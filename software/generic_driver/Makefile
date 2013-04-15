ifneq ($(KERNELRELEASE),)
obj-m		:= genpipe.o
else
KDIR		:= /lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) V=1 modules
clean:
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) clean 
endif
