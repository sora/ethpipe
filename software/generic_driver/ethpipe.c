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

#define	DRV_NAME	"ethpipe"
#define	DRV_VERSION	"0.0.1"
#define	ethpipe_DRIVER_NAME	DRV_NAME " Generic Etherpipe driver " DRV_VERSION

#define	MAX_TEMP_BUF	(4*1024*1024)


#if LINUX_VERSION_CODE > KERNEL_VERSION(3,8,0)
#define	__devinit
#define	__devexit
#define	__devexit_p
#endif

static unsigned char *buf_ptr = 0L;
struct socket *kernel_soc= NULL;

static int ethpipe_open(struct inode *inode, struct file *filp)
{
	int rc = 0;
	struct ifreq ifr;
	printk("%s\n", __func__);
	/* Create kernel socket */
	rc = sock_create( PF_PACKET, SOCK_RAW, htons(ETH_P_ALL), &kernel_soc );
	if (rc <0) {
		printk(KERN_WARNING "Could not create a PF_PACKET Socket, err %d\n", rc);
		return -1;
	}

	/* Set the IFF_PROMISC flag */
	kernel_sock_ioctl( kernel_soc, SIOCSIFFLAGS, &ifr);
	ifr.ifr_flags |= IFF_PROMISC;
	kernel_sock_ioctl( kernel_soc, SIOCSIFFLAGS, &ifr);

	return 0;
}

static ssize_t ethpipe_read(struct file *filp, char __user *buf,
			   size_t count, loff_t *ppos)
{
	int copy_len, size;
	struct msghdr msg;
	struct iovec iov;
	mm_segment_t oldfs;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif
	iov.iov_base = buf_ptr + (2+2+8+4);
	iov.iov_len = MAX_TEMP_BUF;

	msg.msg_control = NULL;
	msg.msg_controllen = 0;
	msg.msg_flags = 0;
	msg.msg_name = 0;
	msg.msg_namelen = 0;
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;

	oldfs = get_fs();
	set_fs(KERNEL_DS);
	size = sock_recvmsg( kernel_soc, &msg, MAX_TEMP_BUF, msg.msg_flags );
	set_fs( oldfs );
#ifdef DEBUG
	printk(KERN_WARNING "sock_recvmsg=%d\n", size);
#endif

	*(short *)(buf_ptr + 0) = 0xd555;	/* magic code */
	*(short *)(buf_ptr + 2) = size;		/* frame length */
	*(long  *)(buf_ptr + 4) = 0x0;		/* counter */
	*(long  *)(buf_ptr + 12) = 0x0;		/* hash */

	if (count > (size + 16))
		copy_len = (size + 16);

	if ( copy_to_user( buf, buf_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}

	return copy_len;
}

static ssize_t ethpipe_write(struct file *filp, const char __user *buf,
			    size_t count, loff_t *ppos)

{
	int copy_len;
	if (count > (MAX_TEMP_BUF - 169))
		count = (MAX_TEMP_BUF - 169);

	copy_len = count;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	if ( copy_from_user( buf_ptr, buf, copy_len ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	return copy_len;
}

static int ethpipe_release(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	/* Release kernel socket */
	if (kernel_soc) {
		sock_release(kernel_soc);
		kernel_soc = NULL;
	}

	return 0;
}

static unsigned int ethpipe_poll(struct file *filp, poll_table *wait)
{
	printk("%s\n", __func__);
	return 0;
}


static int ethpipe_ioctl(struct inode *inode, struct file *filp,
			unsigned int cmd, unsigned long arg)
{
	printk("%s\n", __func__);
	return  -ENOTTY;
}

static struct file_operations ethpipe_fops = {
	.owner		= THIS_MODULE,
	.read		= ethpipe_read,
	.write		= ethpipe_write,
	.poll		= ethpipe_poll,
	.compat_ioctl	= ethpipe_ioctl,
	.open		= ethpipe_open,
	.release	= ethpipe_release,
};

static struct miscdevice ethpipe_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "ethpipe",
	.fops = &ethpipe_fops,
};


static int __init ethpipe_init(void)
{
	int ret, i, num;

#ifdef MODULE
	pr_info(ethpipe_DRIVER_NAME "\n");
#endif

	ret = misc_register(&ethpipe_dev);
	if (ret) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		return ret;
	}

	if ( ( buf_ptr = kmalloc(MAX_TEMP_BUF, GFP_KERNEL | GFP_DMA) ) == 0 ) {
		printk("fail to kmalloc\n");
		return -1;
	}

	printk("%s\n", __func__);
	return 0;
}

static void __exit ethpipe_cleanup(void)
{
	misc_deregister(&ethpipe_dev);

	if (buf_ptr)
		kfree(buf_ptr);

	printk("%s\n", __func__);
}

MODULE_LICENSE("GPL");
module_init(ethpipe_init);
module_exit(ethpipe_cleanup);

