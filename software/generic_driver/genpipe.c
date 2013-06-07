#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/string.h>
#include <linux/pci.h>
#include <linux/wait.h>		/* wait_queue_head_t */
#include <linux/interrupt.h>
#include <linux/version.h>

#include <linux/types.h>
#include <linux/socket.h>
#include <linux/kernel.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/inet.h>
#include <linux/errno.h>
#include <linux/net.h>
#include <linux/in.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/init.h>

#ifndef	DRV_NAME
#define	DRV_NAME	"genpipe"
#endif
#ifndef	IF_NAME
#define	IF_NAME		"eth0"
#endif
#define	DRV_VERSION	"0.0.2"
#define	genpipe_DRIVER_NAME	DRV_NAME " Generic Etherpipe driver " DRV_VERSION

#ifndef	PACKET_BUF_MAX
#define	PACKET_BUF_MAX	(1024*1024)
#endif

#define	MAX_IFR		20	/* Max Ethernet Interfaces */


#if LINUX_VERSION_CODE > KERNEL_VERSION(3,8,0)
#define	__devinit
#define	__devexit
#define	__devexit_p
#endif

static wait_queue_head_t write_q;
static wait_queue_head_t read_q;

/* receive and transmitte buffer */
struct _pbuf_dma {
	unsigned char   *rx_start_ptr;		/* rx buf start */
	unsigned char   *rx_end_ptr;		/* rx buf end */
	unsigned char   *rx_write_ptr;		/* rx write ptr */
	unsigned char   *rx_read_ptr;		/* rx read ptr */
	unsigned char   *tx_start_ptr;		/* tx buf start */
	unsigned char   *tx_end_ptr;		/* tx buf end */
	unsigned char   *tx_write_ptr;		/* tx write ptr */
	unsigned char   *tx_read_ptr;		/* tx read ptr */
} static pbuf0={0,0,0,0,0,0,0,0};

struct ifreq ifr_backup;
struct net_device* device = NULL; 

int genpipe_pack_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt)
{
	int i, frame_len;
	unsigned char *p;

//	if ( strncmp( dev->name, IF_NAME, 5))
//		return 0;

	frame_len = (skb->len)*3+31;
#ifdef DEBUG
	printk(KERN_DEBUG "Test protocol: Packet Received with length: %u\n", skb->len+18);
#endif

	if ( (pbuf0.rx_write_ptr +  frame_len) > pbuf0.rx_end_ptr ) {
		memcpy( pbuf0.rx_start_ptr, pbuf0.rx_write_ptr, (pbuf0.rx_write_ptr - pbuf0.rx_start_ptr ));
		pbuf0.rx_read_ptr -= (pbuf0.rx_write_ptr - pbuf0.rx_start_ptr );
		if ( pbuf0.rx_read_ptr < pbuf0.rx_start_ptr )
			pbuf0.rx_read_ptr = pbuf0.rx_start_ptr;
		pbuf0.rx_write_ptr = pbuf0.rx_start_ptr;
	}

	p = skb_mac_header(skb);
	sprintf(pbuf0.rx_write_ptr, "%02X%02X%02X%02X%02X%02X %02X%02X%02X%02X%02X%02X %02X%02X",
		p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13]); 

	p = skb->data;
	for ( i = 0; i < (skb->len) ; ++i) {
		sprintf(pbuf0.rx_write_ptr+30+i*3, " %02X", p[i] );
	}
	sprintf(pbuf0.rx_write_ptr+30+i*3, "\n");

	pbuf0.rx_write_ptr += frame_len;

	wake_up_interruptible( &read_q );

	return skb->len;
}

static int genpipe_open(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	return 0;
}

