ifneq ($(KERNELRELEASE),)
obj-m		:= ethpipe.o
#obj-m		:= ethpipe0.o ethpipe1.o
else
KDIR		:= /lib/modules/$(shell uname -r)/build/
PWD		:= $(shell pwd)

all:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) V=1 modules

clean:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) clean 

endif
