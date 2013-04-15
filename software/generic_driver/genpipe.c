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

#define	DRV_NAME	"genpipe"
#define	DRV_VERSION	"0.0.1"
#define	genpipe_DRIVER_NAME	DRV_NAME " Generic Etherpipe driver " DRV_VERSION

#define	PACKET_BUF_MAX	(1024*1024)


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
} static pbuf0={0,0,0,0,0};

struct socket *kernel_soc= NULL;

int genpipe_pack_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt)
{
	int frame_len;
	frame_len = skb->len + 18;
#ifdef DEBUG
	printk(KERN_DEBUG "Test protocol: Packet Received with length: %u\n", frame_len);
#endif


	if ( (pbuf0.rx_write_ptr +  frame_len + 0x10) > pbuf0.rx_end_ptr ) {
		memcpy( pbuf0.rx_start_ptr, pbuf0.rx_write_ptr, (pbuf0.rx_write_ptr - pbuf0.rx_start_ptr ));
		pbuf0.rx_read_ptr -= (pbuf0.rx_write_ptr - pbuf0.rx_start_ptr );
		if ( pbuf0.rx_read_ptr < pbuf0.rx_start_ptr )
			pbuf0.rx_read_ptr = pbuf0.rx_start_ptr;
		pbuf0.rx_write_ptr = pbuf0.rx_start_ptr;
	}

	*(short *)(pbuf0.rx_write_ptr + 0) = 0xd555;		/* magic code 0x55d5 */
	*(short *)(pbuf0.rx_write_ptr + 2) = frame_len;		/* frame len */
	*(long long *)(pbuf0.rx_write_ptr + 4) = 0;		/* counter */
	*(long *)(pbuf0.rx_write_ptr + 0xc) = 0;		/* hash */

//	memcpy(pbuf0.rx_write_ptr+0x10, skb->head + skb->mac_header, frame_len);
	memcpy(pbuf0.rx_write_ptr+0x10, skb->head + skb->mac_header, 14);
	memcpy(pbuf0.rx_write_ptr+0x1e, skb->data, skb->len);
	*(long *)(pbuf0.rx_write_ptr + 0xc + frame_len) = 0;	/* FCS */

	pbuf0.rx_write_ptr += (frame_len + 0x10);

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
	int copy_len, size, available_read_len;
//	struct msghdr msg;
//	struct iovec iov;
//	mm_segment_t oldfs;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif
#if 0
	iov.iov_base = buf_ptr + (2+2+8+4);
	iov.iov_len = PACKET_BUF_MAX;

	msg.msg_control = NULL;
	msg.msg_controllen = 0;
	msg.msg_flags = 0;
	msg.msg_name = 0;
	msg.msg_namelen = 0;
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;

	oldfs = get_fs();
	set_fs(KERNEL_DS);
	size = sock_recvmsg( kernel_soc, &msg, PACKET_BUF_MAX, msg.msg_flags );
	set_fs( oldfs );
#endif
#ifdef DEBUG
	printk(KERN_WARNING "sock_recvmsg=%d\n", size);
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
	int copy_len;
	if (count > (PACKET_BUF_MAX - 169))
		count = (PACKET_BUF_MAX - 169);

	copy_len = count;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

//	if ( copy_from_user( pbuf0.tx_write_ptr, buf, copy_len ) ) {
//		printk( KERN_INFO "copy_from_user failed\n" );
//		return -EFAULT;
//	}

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
	.name = "genpipe",
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
	struct ifreq ifr;

#ifdef MODULE
	pr_info(genpipe_DRIVER_NAME "\n");
#endif
	printk("%s\n", __func__);

	ret = misc_register(&genpipe_dev);
	if (ret) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		return ret;
	}

	if ( ( pbuf0.rx_start_ptr = kmalloc(PACKET_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		return -1;
	}
	pbuf0.rx_end_ptr = (pbuf0.rx_start_ptr + PACKET_BUF_MAX - 1);
	pbuf0.rx_write_ptr = pbuf0.rx_start_ptr;
	pbuf0.rx_read_ptr  = pbuf0.rx_start_ptr;

	init_waitqueue_head( &write_q );
	init_waitqueue_head( &read_q );

	dev_add_pack(&genpipe_pack);

	/* Create kernel socket */
	ret = sock_create( PF_PACKET, SOCK_RAW, htons(ETH_P_ALL), &kernel_soc );
	if (ret <0) {
		printk(KERN_WARNING "Could not create a PF_PACKET Socket, err %d\n", ret);
		return -1;
	}

	/* Set the IFF_PROMISC flag */
	kernel_sock_ioctl( kernel_soc, SIOCSIFFLAGS, &ifr);
	ifr.ifr_flags |= IFF_PROMISC;
	kernel_sock_ioctl( kernel_soc, SIOCSIFFLAGS, &ifr);

	return 0;
}

static void __exit genpipe_cleanup(void)
{
	/* Release kernel socket */
	if (kernel_soc) {
		sock_release(kernel_soc);
		kernel_soc = NULL;
	}

	misc_deregister(&genpipe_dev);

	dev_remove_pack(&genpipe_pack);

	if ( pbuf0.rx_start_ptr )
		kfree( pbuf0.rx_start_ptr );

	printk("%s\n", __func__);
}

MODULE_LICENSE("GPL");
module_init(genpipe_init);
module_exit(genpipe_cleanup);

