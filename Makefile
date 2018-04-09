PRODUCT ?= duckbill
HWREV ?= v2

JOBS ?= $(shell cat /proc/cpuinfo | grep processor | wc -l)

ifeq ($(PRODUCT),evachargese)
CROSS_COMPILE := arm-linux-gnueabi-
BL_BOARD := evacharge-se
BL_SUFFIX := sb
DTS_NAME := imx28-evachargese
KERNEL_CFG := evachargese
PRODUCT_COMMON :=
PROGRAMS := open-plc-utils
PLATFORM := armel

else ifeq ($(PRODUCT),tarragon)
CROSS_COMPILE := arm-linux-gnueabihf-
BL_BOARD := tarragon
BL_SUFFIX := imx
DTS_NAME := imx6ull-tarragon
KERNEL_CFG := tarragon
PRODUCT_COMMON :=
HWREV := v1
PROGRAMS := open-plc-utils
PLATFORM := armhf
MFGTOOL_PATH := mfgtool-$(PRODUCT)
MFGTOOL_CFG := tarragon-mfgtool

else
CROSS_COMPILE := arm-linux-gnueabi-
BL_BOARD := duckbill
BL_SUFFIX := sb
DTS_NAME := imx28-duckbill
KERNEL_CFG := duckbill
PRODUCT_COMMON := duckbill
PROGRAMS :=
PLATFORM := armel

endif

ROOTFSSIZE:=$(shell echo $$((384 * 1024 * 1024)))
ROOTFSCHUNKSIZE:=$(shell echo $$((64 * 1024 * 1024)))

ifeq ($(PRODUCT),duckbill)
ROOTFSSIZE:=$(shell echo $$((640 * 1024 * 1024)))
endif

ifeq ($(PRODUCT),evachargese)
ROOTFSSIZE:=$(shell echo $$((1024 * 1024 * 1024)))
endif

ifeq ($(PRODUCT),tarragon)
ROOTFSSIZE:=$(shell echo $$((1024 * 1024 * 1024)))
endif

ifeq ($(BL_BOARD),evachargese)
ifeq ($(HWREV),v1)
BOOTSTREAM:=imx-bootlets/imx28_ivt_linux.sb
else
BOOTSTREAM:=u-boot/u-boot.$(BL_SUFFIX)
endif
else
BOOTSTREAM:=u-boot/u-boot.$(BL_SUFFIX)
endif

TOOLS:=${CURDIR}/tools
PATH:=$(TOOLS)/ptgen:$(TOOLS)/fsl-imx-uuc:${CURDIR}/u-boot/tools/env:$(TOOLS)/elftosb/bld/linux:$(PATH)
export PATH ROOTFSSIZE

.PHONY: help
help:
	@echo 'STIP - Simple Target Image Builder'
	@echo '----------------------------------'
	@echo ''
	@echo 'Please have a look at the README.md for valid make targets.'
	@echo ''

.PHONY: jessie-requirements
jessie-requirements:
	sudo apt-get install -y apt-transport-https build-essential make patch multistrap curl bc binfmt-support libssl-dev qemu-user-static lzop
	sudo sh -c 'echo "deb http://emdebian.org/tools/debian/ jessie main" > /etc/apt/sources.list.d/crosstools.list'
	curl http://emdebian.org/tools/debian/emdebian-toolchain-archive.key | sudo apt-key add -
	sudo dpkg --add-architecture armel
	sudo dpkg --add-architecture armhf
	sudo apt-get update
	sudo apt-get install -y crossbuild-essential-armel crossbuild-essential-armhf

.PHONY: trusty-requirements xenial-requirements zesty-requirements
trusty-requirements xenial-requirements zesty-requirements:
	sudo apt-get install -y apt-transport-https build-essential make patch multistrap bc binfmt-support libssl-dev qemu-user-static lzop
	sudo apt-get install -y gcc-arm-linux-gnueabi gcc-arm-linux-gnueabihf g++-arm-linux-gnueabi g++-arm-linux-gnueabihf
	sudo sh -c 'if [ `dpkg -s multistrap | grep Version | cut -d: -f2` = "2.2.0ubuntu1" ]; then \
	        cp /usr/sbin/multistrap /usr/sbin/multistrap.orig; \
	        sed -i -e "s/-y \$$forceyes install/-y install/" /usr/sbin/multistrap; \
	     fi'

