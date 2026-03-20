obj-m += excalibur.o

# Auto-detect the compiler the running kernel was built with.
# A Clang-built kernel requires CC=clang AND LD=ld.lld for OOT modules.
KERNEL_CLANG := $(shell grep -qi 'clang' /proc/version && echo 1 || echo 0)

ifeq ($(KERNEL_CLANG),1)
    override CC := clang
    override LD := ld.lld
    EXTRA_ARGS  := CC=$(CC) LD=$(LD)
else
    override CC := gcc
    EXTRA_ARGS  := CC=$(CC)
endif

KDIR := /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(EXTRA_ARGS) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
