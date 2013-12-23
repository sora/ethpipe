#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/string.h>
#include <linux/pci.h>
#include <linux/wait.h>		/* wait_queue_head_t */
#include <linux/sched.h>	/* wait_event_interruptible, wake_up_interruptible, tasklet */
#include <linux/interrupt.h>
#include <linux/version.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
//#include <linux/ctype.h>

MODULE_LICENSE( "GPL" );


#define	USE_TIMER
#define DROP_FCS

#ifndef DRV_NAME
#define DRV_NAME	"ethpipe"
#endif

#ifndef TX_WRITE_PTR_ADDRESS
#define TX_WRITE_PTR_ADDRESS		(0x30)
#endif

#ifndef TX_READ_PTR_ADDRESS
#define TX_READ_PTR_ADDRESS		(0x34)
#endif

#define	DRV_VERSION			"0.2.1"
#define	ethpipe_DRIVER_NAME	DRV_NAME " Etherpipe driver " DRV_VERSION
#define	DMA_BUF_MAX			(1024*1024)
#define	ASCII_BUF_MAX			(DMA_BUF_MAX*3)
#define	BINARY_BUF_MAX			(DMA_BUF_MAX*1)

#define ETHPIPE_HEADER_LEN		(14)
#define MAX_FRAME_LEN			(9014)

#if LINUX_VERSION_CODE > KERNEL_VERSION(3,8,0)
#define	__devinit
#define	__devexit
#define	__devexit_p
#endif

//#define DEBUG

#define _SKP    0x20

static const unsigned char _atob[] = {
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 0-7 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 8-15 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 16-23 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 24-31 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 32-39 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 40-47 */
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,     /* 48-55 */
	0x08, 0x09, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 56-63 */
	_SKP, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, _SKP,     /* 64-71 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 72-79 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 80-87 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 88-95 */
	_SKP, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, _SKP,     /* 96-103 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 104-111 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 112-119 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 120-127 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 128-135 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 136-143 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 144-151 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 152-159 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 160-167 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 168-175 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 176-183 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 184-191 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 192-199 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 200-207 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 208-215 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 216-223 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 224-231 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 232-239 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP,     /* 240-247 */
	_SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP, _SKP };   /* 248-255 */

static const short _btoa[257] = {
	0x3030, 0x3130, 0x3230, 0x3330, 0x3430, 0x3530, 0x3630, 0x3730,     /* 0-7 */
	0x3830, 0x3930, 0x4130, 0x4230, 0x4330, 0x4430, 0x4530, 0x4630,     /* 8-15 */
	0x3031, 0x3131, 0x3231, 0x3331, 0x3431, 0x3531, 0x3631, 0x3731,     /* 16-23 */
	0x3831, 0x3931, 0x4131, 0x4231, 0x4331, 0x4431, 0x4531, 0x4631,     /* 24-31 */
	0x3032, 0x3132, 0x3232, 0x3332, 0x3432, 0x3532, 0x3632, 0x3732,     /* 32-39 */
	0x3832, 0x3932, 0x4132, 0x4232, 0x4332, 0x4432, 0x4532, 0x4632,     /* 40-47 */
	0x3033, 0x3133, 0x3233, 0x3333, 0x3433, 0x3533, 0x3633, 0x3733,     /* 48-55 */
	0x3833, 0x3933, 0x4133, 0x4233, 0x4333, 0x4433, 0x4533, 0x4633,     /* 56-63 */
	0x3034, 0x3134, 0x3234, 0x3334, 0x3434, 0x3534, 0x3634, 0x3734,     /* 64-71 */
	0x3834, 0x3934, 0x4134, 0x4234, 0x4334, 0x4434, 0x4534, 0x4634,     /* 72-79 */
	0x3035, 0x3135, 0x3235, 0x3335, 0x3435, 0x3535, 0x3635, 0x3735,     /* 80-87 */
	0x3835, 0x3935, 0x4135, 0x4235, 0x4335, 0x4435, 0x4535, 0x4635,     /* 88-95 */
	0x3036, 0x3136, 0x3236, 0x3336, 0x3436, 0x3536, 0x3636, 0x3736,     /* 96-103 */
	0x3836, 0x3936, 0x4136, 0x4236, 0x4336, 0x4436, 0x4536, 0x4636,     /* 104-111 */
	0x3037, 0x3137, 0x3237, 0x3337, 0x3437, 0x3537, 0x3637, 0x3737,     /* 112-119 */
	0x3837, 0x3937, 0x4137, 0x4237, 0x4337, 0x4437, 0x4537, 0x4637,     /* 120-127 */
	0x3038, 0x3138, 0x3238, 0x3338, 0x3438, 0x3538, 0x3638, 0x3738,     /* 128-135 */
	0x3838, 0x3938, 0x4138, 0x4238, 0x4338, 0x4438, 0x4538, 0x4638,     /* 136-143 */
	0x3039, 0x3139, 0x3239, 0x3339, 0x3439, 0x3539, 0x3639, 0x3739,     /* 144-151 */
	0x3839, 0x3939, 0x4139, 0x4239, 0x4339, 0x4439, 0x4539, 0x4639,     /* 152-159 */
	0x3041, 0x3141, 0x3241, 0x3341, 0x3441, 0x3541, 0x3641, 0x3741,     /* 160-167 */
	0x3841, 0x3941, 0x4141, 0x4241, 0x4341, 0x4441, 0x4541, 0x4641,     /* 168-175 */
	0x3042, 0x3142, 0x3242, 0x3342, 0x3442, 0x3542, 0x3642, 0x3742,     /* 176-183 */
	0x3842, 0x3942, 0x4142, 0x4242, 0x4342, 0x4442, 0x4542, 0x4642,     /* 184-191 */
	0x3043, 0x3143, 0x3243, 0x3343, 0x3443, 0x3543, 0x3643, 0x3743,     /* 192-199 */
	0x3843, 0x3943, 0x4143, 0x4243, 0x4343, 0x4443, 0x4543, 0x4643,     /* 200-207 */
	0x3044, 0x3144, 0x3244, 0x3344, 0x3444, 0x3544, 0x3644, 0x3744,     /* 208-215 */
	0x3844, 0x3944, 0x4144, 0x4244, 0x4344, 0x4444, 0x4544, 0x4644,     /* 216-223 */
	0x3045, 0x3145, 0x3245, 0x3345, 0x3445, 0x3545, 0x3645, 0x3745,     /* 224-231 */
	0x3845, 0x3945, 0x4145, 0x4245, 0x4345, 0x4445, 0x4545, 0x4645,     /* 232-239 */
	0x3046, 0x3146, 0x3246, 0x3346, 0x3446, 0x3546, 0x3646, 0x3746,     /* 240-247 */
	0x3846, 0x3946, 0x4146, 0x4246, 0x4346, 0x4446, 0x4546, 0x4646 };   /* 248-255 */


