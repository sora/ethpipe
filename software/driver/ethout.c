#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/pci.h>

#define	DRV_NAME	"ethout"
#define	DRV_VERSION	"0.0.1"
#define	ETHOUT_DRIVER_NAME	DRV_NAME " Ethout driver " DRV_VERSION

static DEFINE_PCI_DEVICE_TABLE(ethout_pci_tbl) = {
	{0x3776, 0x8001, PCI_ANY_ID, PCI_ANY_ID, 0, 0, 0 },
	{0,}
};
MODULE_DEVICE_TABLE(pci, ethout_pci_tbl);

static unsigned long *mmio_ptr, mmio_start, mmio_end, mmio_flags, mmio_len;

static int ethout_open(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);
	/* */
	return 0;
}

static ssize_t ethout_read(struct file *filp, char __user *buf,
			   size_t count, loff_t *ppos)
{
	int copy_len;

	printk("%s\n", __func__);

	if ( count > 256 )
		copy_len = 256;
	else
		copy_len = count;

	if ( copy_to_user( buf, mmio_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}

	return copy_len;
}

static ssize_t ethout_write(struct file *filp, const char __user *buf,
			    size_t count, loff_t *ppos)

{
	int copy_len;
	if ( count > 256 )
		copy_len = 256;
	else
		copy_len = count;
	printk("%s\n", __func__);

	if ( copy_from_user( mmio_ptr, buf, copy_len ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	return copy_len;
}

static int ethout_release(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);
	return 0;
}

static unsigned int ethout_poll(struct file *filp, poll_table *wait)
{
	printk("%s\n", __func__);
	return 0;
}


static int ethout_ioctl(struct inode *inode, struct file *filp,
			unsigned int cmd, unsigned long arg)
{
	printk("%s\n", __func__);
	return  -ENOTTY;
}

static struct file_operations ethout_fops = {
	.owner		= THIS_MODULE,
	.read		= ethout_read,
	.write		= ethout_write,
	.poll		= ethout_poll,
	.compat_ioctl	= ethout_ioctl,
	.open		= ethout_open,
	.release	= ethout_release,
};

static struct miscdevice ethout_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "ethout",
	.fops = &ethout_fops,
};


static int __devinit ethout_init_one (struct pci_dev *pdev,
				       const struct pci_device_id *ent)
{
	int rc;

	mmio_ptr = 0L;

	rc = pci_enable_device (pdev);
	if (rc)
		goto err_out;

	rc = pci_request_regions (pdev, DRV_NAME);
	if (rc)
		goto err_out;

#if 0
	pci_set_master (pdev);		/* set BUS Master Mode */
#endif

	mmio_start = pci_resource_start (pdev, 0);
	mmio_end   = pci_resource_end   (pdev, 0);
	mmio_flags = pci_resource_flags (pdev, 0);
	mmio_len   = pci_resource_len   (pdev, 0);

	printk( KERN_INFO "mmio_start: %X\n", mmio_start );
	printk( KERN_INFO "mmio_end  : %X\n", mmio_end   );
	printk( KERN_INFO "mmio_flags: %X\n", mmio_flags );
	printk( KERN_INFO "mmio_len  : %X\n", mmio_len   );

	mmio_ptr = ioremap(mmio_start, mmio_len);
	if (!mmio_ptr) {
		printk(KERN_ERR "cannot ioremap MMIO base\n");
		goto err_out;
	}

	/* reset board */

	return 0;

err_out:
	pci_release_regions (pdev);
	pci_disable_device (pdev);
	return -1;
}


static void __devexit ethout_remove_one (struct pci_dev *pdev)
{
	pci_disable_device (pdev);
}


static struct pci_driver ethout_pci_driver = {
	.name		= DRV_NAME,
	.id_table	= ethout_pci_tbl,
	.probe		= ethout_init_one,
	.remove		= __devexit_p(ethout_remove_one),
#ifdef CONFIG_PM
//	.suspend	= ethout_suspend,
//	.resume		= ethout_resume,
#endif /* CONFIG_PM */
};


static int __init ethout_init(void)
{
	int ret;

#ifdef MODULE
	pr_info(ETHOUT_DRIVER_NAME "\n");
#endif

	ret = misc_register(&ethout_dev);
	if (ret) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		return ret;
	}
	
	printk("Succefully loaded.\n");
	return pci_register_driver(&ethout_pci_driver);
}

static void __exit ethout_cleanup(void)
{
	misc_deregister(&ethout_dev);
 	printk("Unloaded.\n"); 
}

MODULE_LICENSE("GPL");
module_init(ethout_init);
module_exit(ethout_cleanup);