static ssize_t genpipe_read(struct file *filp, char __user *buf,
			   size_t count, loff_t *ppos)
{
	int copy_len, available_read_len;
#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	if ( wait_event_interruptible( read_q, ( pbuf0.rx_read_ptr != pbuf0.rx_write_ptr ) ) )
		return -ERESTARTSYS;

	available_read_len = (pbuf0.rx_write_ptr - pbuf0.rx_read_ptr);

	if ( count > available_read_len )
		copy_len = available_read_len;
	else
		copy_len = count;

	if ( copy_to_user( buf, pbuf0.rx_read_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}

	pbuf0.rx_read_ptr += copy_len;

	return copy_len;
}

static ssize_t genpipe_write(struct file *filp, const char __user *buf,
			    size_t count, loff_t *ppos)

{
	int copy_len, available_write_len;
	int i, size, frame_len;
	struct msghdr msg;
	struct iovec iov;
	mm_segment_t oldfs;

	copy_len = 0;

	if ( (pbuf0.tx_write_ptr +  count) > pbuf0.tx_end_ptr ) {
		memcpy( pbuf0.tx_start_ptr, pbuf0.tx_write_ptr, (pbuf0.tx_write_ptr - pbuf0.tx_start_ptr ));
		pbuf0.tx_read_ptr -= (pbuf0.tx_write_ptr - pbuf0.tx_start_ptr );
		if ( pbuf0.tx_read_ptr < pbuf0.tx_start_ptr )
			pbuf0.tx_read_ptr = pbuf0.tx_start_ptr;
		pbuf0.tx_write_ptr = pbuf0.tx_start_ptr;
	}

	if ( count > (pbuf0.tx_end_ptr - pbuf0.tx_write_ptr))
		count = (pbuf0.tx_end_ptr - pbuf0.tx_write_ptr);

//#ifdef DEBUG
	printk("%s count=%d\n", __func__, count);
//#endif

	if ( copy_from_user( pbuf0.tx_write_ptr, buf, count ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	pbuf0.tx_write_ptr += count;
	copy_len = count;

genpipe_write_loop:
	/* looking for magic code */
	available_write_len = (pbuf0.tx_write_ptr - pbuf0.tx_read_ptr);

	for (i = 0; i < available_write_len-1; ++pbuf0.tx_read_ptr, ++i) {
		if (pbuf0.tx_read_ptr[0] == 0x55 && pbuf0.tx_read_ptr[1] == 0xd5)
			break;
	}
	/* does not find magic code */
	if (i == available_write_len - 1) {
		goto genpipe_write_exit;
	}

	available_write_len = (pbuf0.tx_write_ptr - pbuf0.tx_read_ptr);
	if ( available_write_len < 4 ) {
		goto genpipe_write_exit;
	}
	frame_len = *(short *)(pbuf0.tx_read_ptr + 2);
	/* data enough ? */
	if ( available_write_len < ( 16 + frame_len ) ) {
		goto genpipe_write_exit;
	}

//	size = sock_sendmsg( kernel_soc, &msg, frame_len - 4);
//#ifdef DEBUG
//	printk(KERN_WARNING "frame_len=%d, sock_sendmsg=%d\n", frame_len, size);
////#endif
/**********************************/
/* We should use dev_queue_xmit() */
/**********************************/

	pbuf0.tx_read_ptr += (frame_len + 16);

	i = (pbuf0.tx_read_ptr - pbuf0.tx_start_ptr );
	if (i > 0) {
		memcpy( pbuf0.tx_start_ptr, pbuf0.tx_read_ptr, ( pbuf0.tx_write_ptr - pbuf0.tx_read_ptr ) );
		pbuf0.tx_read_ptr -= i;
		pbuf0.tx_write_ptr -= i;
	}
	goto genpipe_write_loop;

genpipe_write_exit:

	return copy_len;
}

static int genpipe_release(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	return 0;
}

static unsigned int genpipe_poll(struct file *filp, poll_table *wait)
{
	printk("%s\n", __func__);
	return 0;
}


static int genpipe_ioctl(struct inode *inode, struct file *filp,
			unsigned int cmd, unsigned long arg)
{
	printk("%s\n", __func__);
	return  -ENOTTY;
}

static struct file_operations genpipe_fops = {
	.owner		= THIS_MODULE,
	.read		= genpipe_read,
	.write		= genpipe_write,
	.poll		= genpipe_poll,
	.compat_ioctl	= genpipe_ioctl,
	.open		= genpipe_open,
	.release	= genpipe_release,
};

static struct miscdevice genpipe_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = DRV_NAME,
	.fops = &genpipe_fops,
};

static struct packet_type genpipe_pack =
{
	__constant_htons(ETH_P_ALL),
	NULL,
	genpipe_pack_rcv,

	(void *) 1,
	NULL
};

static int __init genpipe_init(void)
{
	int ret;

#ifdef MODULE
	pr_info(genpipe_DRIVER_NAME "\n");
#endif
	printk("%s\n", __func__);

	device = dev_get_by_name(&init_net, IF_NAME); 
	if ( !device ) {
		printk(KERN_WARNING "Could not find %s, err %d\n", IF_NAME, ret);
		ret = -1;
		goto error;
	}

	/* Set receive buffer */
	if ( ( pbuf0.rx_start_ptr = kmalloc(PACKET_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		ret = -1;
		goto error;
	}
	pbuf0.rx_end_ptr = (pbuf0.rx_start_ptr + PACKET_BUF_MAX - 1);
	pbuf0.rx_write_ptr = pbuf0.rx_start_ptr;
	pbuf0.rx_read_ptr  = pbuf0.rx_start_ptr;

	/* Set transmitte buffer */
	if ( ( pbuf0.tx_start_ptr = kmalloc(PACKET_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		ret = -1;
		goto error;
	}
	pbuf0.tx_end_ptr = (pbuf0.tx_start_ptr + PACKET_BUF_MAX - 1);
	pbuf0.tx_write_ptr = pbuf0.tx_start_ptr;
	pbuf0.tx_read_ptr  = pbuf0.tx_start_ptr;

	ret = misc_register(&genpipe_dev);
	if (ret) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		goto error;
	}

	init_waitqueue_head( &read_q );
	init_waitqueue_head( &write_q );

	genpipe_pack.dev = device;
	dev_add_pack(&genpipe_pack);

	return 0;

error:
	if ( pbuf0.rx_start_ptr ) {
		kfree( pbuf0.rx_start_ptr );
		pbuf0.rx_start_ptr = NULL;
	}

	if ( pbuf0.tx_start_ptr ) {
		kfree( pbuf0.tx_start_ptr );
		pbuf0.tx_start_ptr = NULL;
	}

	return ret;
}

static void __exit genpipe_cleanup(void)
{
	misc_deregister(&genpipe_dev);

	dev_remove_pack(&genpipe_pack);

	if ( pbuf0.rx_start_ptr ) {
		kfree( pbuf0.rx_start_ptr );
		pbuf0.rx_start_ptr = NULL;
	}

	if ( pbuf0.tx_start_ptr ) {
		kfree( pbuf0.tx_start_ptr );
		pbuf0.tx_start_ptr = NULL;
	}

	printk("%s\n", __func__);
}

MODULE_LICENSE("GPL");
module_init(genpipe_init);
module_exit(genpipe_cleanup);

