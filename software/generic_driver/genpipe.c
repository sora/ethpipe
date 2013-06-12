#include <linux/semaphore.h>
#include <linux/etherdevice.h>
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

#include <linux/if_packet.h>

//#define	DEBUG

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
#ifndef	MTU
#define	MTU		(9014)
#endif

static char *interface = IF_NAME;
module_param( interface , charp , S_IRUGO);
MODULE_PARM_DESC( interface, "interface" );

#define	INFO_SKB(X) \
printk( "len=%u,", X->len); \
printk( "data_len=%u,", X->data_len); \
printk( "mac_header=%x,", (unsigned int)X->mac_header); \
printk( "network_header=%x,", (unsigned int)X->network_header); \
printk( "transport_header=%x,", (unsigned int)X->transport_header); \
printk( "*head=%p,", X->head); \
printk( "*data=%p,", X->data); \
printk( "tail=%x,", (unsigned int)X->tail); \
printk( "end=%x\n", (unsigned int)X->end);

#if LINUX_VERSION_CODE > KERNEL_VERSION(3,8,0)
#define	__devinit
#define	__devexit
#define	__devexit_p
#endif

static struct semaphore genpipe_sem;
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

struct net_device* device = NULL; 

int genpipe_pack_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt, struct net_device *dev2)
{
	int i, frame_len;
	unsigned char *p;

	if (skb->pkt_type == PACKET_OUTGOING)	 // DROP loopback PACKET
		goto lend;

	frame_len = (skb->len)*3+31;
#ifdef DEBUG
	printk(KERN_DEBUG "Test protocol: Packet Received with length: %u\n", skb->len+18);
#endif

	if ( down_interruptible( &genpipe_sem ) ) {
		printk( KERN_INFO "down_interruptible for read failed\n" );
		return -ERESTARTSYS;
	}

	if ( (pbuf0.rx_write_ptr +  frame_len) > pbuf0.rx_end_ptr ) {
		memcpy( pbuf0.rx_start_ptr, pbuf0.rx_read_ptr, (pbuf0.rx_write_ptr - pbuf0.rx_start_ptr ));
		pbuf0.rx_write_ptr -= (pbuf0.rx_write_ptr - pbuf0.rx_start_ptr );
		pbuf0.rx_read_ptr = pbuf0.rx_start_ptr;
		if ( pbuf0.rx_read_ptr < pbuf0.rx_start_ptr )
			pbuf0.rx_read_ptr = pbuf0.rx_start_ptr;
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

	up( &genpipe_sem );

lend:
	/* Don't mangle buffer if shared */
	if (!(skb = skb_share_check(skb, GFP_ATOMIC)))
		return 0;

	kfree_skb(skb);
	return skb->len;
}

static int genpipe_open(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);
	rtnl_lock();
	dev_set_promiscuity(device, 1);
	rtnl_unlock();

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
	int i, copy_len, pos, ret, frame_len;
	struct sk_buff *tx_skb;
	unsigned char *cr;
	static unsigned char tmp_pkt[MTU+14]={0,0,0,0,0,0,0,0,0,0,0,0,0,0};

	copy_len = 0;
	tx_skb = NULL;

	if ( (pbuf0.tx_write_ptr +  count) > pbuf0.tx_end_ptr ) {
		memcpy( pbuf0.tx_start_ptr, pbuf0.tx_read_ptr, (pbuf0.tx_write_ptr - pbuf0.tx_start_ptr ));
		pbuf0.tx_write_ptr -= (pbuf0.tx_write_ptr - pbuf0.tx_start_ptr );
		pbuf0.tx_read_ptr = pbuf0.tx_start_ptr;
		if ( pbuf0.tx_read_ptr < pbuf0.tx_start_ptr )
			pbuf0.tx_read_ptr = pbuf0.tx_start_ptr;
	}

	if ( count > (pbuf0.tx_end_ptr - pbuf0.tx_write_ptr))
		count = (pbuf0.tx_end_ptr - pbuf0.tx_write_ptr);

#ifdef DEBUG
	printk("%s count=%d\n", __func__, count);
#endif

	if ( copy_from_user( pbuf0.tx_write_ptr, buf, count ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	pbuf0.tx_write_ptr += count;
	copy_len = count;

genpipe_write_loop:
	for ( cr = pbuf0.tx_read_ptr; cr < pbuf0.tx_write_ptr && *cr != '\n'; ++cr );
	if ( cr == pbuf0.tx_write_ptr )	/* not found CR */
		goto genpipe_write_exit;

#ifdef DEBUG
	printk( "pbuf0.tx_read_ptr=%s\n", pbuf0.tx_read_ptr);
#endif
	frame_len = 0;
	pos = 0;

	for ( ; pbuf0.tx_read_ptr < cr && frame_len < MTU ; ++pbuf0.tx_read_ptr ) {
		// skip space
		if (*pbuf0.tx_read_ptr == ' ')
			continue;
		// conver to upper char
		if (*pbuf0.tx_read_ptr >= 'a' && *pbuf0.tx_read_ptr <= 'z')
			*pbuf0.tx_read_ptr -= 0x20;
		// is hexdigit?
		if (*pbuf0.tx_read_ptr >= '0' && *pbuf0.tx_read_ptr <= '9') {
			if ( pos == 0 ) {
				tmp_pkt[frame_len+14] = (*pbuf0.tx_read_ptr - '0') << 4;
				pos = 1;
			} else {
				tmp_pkt[frame_len+14] |= (*pbuf0.tx_read_ptr - '0');
				++frame_len;
				pos = 0;
			}
		} else if (*pbuf0.tx_read_ptr >= 'A' && *pbuf0.tx_read_ptr <= 'Z') {
			if ( pos == 0 ) {
				tmp_pkt[frame_len+14] = (*pbuf0.tx_read_ptr - 'A' + 10) << 4;
				pos = 1;
			} else {
				tmp_pkt[frame_len+14] |= (*pbuf0.tx_read_ptr - 'A' + 10);
				++frame_len;
				pos = 0;
			}
		}
	}

#ifdef DEBUG
printk( "%02x%02x%02x%02x%02x%02x %02x%02x%02x%02x%02x%02x %02x%02x %02x %02x\n", 
	tmp_pkt[14], tmp_pkt[15], tmp_pkt[16], tmp_pkt[17], tmp_pkt[18], tmp_pkt[19],
	tmp_pkt[20], tmp_pkt[21], tmp_pkt[22], tmp_pkt[23], tmp_pkt[24], tmp_pkt[25],
	tmp_pkt[26], tmp_pkt[27],
	tmp_pkt[27], tmp_pkt[28]);
#endif

	tx_skb = netdev_alloc_skb_ip_align(device, frame_len+14);
	skb_reserve(tx_skb, 2);	/* align IP on 16B boundary */
	if (likely(tx_skb)) {
#ifdef DEBUG
INFO_SKB(tx_skb);
#endif

		skb_reset_mac_header(tx_skb);
		skb_reset_transport_header(tx_skb);
		skb_reset_network_header(tx_skb);
		memcpy(skb_put(tx_skb, frame_len+14), tmp_pkt, frame_len+14);
//		skb_set_mac_header(tx_skb,14);
//		skb_set_transport_header(tx_skb,20);
		skb_set_network_header(tx_skb,38);
#ifdef DEBUG
INFO_SKB(tx_skb);
#endif
		tx_skb->dev = device;
		tx_skb->protocol = eth_type_trans(tx_skb, device);
		ret = dev_queue_xmit(tx_skb);
		if (ret) {
			printk("fail to dev_queue_xmit=%d\n", ret);
		}
	}

	pbuf0.tx_read_ptr = cr + 1;

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
	rtnl_lock();
	dev_set_promiscuity(device, -1);
	rtnl_unlock();

	return 0;
}

static unsigned int genpipe_poll( struct file* filp, poll_table* wait )
{
	unsigned int retmask = 0;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	poll_wait( filp, &read_q,  wait );
//	poll_wait( filp, &write_q, wait );

	if ( pbuf0.rx_read_ptr != pbuf0.rx_write_ptr ) {
		retmask |= ( POLLIN  | POLLRDNORM );
//		log_format( "POLLIN  | POLLRDNORM" );
	}
/* 
   読み込みデバイスが EOF の場合は retmask に POLLHUP を設定
   デバイスがエラー状態である場合は POLLERR を設定
   out-of-band データが読み出せる場合は POLLPRI を設定
 */

	return retmask;
}


static long genpipe_ioctl(struct file *filp,
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

	device = dev_get_by_name(&init_net, interface); 
	if ( !device ) {
		printk(KERN_WARNING "Could not find %s\n", interface);
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

	sema_init( &genpipe_sem, 1 );
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