prepare:
	git submodule init
	git submodule update

tools: $(if $(findstring sb,$(BL_SUFFIX)),tools/fsl-imx-uuc/sdimage tools/elftosb/elftosb) tools/ptgen/ptgen

tools/fsl-imx-uuc/sdimage: tools/fsl-imx-uuc/sdimage.c tools/fsl-imx-uuc/Makefile
	$(MAKE) -C tools/fsl-imx-uuc

tools/ptgen: tools/ptgen/ptgen.c tools/ptgen/Makefile
	$(MAKE) -C tools/ptgen

tools/elftosb/elftosb:
	$(MAKE) -C tools/elftosb

.PHONY: tools-clean
tools-clean:
	$(MAKE) -C tools/fsl-imx-uuc clean
	$(MAKE) -C tools/ptgen clean
	$(MAKE) -C tools/elftosb clean

.PHONY: u-boot uboot
u-boot uboot: u-boot/u-boot.$(BL_SUFFIX)

u-boot/u-boot.$(BL_SUFFIX):
	$(MAKE) -C u-boot $(BL_BOARD)_defconfig CROSS_COMPILE="$(CROSS_COMPILE)"
	$(MAKE) -C u-boot -j $(JOBS) env
	ln -sf fw_printenv u-boot/tools/env/fw_setenv
	$(MAKE) -C u-boot -j $(JOBS) u-boot.$(BL_SUFFIX) CROSS_COMPILE="$(CROSS_COMPILE)"

linux: linux/arch/arm/boot/zImage

.PHONY: linux/arch/arm/boot/zImage
linux/arch/arm/boot/zImage:
	cat linux-configs/$(KERNEL_CFG) > linux/.config
	$(MAKE) -C linux ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" olddefconfig
	$(MAKE) -C linux -j $(JOBS) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)"
	-$(MAKE) -C linux ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" \
	        INSTALL_MOD_PATH="../linux-modules" modules_install
	rm -f linux-modules/lib/modules/*/build linux-modules/lib/modules/*/source
	-$(MAKE) -C linux ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" \
		INSTALL_FW_PATH="../linux-firmware" firmware_install

linux-clean:
	rm -f linux/arch/arm/boot/zImage

linux-menuconfig:
	cat linux-configs/$(KERNEL_CFG) > linux/.config
	$(MAKE) -C linux ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" olddefconfig
	$(MAKE) -C linux ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" menuconfig
	$(MAKE) -C linux ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" savedefconfig
	cat linux/defconfig > linux-configs/$(KERNEL_CFG)
	rm linux/defconfig

dtbs:
	$(MAKE) -C linux ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" dtbs

kernel: linux dtbs

.PHONY: imx-bootlets
imx-bootlets: imx-bootlets/imx28_ivt_linux.sb

imx-bootlets/imx28_ivt_linux.sb: linux/arch/arm/boot/zImage
	cat linux/arch/arm/boot/zImage linux/arch/arm/boot/dts/imx28-$(PRODUCT).dtb > imx-bootlets/zImage
	$(MAKE) -C imx-bootlets -j1 CROSS_COMPILE="$(CROSS_COMPILE)" MEM_TYPE=MEM_DDR1 BOARD=$(BL_BOARD)


OPENPLCUTILS_INSTALLDIR:=${CURDIR}/programs/open-plc-utils/rootfs
$(OPENPLCUTILS_INSTALLDIR):
	$(MAKE) -C programs/open-plc-utils CROSS="$(CROSS_COMPILE)"
	sudo $(MAKE) -C programs/open-plc-utils ROOTFS="$(OPENPLCUTILS_INSTALLDIR)" install

.PHONY: open-plc-utils
open-plc-utils: $(OPENPLCUTILS_INSTALLDIR)

.PHONY: programs
programs: $(PROGRAMS)

.PHONY: programs-clean
programs-clean:
	-rm -rf $(OPENPLCUTILS_INSTALLDIR)
	$(MAKE) -C programs/open-plc-utils clean


.PHONY: clean
clean: tools-clean
	$(MAKE) -C u-boot clean
	$(MAKE) -C linux clean
	$(MAKE) -C imx-bootlets clean

rootfs-clean:
	$(MAKE) -C debian-rootfs clean

.PHONY: rootfs
rootfs:
	$(MAKE) -C debian-rootfs