static DEFINE_PCI_DEVICE_TABLE(ethpipe_pci_tbl) = {
	{0x3776, 0x8001, PCI_ANY_ID, PCI_ANY_ID, 0, 0, 0 },
	{0,}
};
MODULE_DEVICE_TABLE(pci, ethpipe_pci_tbl);

static unsigned char *mmio0_ptr = 0L, *mmio1_ptr = 0L, *dma1_virt_ptr = 0L, *dma2_virt_ptr = 0L;
static unsigned long long mmio0_start, mmio0_end, mmio0_flags, mmio0_len;
static unsigned long long mmio1_start, mmio1_end, mmio1_flags, mmio1_len;

static dma_addr_t dma1_phys_ptr = 0L, dma2_phys_ptr;
static long *dma1_addr_start, *dma2_addr_start;
static long *dma1_addr_cur, *dma2_addr_cur;
static long long dma1_addr_read_ascii, dma1_addr_read_binary, dma2_addr_read;

static unsigned short *tx_write_ptr;
static unsigned short *tx_read_ptr;

static struct pci_dev *pcidev = NULL;
static wait_queue_head_t write_q_ascii, write_q_binary;
static wait_queue_head_t read_q_ascii, read_q_binary;

static int open_count_ascii = 0, open_count_binary = 0;

static unsigned long long *global_time_ptr;
static unsigned long long *local_time1_ptr, *local_time2_ptr, *local_time3_ptr, *local_time4_ptr,
						  *local_time5_ptr, *local_time6_ptr, *local_time7_ptr;
static struct kobject *ethpipe_kobj;

/* receive and transmitte buffer */
struct _pbuf_dma {
	unsigned char   *rx_start_ascii_ptr;	/* rx buf ascii start */
	unsigned char   *rx_start_binary_ptr;	/* rx buf binary start */
	unsigned char   *rx_end_ascii_ptr;	/* rx buf ascii end */
	unsigned char   *rx_end_binary_ptr;	/* rx buf binary end */
	unsigned char   *rx_write_ascii_ptr;	/* rx write ascii ptr */
	unsigned char   *rx_write_binary_ptr;	/* rx write binary ptr */
	unsigned char   *rx_read_ascii_ptr;	/* rx read ascii ptr */
	unsigned char   *rx_read_binary_ptr;	/* rx read binary ptr */
	unsigned char   *tx_start_ptr;	/* tx buf start */
	unsigned char   *tx_end_ptr;	/* tx buf end */
	unsigned char   *tx_write_ptr;	/* tx write ptr */
	unsigned char   *tx_read_ptr;	/* tx read ptr */
	spinlock_t	lock;
} static pbuf0={0,0,0,0,0,0,0,0};


/* sysfs */

static ssize_t global_time_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%llX\n", *global_time_ptr);
}

#if 0
static ssize_t global_time_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
	sscanf(buf, "%llX", global_time_ptr);
	return count;
}
#endif

static ssize_t local_time1_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%llX\n", *local_time1_ptr);
}

static ssize_t local_time1_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
	sscanf(buf, "%llX", local_time1_ptr);
	return count;
}

static ssize_t local_time2_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%llX\n", *local_time2_ptr);
}

static ssize_t local_time2_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
	sscanf(buf, "%llX", local_time2_ptr);
	return count;
}

static struct kobj_attribute global_time_attribute = __ATTR(global_time, 0666, global_time_show, NULL);
static struct kobj_attribute local_time1_attribute = __ATTR(local_time1, 0666, local_time1_show, local_time1_store);
static struct kobj_attribute local_time2_attribute = __ATTR(local_time2, 0666, local_time2_show, local_time2_store);

static struct attribute *attrs[] = {
	&global_time_attribute.attr,
	&local_time1_attribute.attr,
	&local_time2_attribute.attr,
	NULL,   /* need to NULL terminate the list of attributes */
};
static struct attribute_group attr_group = {
	.attrs = attrs,
};


static void tasklet_body( unsigned long value );
DECLARE_TASKLET( tasklet_fire_led, tasklet_body, ( unsigned long )NULL );

static spinlock_t tasklet_spinlock;


static irqreturn_t ethpipe_interrupt(int irq, void *pdev)
{
	int status;
	int handled = 0;

#if 0
	printk("%s\n", __func__);
#endif
//        spin_lock (&pbuf0.lock);

	status = *(mmio0_ptr + 0x10);
	// is ethpipe interrupt?
	if ( unlikely((status & 8) == 0) ) {
		goto lend;
	}

	handled = 1;

	tasklet_schedule( &tasklet_fire_led );

	// clear interrupt flag
	*(mmio0_ptr + 0x10) = status & 0xf7; 

lend:
//	spin_unlock (&pbuf0.lock);
	return IRQ_RETVAL(handled);
}

