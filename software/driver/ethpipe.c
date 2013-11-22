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

static unsigned long long local_time1, local_time2, local_time3, local_time4, local_time5, local_time6, local_time7;

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


static void tasklet_body( unsigned long value );
DECLARE_TASKLET( tasklet_fire_led, tasklet_body, ( unsigned long )NULL );

static spinlock_t tasklet_spinlock;


static irqreturn_t ethpipe_interrupt(int irq, void *pdev)
{
	int status;
	int handled = 0;

#ifdef DEBUG
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
	static unsigned short hex[257], initialized = 0;
	static long long dma1_addr_write_ascii;
	static int dma1_overflow, mem1_overflow = -1;
	long long dma1_value;
//	int pkt_count = 0;

#ifdef DEBUG
	printk("%s\n", __func__);
#endif

	spin_lock_irqsave( &tasklet_spinlock, flags );

	if ( unlikely(initialized == 0) ) {
		for ( i = 0 ; i < 256 ; ++i ) {
			sprintf( (unsigned char *)&hex[i], "%02X", i);
		}
		initialized = 1;
	}
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
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = hex[ i > 1 ? *p : 0 ];
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
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = hex[ *p ];
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
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = hex[ *p ];
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
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = hex[ i > 1 ? *p : 0 ];
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
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = hex[ *p ];
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
					*(unsigned short *)pbuf0.rx_write_ascii_ptr = hex[ *p ];
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

			// magic code
			*pbuf0.rx_write_binary_ptr++ = 0x55;
			*pbuf0.rx_write_binary_ptr++ = 0x5d;

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
	printk("%s\n", __func__);

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
	static unsigned char tmp_pkt[14+MAX_FRAME_LEN] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0};
	unsigned int copy_len, frame_len;
	static unsigned short hw_slot_addr = 0xffff;
	unsigned char *cr;
	int i, data, data2;
	short j, data_len;
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
	printk( "count=%d, copy_len=%d, mmio1_free=%d\n", count, copy_len, j);
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

	frame_len = 0;
	for ( ; pbuf0.tx_read_ptr < cr && frame_len < MAX_FRAME_LEN; ++pbuf0.tx_read_ptr ) {

		// skip blank char
		if ( (data = *pbuf0.tx_read_ptr) == ' ')
			continue;

		// ascii to number
		if (data >= '0' && data <= '9') {
			data2 =  (data - '0') << 4;
		} else if (data >= 'A' && data <= 'F') {
			data2 =  (data - 'A' + 0xA) << 4;
		} else if (data >= 'a' && data <= 'f') {
			data2 =  (data - 'a' + 0xA) << 4;
		} else {
			printk("input data err: %c\n", data);
			goto ethpipe_write_exit;
		}

		data = *(++pbuf0.tx_read_ptr);

		// ascii to number
		if (data >= '0' && data <= '9') {
			tmp_pkt[frame_len+14] = (data2 | (data - '0'));
			++frame_len;
		} else if (data >= 'A' && data <= 'F') {
			tmp_pkt[frame_len+14] = (data2 | (data - 'A' + 0xA));
			++frame_len;
		} else if (data >= 'a' && data <= 'f') {
			tmp_pkt[frame_len+14] = (data2 | (data - 'a' + 0xA));
			++frame_len;
		} else {
			printk("input data err: %c\n", data);
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

#ifdef DEBUG
	printk( "%02x%02x%02x%02x%02x%02x %02x%02x%02x%02x%02x%02x %02x%02x %02x %02x\n",
		tmp_pkt[14], tmp_pkt[15], tmp_pkt[16], tmp_pkt[17], tmp_pkt[18], tmp_pkt[19],
		tmp_pkt[20], tmp_pkt[21], tmp_pkt[22], tmp_pkt[23], tmp_pkt[24], tmp_pkt[25],
		tmp_pkt[26], tmp_pkt[27],
		tmp_pkt[27], tmp_pkt[28]);
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
	p1 = (unsigned short *)mmio1_ptr;
	for (i=0;i<16384;i++) {
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
	printk("%s\n", __func__);

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
	local_time1 = *(unsigned long long *)(mmio0_ptr + 0x100);
	local_time2 = *(unsigned long long *)(mmio0_ptr + 0x108);
	local_time3 = *(unsigned long long *)(mmio0_ptr + 0x110);
	local_time4 = *(unsigned long long *)(mmio0_ptr + 0x118);
	local_time5 = *(unsigned long long *)(mmio0_ptr + 0x120);
	local_time6 = *(unsigned long long *)(mmio0_ptr + 0x128);
	local_time7 = *(unsigned long long *)(mmio0_ptr + 0x130);


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
#ifdef MODULE
	pr_info(ethpipe_DRIVER_NAME "\n");
#endif

	init_waitqueue_head( &write_q_ascii );
	init_waitqueue_head( &write_q_binary );
	init_waitqueue_head( &read_q_ascii );
	init_waitqueue_head( &read_q_binary );
	
	printk("%s\n", __func__);
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
}

MODULE_LICENSE("GPL");
module_init(ethpipe_init);
module_exit(ethpipe_cleanup);