install: clean-rootfs programs
	sudo mkdir -p rootfs
	sudo cp -a debian-rootfs/rootfs/* rootfs/

	# linux kernel and device tree
	sudo mkdir -p rootfs/boot
	sudo cp -av linux/arch/arm/boot/zImage rootfs/boot/
	sudo cp -av linux/arch/arm/boot/dts/$(DTS_NAME)*.dtb rootfs/boot/
	sudo sh -c 'if [ -d linux-modules/lib/modules ]; then cp -av linux-modules/lib/modules rootfs/lib; fi'
	sudo sh -c 'if [ -d linux-firmware ]; then cp -av linux-firmware rootfs/lib/firmware; fi'
	sudo chown 0:0 rootfs/boot/*
	sudo chmod 0644 rootfs/boot/*
	-sudo chown 0:0 -R rootfs/lib/
	-sudo sh -c 'find rootfs/lib/modules -type d -exec chmod 0755 {} \;'
	-sudo sh -c 'find rootfs/lib/modules -type f -exec chmod 0644 {} \;'

	# fold in root fs overlay
	sudo mkdir rootfs-tmp
	sudo cp -a debian-rootfs/files/* rootfs-tmp/
	sudo cp -a debian-rootfs/files-$(PLATFORM)/* rootfs-tmp/
	# fold in common files for this product
ifneq ($(PRODUCT_COMMON),)
	sudo cp -a debian-rootfs/files-$(PRODUCT_COMMON)-common/* rootfs-tmp/
endif
	# fold in product specific files
	sudo sh -c 'if [ -d debian-rootfs/files-$(PRODUCT) ]; then cp -a debian-rootfs/files-$(PRODUCT)/* rootfs-tmp/; fi'
	# and fold in customer specific files (if present)
	sudo sh -c 'if [ -d debian-rootfs/files-$(PRODUCT)-custom ]; then cp -a debian-rootfs/files-$(PRODUCT)-custom/* rootfs-tmp/ || true; fi'
ifeq ($(findstring open-plc-utils,$(PROGRAMS)),open-plc-utils)
	sudo sh -c 'cp -a $(OPENPLCUTILS_INSTALLDIR)/* rootfs-tmp/'
endif
	sudo mkdir -p rootfs-tmp/usr/bin/
	sudo cp -a /usr/bin/qemu-arm-static rootfs-tmp/usr/bin/
	sudo chown 0:0 -R rootfs-tmp
	# for root fs resizing after first boot
	sudo mv rootfs/sbin/init rootfs/sbin/init.orig
	sudo cp -a rootfs-tmp/* rootfs
	sudo rm -rf rootfs-tmp

	# run dpkg-configure stuff inside the chroot
	sudo mount -t proc - rootfs/proc
	sudo chroot rootfs /init-chroot.sh
	# workarounds to stop some daemons
	-sudo kill -9 $$(ps ax | grep [q]emu-arm-static | awk '{ print $$1 }')
	sudo umount rootfs/proc

	# cleanup
	-sudo sh -c 'find rootfs -name .stib_placeholder -exec rm {} \;'
	sudo rm -f rootfs/init-chroot.sh
	sudo rm -rf rootfs/var/cache/apt/*

clean-rootfs:
	sudo rm -rf rootfs rootfs-tmp

images-clean clean-images:
	rm -f images/*.*

rootfs-image: images/rootfs.img
#.PHONY: images/rootfs.img
images/rootfs.img:
	rm -f images/rootfs.img
	mkdir -p images
	dd if=/dev/zero of=images/rootfs.img seek=$$(($(ROOTFSSIZE) - 1)) bs=1 count=1
	sudo mkfs.ext4 -F images/rootfs.img
	mktemp -d > images/mountpoint
	sudo mount images/rootfs.img $$(cat images/mountpoint) -o loop
	-sudo cp -a rootfs/* $$(cat images/mountpoint)
	sudo umount $$(cat images/mountpoint)
	sudo rmdir $$(cat images/mountpoint)
	rm -f images/mountpoint

images/sdcard.img: images/rootfs.img
ifeq ($(PRODUCT),duckbill)
	sh tools/gen_sdcard_ext4.sh images/sdcard.img $(BOOTSTREAM) images/rootfs.img $$(($(ROOTFSSIZE) / (1024 * 1024)))
	sh tools/fixup_fdt_file.sh tools/fw_env.config $(PRODUCT) $(HWREV)
endif
ifeq ($(PRODUCT),evachargese)
ifeq ($(HWREV),v2)
	sh tools/gen_emmc_mx28.sh images/sdcard.img $(BOOTSTREAM) images/rootfs.img $$(($(ROOTFSSIZE) / (1024 * 1024)))
else
	sh tools/gen_sdcard_ext4.sh images/sdcard.img $(BOOTSTREAM) images/rootfs.img $$(($(ROOTFSSIZE) / (1024 * 1024)))
	sh tools/fixup_fdt_file.sh tools/fw_env.config $(PRODUCT) $(HWREV)
endif
endif
ifeq ($(PRODUCT),tarragon)
	sh tools/gen_emmc_mx6ull.sh images/sdcard.img $(BOOTSTREAM) images/rootfs.img $$(($(ROOTFSSIZE) / (1024 * 1024)))
endif

.PHONY: disk-image
disk-image: images/sdcard.img
	rm -f images/ucl.xml images/emmc.img.*
ifeq ($(PLATFORM),armel)
	split -b $(ROOTFSCHUNKSIZE) --numeric-suffixes=1 images/sdcard.img images/emmc.img.
	python tools/fix-filenames.py images/emmc.img.*
ifeq ($(PRODUCT),duckbill)
	gzip -9 images/emmc.img.*
endif
ifeq ($(PRODUCT),evachargese)
ifneq ($(HWREV),v1)
	gzip -9 images/emmc.img.*
endif
	tools/gen_ucl_xml.sh images/ > images/ucl.xml
endif
endif

.PHONY: mfgtool-profile
mfgtool-profile: images/sdcard.img
	rm -rf "images/$(MFGTOOL_PATH)"
	cp -a mfgtool "images/$(MFGTOOL_PATH)"
	mkdir -p "images/$(MFGTOOL_PATH)/Profiles/$(PRODUCT)/OS Firmware/files/"
	cp -av linux/arch/arm/boot/zImage "images/$(MFGTOOL_PATH)/Profiles/$(PRODUCT)/OS Firmware/firmware"
	cp -av linux/arch/arm/boot/dts/$(DTS_NAME)-*.dtb "images/$(MFGTOOL_PATH)/Profiles/$(PRODUCT)/OS Firmware/firmware"
ifneq ($(MFGTOOL_CFG),)
	cat linux-configs/$(MFGTOOL_CFG) > linux/.config
	$(MAKE) -C linux ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" olddefconfig
	$(MAKE) -C linux -j $(JOBS) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)"
endif
	split -b $(ROOTFSCHUNKSIZE) --numeric-suffixes=1 images/sdcard.img "images/$(MFGTOOL_PATH)/Profiles/$(PRODUCT)/OS Firmware/files/emmc.img."
	cp "$(BOOTSTREAM)" "images/$(MFGTOOL_PATH)/Profiles/$(PRODUCT)/OS Firmware/firmware"
	cp -av linux/arch/arm/boot/zImage "images/$(MFGTOOL_PATH)/Profiles/$(PRODUCT)/OS Firmware/firmware/zImage_mfgtool"
	tools/gen_ucl2_xml.sh "images/$(MFGTOOL_PATH)/Profiles/$(PRODUCT)/OS Firmware/files" $(DTS_NAME)-sd-mfg.dtb > "images/$(MFGTOOL_PATH)/Profiles/$(PRODUCT)/OS Firmware/ucl2.xml"

images/mfgtool-$(PRODUCT).zip: mfgtool-profile
	cd images && zip -r "$(shell basename "$@")" "$(MFGTOOL_PATH)"

.PHONY: mfgtool-image
mfgtool-image: images/mfgtool-$(PRODUCT).zip

.PHONY: mrproper
mrproper:
	-make -C u-boot mrproper
	-make -C linux mrproper
	-make -C update-image clean

.PHONY: distclean
distclean: mrproper clean-rootfs rootfs-clean tools-clean programs-clean
	rm -rf linux-modules
	rm -rf linux-firmware
	rm -rf images
	rm -f update/bundle-staging/rootfs.*

.PHONY: update-image
update-image: images/rootfs.img
	test -f update/bundle-staging/rootfs.ext4 || ln images/rootfs.img update/bundle-staging/rootfs.ext4
	$(MAKE) -C update

.PHONY: update-clean
update-clean:
	$(MAKE) -C update clean
