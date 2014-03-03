#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/string.h>
#include <linux/pci.h>
#include <linux/wait.h>		/* wait_queue_head_t */
#include <linux/interrupt.h>
#include <linux/version.h>
#include <linux/vmalloc.h>

#ifndef	DRV_NAME
#define	DRV_NAME	"ethpipe"
#endif
#define	DRV_VERSION	"0.0.2"
#define	ethpipe_DRIVER_NAME	DRV_NAME " Etherpipe driver " DRV_VERSION

#ifndef	PACKET_SIZE
//#define	PACKET_SIZE	64
#define	PACKET_SIZE	1518
#endif
#define	PER_BUFFER	((PACKET_SIZE-18)*3+31)

#ifndef	MAX_TEMP_BUF
#define	MAX_TEMP_BUF	(4*1024*1024)
#endif

#if LINUX_VERSION_CODE > KERNEL_VERSION(3,8,0)
#define	__devinit
#define	__devexit
#define	__devexit_p
#endif


static unsigned char *phy0_rx_ptr = 0L;
static unsigned char *phy0_tx_ptr = 0L;

static int phy0_read_pos;

static int ethpipe_open(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);
	phy0_read_pos = 0;
	/* */
	return 0;
}

static ssize_t ethpipe_read(struct file *filp, char __user *buf,
			   size_t count, loff_t *ppos)
{
	int copy_len;
	unsigned int frame_len;

#ifdef DEBUG
	printk("%s:len=%d\n", __func__, count);
#endif

	if ((phy0_read_pos + count) > (MAX_TEMP_BUF - PER_BUFFER))
		copy_len = (MAX_TEMP_BUF - PER_BUFFER) - phy0_read_pos;
	else
		copy_len = count;

	if ( copy_to_user( buf, phy0_rx_ptr + phy0_read_pos, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}

	phy0_read_pos += copy_len;

	phy0_read_pos = phy0_read_pos % (PER_BUFFER * 10);

	return copy_len;
}

static ssize_t ethpipe_write(struct file *filp, const char __user *buf,
			    size_t count, loff_t *ppos)

{
	int copy_len;
	if (count > (MAX_TEMP_BUF - PER_BUFFER))
		count = (MAX_TEMP_BUF - PER_BUFFER);

	copy_len = count;

#ifdef DEBUG
	printk("%s:len=%d\n", __func__, count);
#endif

	if ( copy_from_user( phy0_tx_ptr, buf, copy_len ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	return copy_len;
}

static int ethpipe_release(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);
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
	.name = DRV_NAME,
	.fops = &ethpipe_fops,
};


static int __init ethpipe_init(void)
{
	int ret, i, num;

#ifdef MODULE
	pr_info(ethpipe_DRIVER_NAME "\n");
#endif

	if ( ( phy0_rx_ptr = kmalloc(MAX_TEMP_BUF, GFP_KERNEL | GFP_DMA) ) == 0 ) {
		printk("fail to kmalloc\n");
		return -1;
	}

	if ( ( phy0_tx_ptr = kmalloc(MAX_TEMP_BUF, GFP_KERNEL | GFP_DMA) ) == 0 ) {
		printk("fail to kmalloc\n");
		return -1;
	}

	ret = misc_register(&ethpipe_dev);
	if (ret) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		return ret;
	}

	num = 0;
	for ( i = 0; i < (MAX_TEMP_BUF-PER_BUFFER); ) {
#if PACKET_SIZE == 64
	memcpy( phy0_rx_ptr+i, "FFFFFFFFFFFF 0022CF63967B 8899 23 1E 0A CF E5 3A DF 00 22 CF 63 96 7B 00 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20\n", PER_BUFFER);
#endif
#if PACKET_SIZE == 1518
		memcpy( phy0_rx_ptr+i, "FFFFFFFFFFFF 0022CF63967B 8899 23 1E 0A CF E5 3A DF 00 22 CF 63 96 7B 00 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20\n", PER_BUFFER);
#endif

		switch ( num % 10 ) {
			case 0:  memcpy ( phy0_rx_ptr+i, "001111111111", 12); break;
			case 1:  memcpy ( phy0_rx_ptr+i, "002222222222", 12); break;
			case 2:  memcpy ( phy0_rx_ptr+i, "003333333333", 12); break;
			case 3:  memcpy ( phy0_rx_ptr+i, "004444444444", 12); break;
			case 4:  memcpy ( phy0_rx_ptr+i, "005555555555", 12); break;
			case 5:  memcpy ( phy0_rx_ptr+i, "006666666666", 12); break;
			case 6:  memcpy ( phy0_rx_ptr+i, "007777777777", 12); break;
			case 7:  memcpy ( phy0_rx_ptr+i, "008888888888", 12); break;
			case 8:  memcpy ( phy0_rx_ptr+i, "009999999999", 12); break;
			default: break;
		}
		i += PER_BUFFER;
		++num;
	}
	
	printk("%s\n", __func__);
	return 0;
}

static void __exit ethpipe_cleanup(void)
{
	misc_deregister(&ethpipe_dev);

	if (phy0_rx_ptr)
		kfree(phy0_rx_ptr);

	if (phy0_tx_ptr)
		kfree(phy0_tx_ptr);

	printk("%s\n", __func__);
}

MODULE_LICENSE("GPL");
module_init(ethpipe_init);
module_exit(ethpipe_cleanup);