void  tasklet_body( unsigned long value )
{
	int i;
//	int status;
	unsigned long flags;
	unsigned short frame_len;
	static long long dma1_addr_write_ascii;
	static int dma1_overflow, mem1_overflow = -1;
	long long dma1_value;
//	int pkt_count = 0;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	spin_lock_irqsave( &tasklet_spinlock, flags );

	dma1_value = (long)*dma1_addr_cur;
	dma1_addr_write_ascii = (dma1_value & 0x0fffffff) | (dma1_phys_ptr  & 0xf0000000);
	dma1_overflow = dma1_value >> 28;
//printk( "dma1_addr_write_ascii = %X\n", dma1_addr_write_ascii );
	if ( unlikely( mem1_overflow < 0 ) ) {
		mem1_overflow = dma1_overflow;
	}

	// for ASCII Interface
	if ( open_count_ascii ) {
		while ( dma1_addr_write_ascii != dma1_addr_read_ascii ) {
			unsigned char *read_ptr, *read_end, *p;

			read_ptr = dma1_virt_ptr + (int)(dma1_addr_read_ascii - dma1_phys_ptr);
			read_end = dma1_virt_ptr + DMA_BUF_MAX - 1;
			p = read_ptr;
		
			frame_len = *(unsigned short *)(p + 0);

#ifdef DEBUG
			printk( "frame_len=%4d\n", frame_len );
#endif
			if ( unlikely(frame_len == 0 || frame_len > 1518) ) {
				printk( "invalid: frame_len=%4d\n", frame_len );
				dma1_addr_read_ascii = ((long)*dma1_addr_cur & 0x0fffffff) | (dma1_phys_ptr  & 0xf0000000);
//printk( "dma1_addr_read_ascii = %X\n", dma1_addr_read_ascii );
				goto lend;
			}

			// check dma or ascii ring buffer overflow ?
			if ( unlikely( ((pbuf0.rx_write_ascii_ptr + (14*2) + 3 + (frame_len-14)*3 + 0x10) > pbuf0.rx_end_ascii_ptr ) || ( ( p + frame_len + 0x10 ) > read_end ) ) ) {

				// global counter
#ifdef USE_TIMER
				p += 0x08;
				if ( unlikely( p > read_end ) ) {
					p -= DMA_BUF_MAX;
					mem1_overflow = (mem1_overflow + 1) & 0xf;
					if ( unlikely( mem1_overflow != dma1_overflow ) ) {
						printk( "dma1 ring overflow: mem=%d, dma=%d\n", mem1_overflow, dma1_overflow );
					}
				}
				for ( i = 0; i < 8; ++i ) {
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = _btoa[ i > 1 ? *p : 0 ];
					pbuf0.rx_write_ascii_ptr += 2;
					if ( unlikely(pbuf0.rx_write_ascii_ptr > pbuf0.rx_end_ascii_ptr) )
						pbuf0.rx_write_ascii_ptr -= ASCII_BUF_MAX;
					if ( unlikely( i == 7 ) ) {
						*pbuf0.rx_write_ascii_ptr++ = ' ';
						if ( unlikely(pbuf0.rx_write_ascii_ptr > pbuf0.rx_end_ascii_ptr) )
							pbuf0.rx_write_ascii_ptr -= ASCII_BUF_MAX;
					}
					++p;
					if ( unlikely( p > read_end ) ) {
						p -= DMA_BUF_MAX;
						mem1_overflow = (mem1_overflow + 1) & 0xf;
						if ( unlikely( mem1_overflow != dma1_overflow ) ) {
							printk( "dma1 ring overflow: mem=%d, dma=%d\n", mem1_overflow, dma1_overflow );
						}
					}
				}
#else
				p += 0x10;
				if ( unlikely( p > read_end ) ) {
					p -= DMA_BUF_MAX;
					mem1_overflow = (mem1_overflow + 1) & 0xf;
					if ( unlikely( mem1_overflow != dma1_overflow ) ) {
						printk( "dma1 ring overflow: mem=%d, dma=%d\n", mem1_overflow, dma1_overflow );
					}
				}
#endif

				// L2 header
				for ( i = 0; i < 14; ++i ) {
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = _btoa[ *p ];
					pbuf0.rx_write_ascii_ptr += 2;
					if ( unlikely( pbuf0.rx_write_ascii_ptr > pbuf0.rx_end_ascii_ptr ) )
						pbuf0.rx_write_ascii_ptr -= ASCII_BUF_MAX;
					if ( unlikely( i == 5 || i== 11 || i == 13 ) ) {
						*pbuf0.rx_write_ascii_ptr++ = ' ';
						if ( unlikely( pbuf0.rx_write_ascii_ptr > pbuf0.rx_end_ascii_ptr ) )
							pbuf0.rx_write_ascii_ptr -= ASCII_BUF_MAX;
					}
					++p;
					if ( unlikely( p > read_end ) ) {
						p -= DMA_BUF_MAX;
						mem1_overflow = (mem1_overflow + 1) & 0xf;
						if ( unlikely( mem1_overflow != dma1_overflow ) ) {
							printk( "dma1 ring overflow: mem=%d, dma=%d\n", mem1_overflow, dma1_overflow );
						}
					}
				}
	
				// L3 header
#ifdef DROP_FCS
				for ( i = 0; i < (frame_len-14-4) ; ++i) {
#else
				for ( i = 0; i < (frame_len-14) ; ++i) {
#endif
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = _btoa[ *p ];
					pbuf0.rx_write_ascii_ptr += 2;
					if ( unlikely(pbuf0.rx_write_ascii_ptr > pbuf0.rx_end_ascii_ptr) )
						pbuf0.rx_write_ascii_ptr -= ASCII_BUF_MAX;
					*pbuf0.rx_write_ascii_ptr++ = ' ';
					if ( unlikely(pbuf0.rx_write_ascii_ptr > pbuf0.rx_end_ascii_ptr) )
						pbuf0.rx_write_ascii_ptr -= ASCII_BUF_MAX;
					++p;
					if ( unlikely( p > read_end ) ) {
						p -= DMA_BUF_MAX;
						mem1_overflow = (mem1_overflow + 1) & 0xf;
						if ( unlikely( mem1_overflow != dma1_overflow ) ) {
							printk( "dma1 ring overflow: mem=%d, dma=%d\n", mem1_overflow, dma1_overflow );
						}
					}
				}
				if ( likely( pbuf0.rx_write_ascii_ptr != pbuf0.rx_start_ascii_ptr ) )
					*(pbuf0.rx_write_ascii_ptr-1) = '\n';
				else
					*(pbuf0.rx_end_ascii_ptr) = '\n';
#ifdef DROP_FCS
				p += 4;
				if ( unlikely( p > read_end ) ) {
					p -= DMA_BUF_MAX;
					mem1_overflow = (mem1_overflow + 1) & 0xf;
					if ( unlikely( mem1_overflow != dma1_overflow ) ) {
						printk( "dma1 ring overflow: mem=%d, dma=%d\n", mem1_overflow, dma1_overflow );
					}
				}
#endif

				if ( likely((long long)p & 0xf) )
					p = (unsigned char *)(((long long)p + 0xf) & 0xfffffffffffffff0);
				if ( unlikely( p > read_end ) ) {
					p -= DMA_BUF_MAX;
					mem1_overflow = (mem1_overflow + 1) & 0xf;
					if ( unlikely( mem1_overflow != dma1_overflow ) ) {
						printk( "dma1 ring overflow: mem=%d, dma=%d\n", mem1_overflow, dma1_overflow );
					}
				}
				dma1_addr_read_ascii = (long long)dma1_phys_ptr + (int)(p - dma1_virt_ptr);
			} else {
				// global counter
#ifdef USE_TIMER
				p += 0x08;
				for ( i = 0; i < 8; ++i ) {
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = _btoa[ i > 1 ? *p : 0 ];
					pbuf0.rx_write_ascii_ptr += 2;
					if ( unlikely( i == 7 ) ) {
						*pbuf0.rx_write_ascii_ptr++ = ' ';
					}
					++p;
				}
#else
				p += 0x10;
#endif

				// L2 header
				for ( i = 0; i < 14; ++i ) {
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = _btoa[ *p ];
					pbuf0.rx_write_ascii_ptr += 2;
					if ( unlikely( i == 5 || i== 11 || i == 13 ) ) {
						*pbuf0.rx_write_ascii_ptr++ = ' ';
					}
					++p;
				}
	
				// L3 header
#ifdef DROP_FCS
				for ( i = 0; i < (frame_len-14-4) ; ++i) {
#else
				for ( i = 0; i < (frame_len-14) ; ++i) {
#endif
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = _btoa[ *p ];
					pbuf0.rx_write_ascii_ptr += 2;
					*pbuf0.rx_write_ascii_ptr++ = ' ';
					++p;
				}
				if ( likely( pbuf0.rx_write_ascii_ptr != pbuf0.rx_start_ascii_ptr ) )
					*(pbuf0.rx_write_ascii_ptr-1) = '\n';
				else
					*(pbuf0.rx_end_ascii_ptr) = '\n';
#ifdef DROP_FCS
				p += 4;
#endif

				if ( likely((long long)p & 0xf) )
					p = (unsigned char *)(((long long)p + 0xf) & 0xfffffffffffffff0);
				dma1_addr_read_ascii = (long long)dma1_phys_ptr + (int)(p - dma1_virt_ptr);
			}
		}

		wake_up_interruptible( &read_q_ascii );
	}


	// for BINARY Interface
	if ( open_count_binary ) {
		while ( *dma1_addr_cur != dma1_addr_read_binary ) {
			unsigned char *read_ptr, *read_end, *p;

			read_ptr = dma1_virt_ptr + (int)(dma1_addr_read_binary - dma1_phys_ptr);
			read_end = dma1_virt_ptr + DMA_BUF_MAX - 1;
			p = read_ptr;
		
			frame_len = *(unsigned short *)(p + 0);

#ifdef DEBUG
			printk( "frame_len=%4d\n", frame_len );
#endif
			if (frame_len == 0 || frame_len > 1518) {
				printk( "invalid: frame_len=%4d\n", frame_len );
				dma1_addr_read_binary = (long)*dma1_addr_cur;
				goto lend;
			}

			if ( (pbuf0.rx_write_binary_ptr + frame_len + 0x10) > pbuf0.rx_end_binary_ptr ) {
				if (pbuf0.rx_read_binary_ptr == pbuf0.rx_start_binary_ptr)
					pbuf0.rx_read_binary_ptr = pbuf0.rx_write_binary_ptr;
				memcpy( pbuf0.rx_start_binary_ptr, pbuf0.rx_read_binary_ptr, (pbuf0.rx_write_binary_ptr - pbuf0.rx_read_binary_ptr ));
				pbuf0.rx_write_binary_ptr = pbuf0.rx_start_binary_ptr + (pbuf0.rx_write_binary_ptr - pbuf0.rx_read_binary_ptr );
				pbuf0.rx_read_binary_ptr = pbuf0.rx_start_binary_ptr;
			}

			// length and SFD
			for ( i = 0; i < 8; ++i ) {
				*(unsigned char *)pbuf0.rx_write_binary_ptr = *p;
				pbuf0.rx_write_binary_ptr += 1;
				if ( unlikely( pbuf0.rx_write_binary_ptr > pbuf0.rx_end_binary_ptr ) )
					pbuf0.rx_write_binary_ptr -= (pbuf0.rx_end_binary_ptr - pbuf0.rx_start_binary_ptr + 1);
				if ( unlikely( ++p > read_end ) )
					p -= DMA_BUF_MAX;
			}
			// global counter
#ifdef USE_TIMER
			for ( i = 0; i < 8; ++i ) {
				*(unsigned char *)pbuf0.rx_write_binary_ptr = i > 2 ? *p : 0;
				pbuf0.rx_write_binary_ptr += 1;
				if ( unlikely( pbuf0.rx_write_binary_ptr > pbuf0.rx_end_binary_ptr ) )
					pbuf0.rx_write_binary_ptr -= (pbuf0.rx_end_binary_ptr - pbuf0.rx_start_binary_ptr + 1);
				if ( unlikely( ++p > read_end ) )
					p -= DMA_BUF_MAX;
			}
#else
			p += 0x08;
			if ( unlikely( p > read_end ) )
				p -= DMA_BUF_MAX;
#endif

			// Packet
#ifdef DROP_FCS
			for ( i = 0; i < (frame_len-4) ; ++i) {
#else
			for ( i = 0; i < (frame_len) ; ++i) {
#endif
				*(unsigned char *)pbuf0.rx_write_binary_ptr =*p;
				pbuf0.rx_write_binary_ptr += 1;
				if ( unlikely( pbuf0.rx_write_binary_ptr > pbuf0.rx_end_binary_ptr ) )
					pbuf0.rx_write_binary_ptr -= (pbuf0.rx_end_binary_ptr - pbuf0.rx_start_binary_ptr + 1);
				if ( unlikely( ++p > read_end ) )
					p -= DMA_BUF_MAX;
			}
#ifdef DROP_FCS
			p += 4;
			if ( unlikely( p > read_end ) )
				p -= DMA_BUF_MAX;
#endif

			if ((long long)p & 0xf)
				p = (unsigned char *)(((long long)p + 0xf) & 0xfffffffffffffff0);
			if ( unlikely( p > read_end ) )
				p -= DMA_BUF_MAX;
			dma1_addr_read_binary = (long long)dma1_phys_ptr + (int)(p - dma1_virt_ptr);
//			dma1_addr_read_binary = (long)*dma1_addr_cur;

		}
		wake_up_interruptible( &read_q_binary );
	}

lend:
//	spin_unlock (&pbuf0.lock);

	spin_unlock_irqrestore( &tasklet_spinlock, flags );
}

static int ethpipe_open_ascii(struct inode *inode, struct file *filp)
{
#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	/* enanble DMA1 and DMA2 */
	*(mmio0_ptr + 0x10)  = 0x3;

	++open_count_ascii;

	dma1_addr_read_ascii = ((long )*dma1_addr_cur & 0x0fffffff) | (dma1_phys_ptr  & 0xf0000000);

	return 0;
}

static int ethpipe_open_binary(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	/* enanble DMA1 and DMA2 */
	*(mmio0_ptr + 0x10)  = 0x3;

	++open_count_binary;

	dma1_addr_read_binary = (long)*dma1_addr_cur;

	return 0;
}

static ssize_t ethpipe_read_ascii(struct file *filp, char __user *buf, size_t count, loff_t *ppos)
{
	int copy_len, available_read_len, remain;
	unsigned char *tmp_wptr;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

#if 0
	if ( count > 1024 * 1024 ) 
		copy_len = 1024 * 1024;
	else
		copy_len = count;
	if ( copy_to_user( buf, (long long)dma1_virt_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}
	return copy_len;
#endif

	if ( wait_event_interruptible( read_q_ascii, ( pbuf0.rx_read_ascii_ptr != (tmp_wptr = pbuf0.rx_write_ascii_ptr) ) ) )
		return -ERESTARTSYS;

	if (tmp_wptr >= pbuf0.rx_read_ascii_ptr)
		available_read_len = (tmp_wptr - pbuf0.rx_read_ascii_ptr);
	else
		available_read_len = (tmp_wptr - pbuf0.rx_read_ascii_ptr + ASCII_BUF_MAX);

	if (count <= available_read_len)
		copy_len = count;
	else
		copy_len = available_read_len;

	if ( (pbuf0.rx_read_ascii_ptr + copy_len ) > pbuf0.rx_end_ascii_ptr ) {
		remain = (pbuf0.rx_end_ascii_ptr - pbuf0.rx_read_ascii_ptr + 1);
		if ( copy_to_user( buf, pbuf0.rx_read_ascii_ptr, remain ) ) {
			printk( KERN_INFO "copy_to_user failed\n" );
			return -EFAULT;
		}
		if ( copy_to_user( buf + remain , pbuf0.rx_start_ascii_ptr, copy_len - remain ) ) {
			printk( KERN_INFO "copy_to_user failed\n" );
			return -EFAULT;
		}
	} else {
		if ( copy_to_user( buf, pbuf0.rx_read_ascii_ptr, copy_len ) ) {
			printk( KERN_INFO "copy_to_user failed\n" );
			return -EFAULT;
		}
	}


	pbuf0.rx_read_ascii_ptr += copy_len;
	if (pbuf0.rx_read_ascii_ptr > pbuf0.rx_end_ascii_ptr)
		pbuf0.rx_read_ascii_ptr -= ASCII_BUF_MAX;

	return copy_len;
}

static ssize_t ethpipe_read_binary(struct file *filp, char __user *buf, size_t count, loff_t *ppos)
{
	int copy_len, available_read_len;
	unsigned char *tmp_wptr;
#ifdef DEBUG
	printk("%s\n", __func__);
#endif

#if 0
	if ( count > 1024 * 1024 ) 
		copy_len = 1024 * 1024;
	else
		copy_len = count;
	if ( copy_to_user( buf, dma1_virt_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}
	return copy_len;
#endif

	if ( wait_event_interruptible( read_q_binary, ( pbuf0.rx_read_binary_ptr != (tmp_wptr = pbuf0.rx_write_binary_ptr) ) ) )
		return -ERESTARTSYS;

	available_read_len = (tmp_wptr - pbuf0.rx_read_binary_ptr);
	if ( (pbuf0.rx_read_binary_ptr + available_read_len ) > pbuf0.rx_end_binary_ptr )
		available_read_len = (pbuf0.rx_end_binary_ptr - pbuf0.rx_read_binary_ptr + 1);

	if ( count > available_read_len )
		copy_len = available_read_len;
	else
		copy_len = count;

	if ( copy_to_user( buf, pbuf0.rx_read_binary_ptr, copy_len ) ) {
		printk( KERN_INFO "copy_to_user failed\n" );
		return -EFAULT;
	}

	pbuf0.rx_read_binary_ptr += copy_len;
	if (pbuf0.rx_read_binary_ptr > pbuf0.rx_end_binary_ptr)
		pbuf0.rx_read_binary_ptr = pbuf0.rx_start_binary_ptr;

	return copy_len;
}

static ssize_t ethpipe_write(int is_binary, struct file *filp, const char __user *buf, size_t count, loff_t *ppos)
{
	static unsigned char tmp_pkt[ETHPIPE_HEADER_LEN+MAX_FRAME_LEN] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0};
	unsigned int copy_len, frame_len;
	static unsigned short hw_slot_addr = 0xffff;
	unsigned char *cr;
	int i, data, data2;
	short j, data_len;
#ifdef USE_TIMER
	unsigned char *pbuf_tx_read_ptr_tmp;
#endif
#ifdef DEBUG
	unsigned char *p1;
#endif

	copy_len = 0;

	if (hw_slot_addr == 0xffff)
		hw_slot_addr = *tx_write_ptr << 1;

	// mmio1 read ptr
	i = *tx_read_ptr << 1;

	// mmio1 free
	if (i < hw_slot_addr) {
		j = hw_slot_addr - i;
	} else {
		j = ((int)hw_slot_addr - (int)i) + (mmio1_len >> 1);
	}

	// count < (mmio1 free)*3
	if ( count < j * 3 ) {
		copy_len = count;
	} else {
		copy_len = j * 3;
	}
#ifdef DEBUG
	printk( "count=%d, copy_len=%d, mmio1_free=%d\n", (int)count, copy_len, j);
#endif

	if ( (pbuf0.tx_write_ptr + copy_len) > pbuf0.tx_end_ptr ) {
		memcpy( pbuf0.tx_start_ptr, pbuf0.tx_read_ptr, (pbuf0.tx_write_ptr - pbuf0.tx_read_ptr ));
		pbuf0.tx_write_ptr = pbuf0.tx_start_ptr + (pbuf0.tx_write_ptr - pbuf0.tx_read_ptr );
		pbuf0.tx_read_ptr = pbuf0.tx_start_ptr;
	}

	// copy from user inputs to kernel buffer
	if ( copy_from_user( pbuf0.tx_write_ptr, buf, copy_len ) ) {
		printk( KERN_INFO "copy_from_user failed\n" );
		return -EFAULT;
	}

	pbuf0.tx_write_ptr += copy_len;

ethpipe_write_loop:

	// check input number of words
	for ( cr = pbuf0.tx_read_ptr; cr < pbuf0.tx_write_ptr && *cr != '\n'; ++cr );
	if ( cr == pbuf0.tx_write_ptr )
		goto ethpipe_write_exit;

#ifdef DEBUG
	printk("pbuf0.tx_write_ptr: %p\n", pbuf0.tx_write_ptr);
	printk("pbuf0.tx_read_ptr: %p\n", pbuf0.tx_read_ptr);
	printk("cr	       : %p\n", cr);
	printk("copy_len: %d\n", (int)copy_len);
#endif

#ifdef USE_TIMER
	pbuf_tx_read_ptr_tmp = pbuf0.tx_read_ptr;
	pbuf0.tx_read_ptr += 17; // number of characters of the timestamp(16) + a space(1)
#endif

	frame_len = 0;
	for ( ; pbuf0.tx_read_ptr < cr && frame_len < MAX_FRAME_LEN; ++pbuf0.tx_read_ptr ) {

		// skip blank char
		if ( (data = *pbuf0.tx_read_ptr) == ' ')
			continue;

		// ascii to number
		data2 = *(++pbuf0.tx_read_ptr);
		if (_atob[data] != _SKP && _atob[data2] != _SKP) {
			tmp_pkt[frame_len+ETHPIPE_HEADER_LEN] = (_atob[data] << 4) | _atob[data2];
			++frame_len;
		} else {
			printk("input data err: %c %c\n", data, data2);
			goto ethpipe_write_exit;
		}
	}

	// set frame length
	tmp_pkt[0] = (frame_len >> 8) & 0xFF;
	tmp_pkt[1] = frame_len & 0xFF;
#ifdef DEBUG
	printk( "frame_len: %d\n", frame_len );
	printk( "tmp_pkt[0] = %02x, tmp_pkt[1] = %02x\n", tmp_pkt[0], tmp_pkt[1] );
#endif

#ifdef USE_TIMER
	data  = *(pbuf_tx_read_ptr_tmp++);
	data2 = *(pbuf_tx_read_ptr_tmp++);
	if ( (data == '0' || data == '1') && _atob[data2] != _SKP) {
		tmp_pkt[2] = (_atob[data] << 7) | (_atob[data2] << 4);
	} else {
		printk("input data err: %c %c\n", data, data2);
		goto ethpipe_write_exit;
	}

	for (i=3; i<10; i++) {
		data  = *(pbuf_tx_read_ptr_tmp++);
		data2 = *(pbuf_tx_read_ptr_tmp++);
		if (_atob[data] != _SKP && _atob[data2] != _SKP) {
			tmp_pkt[i] = (_atob[data] << 4) | _atob[data2];
		} else {
			printk("input data err: %c %c\n", data, data2);
			goto ethpipe_write_exit;
		}
	}

#ifdef DEBUG
	printk( "timestamp: %02x%02x%02x%02x%02x%02x%02x%02x\n",
		tmp_pkt[ 2], tmp_pkt[ 3], tmp_pkt[ 4], tmp_pkt[ 5], tmp_pkt[ 6], tmp_pkt[ 7],
		tmp_pkt[ 8], tmp_pkt[ 9]);
#endif
#endif

#ifdef DEBUG
	printk( "%02x%02x%02x%02x%02x%02x %02x%02x%02x%02x%02x%02x %02x%02x %02x %02x\n",
		tmp_pkt[14], tmp_pkt[15], tmp_pkt[16], tmp_pkt[17], tmp_pkt[18], tmp_pkt[19],
		tmp_pkt[20], tmp_pkt[21], tmp_pkt[22], tmp_pkt[23], tmp_pkt[24], tmp_pkt[25],
		tmp_pkt[26], tmp_pkt[27],
		tmp_pkt[27], tmp_pkt[28]);
#endif

#ifdef DEBUG
	printk("LOCAL_TIME1: %llX\n", *local_time1_ptr);
	printk("LOCAL_TIME2: %llX\n", *local_time2_ptr);
#endif

	data_len = frame_len + ETHPIPE_HEADER_LEN;
	if ( (hw_slot_addr + data_len) < (mmio1_len>>1)) {
		memcpy(mmio1_ptr+hw_slot_addr, tmp_pkt, data_len);
	} else {
		memcpy(mmio1_ptr+hw_slot_addr, tmp_pkt, ((mmio1_len>>1) - hw_slot_addr));
		memcpy(mmio1_ptr, tmp_pkt+((mmio1_len>>1) - hw_slot_addr), data_len - ((mmio1_len>>1) - hw_slot_addr));
	}

	hw_slot_addr += (data_len + 1) & 0xfffffffe;
	hw_slot_addr &= ((mmio1_len>>1) - 1);

#ifdef DEBUG
	p1 = (unsigned char *)mmio1_ptr;
	for (i=0;i<600;i++) {
		if (i % 0x10 == 0)
			printk("%04X:", i);
		printk(" %02X%02X", *p1 & 0xFF, (*p1>>8) & 0xFF);
		if (i % 0x10 == 0xF)
			printk("\n");
		p1++;
	}
	printk("\n");
#endif

#ifdef DEBUG
	printk( "hw_slot_addr: %d\n", hw_slot_addr );
	printk( "*tx_write_ptr: %d, *tx_read_ptr %d\n", *tx_write_ptr, *tx_read_ptr);
#endif

	pbuf0.tx_read_ptr = cr + 1;

	goto ethpipe_write_loop;


ethpipe_write_exit:

#ifdef DEBUG
	printk( "ethpipe_write_exit\n" );
#endif

	// update tx_write_pointer
	*tx_write_ptr = hw_slot_addr >> 1;
#ifdef DEBUG
	printk( "*tx_write_ptr: %d, *tx_read_ptr %d\n", *tx_write_ptr, *tx_read_ptr);
#endif

	return copy_len;
}

static ssize_t ethpipe_write_ascii(struct file *filp, const char __user *buf, size_t count, loff_t *ppos)
{
	return ethpipe_write( 0, filp, buf, count, ppos);
}

static ssize_t ethpipe_write_binary(struct file *filp, const char __user *buf, size_t count, loff_t *ppos)
{
	return ethpipe_write( 1, filp, buf, count, ppos);
}

static int ethpipe_release_ascii(struct inode *inode, struct file *filp)
{
#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	if ( open_count_ascii > 0 )
		--open_count_ascii;

	/* disable DMA1 and DMA2 */
	if ( open_count_ascii == 0 && open_count_binary == 0 )
		*(mmio0_ptr + 0x10)  = 0x0;

	return 0;
}

static int ethpipe_release_binary(struct inode *inode, struct file *filp)
{
	printk("%s\n", __func__);

	if ( open_count_binary > 0 )
		--open_count_binary;

	/* disable DMA1 and DMA2 */
	if ( open_count_ascii == 0 && open_count_binary == 0 )
		*(mmio0_ptr + 0x10)  = 0x0;

	return 0;
}

static unsigned int ethpipe_poll_ascii(struct file* filp, poll_table* wait )
{
	unsigned int retmask = 0;
#ifdef DEBUG
	printk("%s\n", __func__);
#endif
	poll_wait( filp, &read_q_ascii,  wait );
//      poll_wait( filp, &write_q_ascii, wait );

	if ( pbuf0.rx_read_ascii_ptr != pbuf0.rx_write_ascii_ptr ) {
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

static unsigned int ethpipe_poll_binary(struct file* filp, poll_table* wait )
{
	unsigned int retmask = 0;
#ifdef DEBUG
	printk("%s\n", __func__);
#endif
	poll_wait( filp, &read_q_binary,  wait );
//      poll_wait( filp, &write_q_binary, wait );

	if ( pbuf0.rx_read_binary_ptr != pbuf0.rx_write_binary_ptr ) {
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

static long ethpipe_ioctl_ascii(struct file *filp, unsigned int cmd, unsigned long arg)
{
	printk("%s\n", __func__);
	return  -ENOTTY;
}

static long ethpipe_ioctl_binary(struct file *filp, unsigned int cmd, unsigned long arg)
{
	printk("%s\n", __func__);
	return  -ENOTTY;
}

static struct file_operations ethpipe_fops = {
	.owner		= THIS_MODULE,
	.read		= ethpipe_read_ascii,
	.write		= ethpipe_write_ascii,
	.poll		= ethpipe_poll_ascii,
	.compat_ioctl	= ethpipe_ioctl_ascii,
	.open		= ethpipe_open_ascii,
	.release	= ethpipe_release_ascii,
};

static struct file_operations ethpipeb_fops = {
	.owner		= THIS_MODULE,
	.read		= ethpipe_read_binary,
	.write		= ethpipe_write_binary,
	.poll		= ethpipe_poll_binary,
	.compat_ioctl	= ethpipe_ioctl_binary,
	.open		= ethpipe_open_binary,
	.release	= ethpipe_release_binary,
};

static struct miscdevice ethpipea_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = DRV_NAME,
	.fops = &ethpipe_fops,
};

static struct miscdevice ethpipeb_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = DRV_NAME,
	.fops = &ethpipeb_fops,
};

static int __devinit ethpipe_init_one (struct pci_dev *pdev,
				       const struct pci_device_id *ent)
{
	int rc;
	static char name[16];
	static int board_idx = -1;

	mmio0_ptr = 0L;
	mmio1_ptr = 0L;
	dma1_virt_ptr = 0L;
	dma1_phys_ptr = 0L;
	dma2_virt_ptr = 0L;
	dma2_phys_ptr = 0L;

	rc = pci_enable_device (pdev);
	if (rc)
		goto error;

	rc = pci_request_regions (pdev, DRV_NAME);
	if (rc)
		goto error;

	++board_idx;

	printk( KERN_INFO "board_idx: %d\n", board_idx );

	pci_set_master (pdev);		/* set BUS Master Mode */

	mmio0_start = pci_resource_start (pdev, 0);
	mmio0_end   = pci_resource_end   (pdev, 0);
	mmio0_flags = pci_resource_flags (pdev, 0);
	mmio0_len   = pci_resource_len   (pdev, 0);

	printk( KERN_INFO "mmio0_start: %X\n", (unsigned int)mmio0_start );
	printk( KERN_INFO "mmio0_end  : %X\n", (unsigned int)mmio0_end   );
	printk( KERN_INFO "mmio0_flags: %X\n", (unsigned int)mmio0_flags );
	printk( KERN_INFO "mmio0_len  : %X\n", (unsigned int)mmio0_len   );

	mmio0_ptr = ioremap(mmio0_start, mmio0_len);
	if (!mmio0_ptr) {
		printk(KERN_ERR "cannot ioremap MMIO0 base\n");
		goto error;
	}

	mmio1_start = pci_resource_start (pdev, 2);
	mmio1_end   = pci_resource_end   (pdev, 2);
	mmio1_flags = pci_resource_flags (pdev, 2);
	mmio1_len   = pci_resource_len   (pdev, 2);

	printk( KERN_INFO "mmio1_start: %X\n", (unsigned int)mmio1_start );
	printk( KERN_INFO "mmio1_end  : %X\n", (unsigned int)mmio1_end   );
	printk( KERN_INFO "mmio1_flags: %X\n", (unsigned int)mmio1_flags );
	printk( KERN_INFO "mmio1_len  : %X\n", (unsigned int)mmio1_len   );

	mmio1_ptr = ioremap_wc(mmio1_start, mmio1_len);
	if (!mmio1_ptr) {
		printk(KERN_ERR "cannot ioremap MMIO1 base\n");
		goto error;
	}

	dma1_virt_ptr = dma_alloc_coherent( &pdev->dev, DMA_BUF_MAX, &dma1_phys_ptr, GFP_KERNEL);
	if (!dma1_virt_ptr) {
		printk(KERN_ERR "cannot dma1_alloc_coherent\n");
		goto error;
	}
	printk( KERN_INFO "dma1_virt_ptr  : %llX\n", (long long)dma1_virt_ptr );
	printk( KERN_INFO "dma1_phys_ptr  : %llX\n", (long long)dma1_phys_ptr );

	dma2_virt_ptr = dma_alloc_coherent( &pdev->dev, DMA_BUF_MAX, &dma2_phys_ptr, GFP_KERNEL);
	if (!dma2_virt_ptr) {
		printk(KERN_ERR "cannot dma2_alloc_coherent\n");
		goto error;
	}
	printk( KERN_INFO "dma2_virt_ptr  : %llX\n", (long long)dma2_virt_ptr );
	printk( KERN_INFO "dma2_phys_ptr  : %llX\n", (long long)dma2_phys_ptr );

	spin_lock_init (&tasklet_spinlock);
	spin_lock_init (&pbuf0.lock);

	pcidev = pdev;

	/* set min disable interrupt cycles (@125MHz) */
//	*(long *)(mmio0_ptr + 0x80)  = 2500000;
	*(long *)(mmio0_ptr + 0x80)  = 1;

	/* set max enable interrupt cycles (@125MHz) */
//	*(long *)(mmio0_ptr + 0x84)  = 2500000;
	*(long *)(mmio0_ptr + 0x84)  = 0xffffffff;

	/* Set DMA Pointer */
	dma1_addr_start = (long *)(mmio0_ptr + 0x20);
	dma1_addr_cur   = (long *)(mmio0_ptr + 0x24);
	dma2_addr_start = (long *)(mmio0_ptr + 0x28);
	dma2_addr_cur   = (long *)(mmio0_ptr + 0x2c);

	/* set DMA Buffer length */
	*(long *)(mmio0_ptr + 0x14)  = DMA_BUF_MAX;

	/* set DMA1 start address */
	*dma1_addr_start  = dma1_phys_ptr;

	/* set DMA2 start address */
	*dma2_addr_start  = dma2_phys_ptr;

	/* set DMA read pointer */
	dma1_addr_read_ascii = dma1_phys_ptr;
	dma1_addr_read_binary = dma1_phys_ptr;
	dma2_addr_read = dma2_phys_ptr;

	/* set TX slot Pointer */
	tx_write_ptr = (unsigned short *)(mmio0_ptr + TX_WRITE_PTR_ADDRESS);
	tx_read_ptr  = (unsigned short *)(mmio0_ptr + TX_READ_PTR_ADDRESS);

#ifdef DEBUG
	printk( "*tx_write_ptr: %x\n", *tx_write_ptr);
	printk( "*tx_read_ptr: %x\n", *tx_read_ptr);
#endif

	/* clear tx_write_ptr */
	*tx_write_ptr = *tx_read_ptr;

	/* Set receive ascii buffer */
	if ( ( pbuf0.rx_start_ascii_ptr = kmalloc(ASCII_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		rc = -1;
		goto error;
	}
	pbuf0.rx_end_ascii_ptr = (pbuf0.rx_start_ascii_ptr + ASCII_BUF_MAX - 1);
	pbuf0.rx_write_ascii_ptr = pbuf0.rx_start_ascii_ptr;
	pbuf0.rx_read_ascii_ptr  = pbuf0.rx_start_ascii_ptr;

	/* Set receive binary buffer */
	if ( ( pbuf0.rx_start_binary_ptr = kmalloc(BINARY_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		rc = -1;
		goto error;
	}
	pbuf0.rx_end_binary_ptr = (pbuf0.rx_start_binary_ptr + BINARY_BUF_MAX - 1);
	pbuf0.rx_write_binary_ptr = pbuf0.rx_start_binary_ptr;
	pbuf0.rx_read_binary_ptr  = pbuf0.rx_start_binary_ptr;

	/* Set transmitte buffer */
	if ( ( pbuf0.tx_start_ptr = kmalloc(ASCII_BUF_MAX, GFP_KERNEL) ) == 0 ) {
		printk("fail to kmalloc\n");
		rc = -1;
		goto error;
	}
	pbuf0.tx_end_ptr = (pbuf0.tx_start_ptr + ASCII_BUF_MAX - 1);
	pbuf0.tx_write_ptr = pbuf0.tx_start_ptr;
	pbuf0.tx_read_ptr  = pbuf0.tx_start_ptr;

	/* Set sysfs pointers */
	global_time_ptr = (unsigned long long *)(mmio0_ptr + 0x4);
	local_time1_ptr = (unsigned long long *)(mmio0_ptr + 0x100);
	local_time2_ptr = (unsigned long long *)(mmio0_ptr + 0x108);
	local_time3_ptr = (unsigned long long *)(mmio0_ptr + 0x110);
	local_time4_ptr = (unsigned long long *)(mmio0_ptr + 0x118);
	local_time5_ptr = (unsigned long long *)(mmio0_ptr + 0x120);
	local_time6_ptr = (unsigned long long *)(mmio0_ptr + 0x128);
	local_time7_ptr = (unsigned long long *)(mmio0_ptr + 0x130);


	/* register ascii character device */
	sprintf( name, "%s/%d", DRV_NAME, board_idx );
	ethpipea_dev.name = name,
	rc = misc_register(&ethpipea_dev);
	if (rc) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		return rc;
	}
	/* register raw character device */
	sprintf( name, "%s/r%d", DRV_NAME, board_idx );
	ethpipeb_dev.name = name,
	rc = misc_register(&ethpipeb_dev);
	if (rc) {
		printk("fail to misc_register (MISC_DYNAMIC_MINOR)\n");
		return rc;
	}

	open_count_ascii = 0;

	if (request_irq(pdev->irq, ethpipe_interrupt, IRQF_SHARED, DRV_NAME, pdev)) {
		printk(KERN_ERR "cannot request_irq\n");
	}
	
	return 0;

error:
	if ( pbuf0.rx_start_ascii_ptr ) {
		kfree( pbuf0.rx_start_ascii_ptr );
		pbuf0.rx_start_ascii_ptr = NULL;
	}
	if ( pbuf0.rx_start_binary_ptr ) {
		kfree( pbuf0.rx_start_binary_ptr );
		pbuf0.rx_start_binary_ptr = NULL;
	}

	if ( pbuf0.tx_start_ptr ) {
		kfree( pbuf0.tx_start_ptr );
		pbuf0.tx_start_ptr = NULL;
	}

	pci_release_regions (pdev);
	pci_disable_device (pdev);

	return -1;
}

static void __devexit ethpipe_remove_one (struct pci_dev *pdev)
{
	disable_irq(pdev->irq);
	free_irq(pdev->irq, pdev);

	tasklet_kill( &tasklet_fire_led );

	if (mmio0_ptr) {
		iounmap(mmio0_ptr);
		mmio0_ptr = 0L;
	}
	if (mmio1_ptr) {
		iounmap(mmio1_ptr);
		mmio1_ptr = 0L;
	}
	if ( pbuf0.rx_start_ascii_ptr ) {
		kfree( pbuf0.rx_start_ascii_ptr );
		pbuf0.rx_start_ascii_ptr = NULL;
	}
	if ( pbuf0.rx_start_binary_ptr ) {
		kfree( pbuf0.rx_start_binary_ptr );
		pbuf0.rx_start_binary_ptr = NULL;
	}

	if ( pbuf0.tx_start_ptr ) {
		kfree( pbuf0.tx_start_ptr );
		pbuf0.tx_start_ptr = NULL;
	}

	pci_release_regions (pdev);
	pci_disable_device (pdev);
	printk("%s\n", __func__);
}


static struct pci_driver ethpipe_pci_driver = {
	.name		= DRV_NAME,
	.id_table	= ethpipe_pci_tbl,
	.probe		= ethpipe_init_one,
	.remove		= __devexit_p(ethpipe_remove_one),
#ifdef CONFIG_PM
//	.suspend	= ethpipe_suspend,
//	.resume		= ethpipe_resume,
#endif /* CONFIG_PM */
};


static int __init ethpipe_init(void)
{
	int ret;

#ifdef MODULE
	pr_info(ethpipe_DRIVER_NAME "\n");
#endif

	init_waitqueue_head( &write_q_ascii );
	init_waitqueue_head( &write_q_binary );
	init_waitqueue_head( &read_q_ascii );
	init_waitqueue_head( &read_q_binary );
	
	printk("%s\n", __func__);

	/* sysfs */
	ethpipe_kobj = kobject_create_and_add("ethpipe", kernel_kobj);
	if (!ethpipe_kobj)
		return -ENOMEM;

	ret = sysfs_create_group(ethpipe_kobj, &attr_group);
	if (ret)
		kobject_put(ethpipe_kobj);

	return pci_register_driver(&ethpipe_pci_driver);
}

static void __exit ethpipe_cleanup(void)
{
	printk("%s\n", __func__);
	misc_deregister(&ethpipea_dev);
	misc_deregister(&ethpipeb_dev);
	pci_unregister_driver(&ethpipe_pci_driver);

	if ( dma1_virt_ptr )
		dma_free_coherent(&pcidev->dev, DMA_BUF_MAX, dma1_virt_ptr, dma1_phys_ptr);

	if ( dma2_virt_ptr )
		dma_free_coherent(&pcidev->dev, DMA_BUF_MAX, dma2_virt_ptr, dma2_phys_ptr);

	kobject_put(ethpipe_kobj);
}

MODULE_LICENSE("GPL");
module_init(ethpipe_init);
module_exit(ethpipe_cleanup);

