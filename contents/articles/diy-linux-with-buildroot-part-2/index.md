---
title: DIY Linux with Buildroot [2/2]
author: cellux
date: 2013-01-11 08:27
template: article.jade
---

In the [first part] of this article, we built a minimal Linux system with Buildroot. In today's session, we'll automate the post-build fixups and extend Buildroot with two RPi-specific packages.

[first part]: /articles/diy-linux-with-buildroot-part-1/

##### Automating post-build actions

This is easy: just create a script somewhere which contains the commands to execute after a successful build, and let Buildroot know about it by setting the `BR2_ROOTFS_POST_BUILD_SCRIPT` config variable (under `System configuration` / `Custom script to run before creating filesystem images` in kconfig).

The location of this script can be specified relative to `$TOPDIR`, so it makes sense to store it somewhere in the Buildroot tree. My solution was to create a `board/rpi` directory for this purpose and symlink it to the actual content which is stored in a git repository:

```bash
cd $HOME/repos
git clone https://github.com/cellux/rpi-buildroot.git
cd $HOME/buildroot
tar xvzf buildroot-2012.11.1.tar.gz
cd buildroot-2012.11.1
ln -s $HOME/repos/rpi-buildroot/board/rpi board/rpi
```

This way I can easily add my personal customizations to a freshly unpacked Buildroot tree.

The script (`board/rpi/post-build.sh`) could look like this:

```bash
TARGETDIR=$1
BR_ROOT=$PWD

# set root password to `passpass'
install -T -m 0600 $BR_ROOT/system/skeleton/etc/shadow $TARGETDIR/etc/shadow
sed -i -e 's#^root:[^:]*:#root:saWv8UefZU43.:#' $TARGETDIR/etc/shadow

# create an empty /boot directory in target
install -d -m 0755 $TARGETDIR/boot

# setup mount for /boot
install -T -m 0644 $BR_ROOT/system/skeleton/etc/fstab $TARGETDIR/etc/fstab
echo '/dev/mmcblk0p1 /boot vfat defaults 0 0' >> $TARGETDIR/etc/fstab
```

(don't forget to chmod it to 755)

As you see, Buildroot runs the script from `$TOPDIR` and passes the location of the target file system as the first argument.

A small change compared to the previous article is the hard-coding of the crypted password to avoid a dependency on Perl.

The `/etc/shadow` and `/etc/fstab` files are copied from a Buildroot-provided skeleton filesystem - that's what Buildroot uses as a base for the root fs - and then updated with our stuff. (If we left out the copy and ran `make` repeatedly, `$TARGETDIR/etc/fstab` would contain several entries for `/boot`.)

##### Extending Buildroot with new packages

Buildroot stores its packages (or rather package definitions) in the `$TOPDIR/package` directory. For instance, the busybox package may be found under `$TOPDIR/package/busybox`.

Packages may have sub-packages, sub-packages may have sub-sub-packages and so on, these are stored in an analogous directory structure under `package/<main-package>` (see `x11r7` for an example).

Each package has a `Config.in` file which specifies what options the package has and defines how kconfig should display these in the configuration menu.

When kconfig starts, it parses `$TOPDIR/Config.in`, which pulls in the `Config.in` files of the `toolchain`, `system`, `package`, `fs`, `boot` and `linux` directories. These recursively include their child `Config.in` files and this way a configuration tree is built. Kconfig presents this tree to the user who makes her selections. Upon exiting, all config settings are merged together into a `.config` file which is then saved to `$TOPDIR`.

As an example, here is the `Config.in` file from the `tcpdump` package:

```
config BR2_PACKAGE_TCPDUMP
	bool "tcpdump"
	select BR2_PACKAGE_LIBPCAP
	help
	  A tool for network monitoring and data acquisition.
	  
	  http://www.tcpdump.org/

config BR2_PACKAGE_TCPDUMP_SMB
	bool "smb dump support"
	depends on BR2_PACKAGE_TCPDUMP
	help
	  enable possibly-buggy SMB printer
```

Each `config` stanza defines one configuration variable. The first line of the stanza defines the type and label of the config entry. The `select` entry tells kconfig that selecting `tcpdump` would automatically enable the `libpcap` package as well, while `depends` declares that `smb dump support` can be selected only if `tcpdump` has been already selected (in practice this means that this entry won't be visible in the config until `tcpdump` has been selected).

All lines belonging to the config stanzas must be indented with a single Tab, help lines must be also prefixed with two extra spaces.

When the `.config` file has been written and we execute `make`, Buildroot goes over all selected packages and executes the package-specific makefile located at `package/<package-name>/<package-name>.mk`.

Let's see how `tcpdump` gets built (`package/tcpdump/tcpdump.mk`):

```
#############################################################
#
# tcpdump
#
#############################################################
# Copyright (C) 2001-2003 by Erik Andersen <andersen@codepoet.org>
# Copyright (C) 2002 by Tim Riker <Tim@Rikers.org>

TCPDUMP_VERSION = 4.3.0
TCPDUMP_SITE = http://www.tcpdump.org/release
TCPDUMP_LICENSE = BSD-3c
TCPDUMP_LICENSE_FILES = LICENSE

TCPDUMP_CONF_ENV = ac_cv_linux_vers=2 td_cv_buggygetaddrinfo=no
TCPDUMP_CONF_OPT = --without-crypto \
                $(if $(BR2_PACKAGE_TCPDUMP_SMB),--enable-smb,--disable-smb)
TCPDUMP_DEPENDENCIES = zlib libpcap

# make install installs an unneeded extra copy of the tcpdump binary
define TCPDUMP_REMOVE_DUPLICATED_BINARY
	rm -f $(TARGET_DIR)/usr/sbin/tcpdump.$(TCPDUMP_VERSION)
endef

TCPDUMP_POST_INSTALL_TARGET_HOOKS += TCPDUMP_REMOVE_DUPLICATED_BINARY

$(eval $(autotools-package))
```

Every makefile in Buildroot works in the same way: first it sets up a set of make variables to configure the build (their names are prefixed with the uppercase name of the package, hyphens converted to underscores), then invokes one or several macros (in this case, `autotools-package`) which carry out the actual build process.

The system provides three major mechanisms for building packages:

1. `autotools-package` for autotools-based ones (`./configure && make && make install`)
2. `cmake-package` for `cmake` projects
3. `generic-package` for the rest

A package gets built in several stages: first it's downloaded, then unpacked, patched, configured, built and finally installed (it can be also cleaned and uninstalled).

###### Download

To download a package called `pkg`, Buildroot tries to fetch it from `$(PKG_SITE)/$(PKG)-$(PKG_VERSION).tar.gz` (it can also fetch it from a version control system - SVN, Bazaar, Git, Mercurial are all supported -, `scp` it from somewhere or simply copy it from a directory on the local system). If we define a variable named `PKG_SOURCE`, then it will use that instead of `$(PKG)-$(PKG_VERSION).tar.gz`. The downloaded file will be stored in the download directory (`$(HOME)/buildroot/dl` in our case).

###### Unpack

The package gets unpacked into the `output/build/$(PKG)-$(PKG_VERSION)` directory.

###### Patch

If there are any files called `$(PKG)-*.patch` in the `package/$(PKG)` directory, then these are all applied to the unpacked source in alphabetical order.

###### Configure

In the case of autotools-based packages, this step invokes the `./configure` script with parameters given by `$(PKG)_CONF_OPT`, in an environment extended with the variables in `$(PKG)_CONF_ENV`.

In the case of generic packages, we must define a variable called `$(PKG)_CONFIGURE_CMDS` and Buildroot will invoke that:

```
define PKG_CONFIGURE_CMDS
       # do what is required here to configure the package
endef
```

###### Build

In case of autotools-based packages, this step executes `make`.

For generic packages, we must define `$(PKG)_BUILD_CMDS`.

###### Install

Buildroot knows about four types of installation:

1. Install to the host directory (`output/host`)
2. Install to the staging directory (`output/staging`)
3. Install to the images directory (`output/images`)
4. Install to the target directory (`output/target`)

The `host` directory is used for packages which must be built for the host machine (host gcc, m4, autotools, cmake, etc.)

The `staging` directory is used to install dependencies of other packages. For instance, `tcpdump` depends on `zlib` and `libpcap`, so these must be built and installed (as ARM binaries) to `output/staging` before `tcpdump` can get built.

The `images` directory is the target for the Linux kernel and the final root fs. Not many packages use this kind of install.

The `target` directory is the base for the final root fs: each package which wants to have files in the root fs must install something to here.

For generic packages, the corresponding make variables are `$(PKG)_INSTALL_CMDS`, `$(PKG)_INSTALL_STAGING_CMDS`, `$(PKG)_INSTALL_IMAGES_CMDS` and `$(PKG)_INSTALL_TARGET_CMDS`, respectively.

##### Creating a package for RPi firmware

In the previous article, we copied the firmware files (`bootcode.bin`, `start.elf` and `fixup.dat`), the Linux kernel and `cmdline.txt` to the `/boot` partition of the SD card by hand.

It would be nice to modify Buildroot in such a way that at the end of the build process we get a `bootfs.tar.gz` file under `output/images`, which just has to be extracted to the `/boot` partition.

To achieve this goal, we'll create a new package under `package/rpi/rpi-firmware` to take care of this.

The new package's `Config.in` file looks like this (watch out for tab characters if you copy/paste this):

```
config BR2_PACKAGE_RPI_FIRMWARE
	bool "Raspberry Pi GPU firmware + boot files"
	help
	  If you select this, you'll get a bootfs.tar.gz in output/images
	  with a filesystem ready to be written to the first partition
	  of the Raspberry Pi SD card.
	  
	https://github.com/raspberrypi/firmware

config BR2_PACKAGE_RPI_FIRMWARE_CMDLINE
	string "Linux kernel command line"
	default "dwc_otg.lpm_enable=0 console=tty1 elevator=deadline rootwait ip=dhcp root=/dev/mmcblk0p2 rootfstype=ext4"
	help
	  String to be written to /boot/cmdline.txt

```

The corresponding makefile:

```
#############################################################
#
# rpi-firmware
#
#############################################################
RPI_FIRMWARE_VERSION = ffbb918fd46f1b0b687a474857b370f24f71989d
RPI_FIRMWARE_SITE = https://github.com/raspberrypi/firmware/archive
RPI_FIRMWARE_SOURCE = $(RPI_FIRMWARE_VERSION).tar.gz
RPI_FIRMWARE_INSTALL_STAGING = YES

define RPI_FIRMWARE_INSTALL_STAGING_CMDS
	$(INSTALL) -d -m 0755 $(STAGING_DIR)/boot || /bin/true
	$(INSTALL) -m 0644 $(@D)/boot/bootcode.bin $(STAGING_DIR)/boot
	$(INSTALL) -m 0644 $(@D)/boot/fixup.dat $(STAGING_DIR)/boot
	$(INSTALL) -m 0644 $(@D)/boot/start.elf $(STAGING_DIR)/boot
	echo "$(call qstrip,$(BR2_PACKAGE_RPI_FIRMWARE_CMDLINE))" > $(STAGING_DIR)/boot/cmdline.txt
endef

$(eval $(generic-package))
```

We take advantage of the fact that a given commit on Github can be downloaded in .tar.gz format from the `https://github.com/<user>/<repo>/archive/<sha1>.tar.gz` URL.

`RPI_FIRMWARE_INSTALL_STAGING = YES` declares that this package wants to install something to `output/staging` so the build process will execute the commands in `RPI_FIRMWARE_INSTALL_STAGING_CMDS`.

The reason for assembling the boot directory under `staging` is that we don't want these files to be present on `target` (there we need an empty directory which will serve as a mount point).

To activate this package, we need to pull in its `Config.in` from one of the main `Config.in` files.

As we'll most likely create several RPi-specific packages, I created the following `Config.in` in the `package/rpi` directory:

```
menu "Raspberry Pi"
source "package/rpi/rpi-firmware/Config.in"
endmenu
```

and sourced it at the end of `package/Config.in` (before the last `endmenu`):

```
source "package/rpi/Config.in"
```

The result: a new menu entry - `Raspberry Pi` - shows up under `Package Selection for the target`, and when we enter it, we see the options defined by `package/rpi/rpi-firmware/Config.in`.

The corresponding makefile (`package/rpi/rpi.mk`):

```
include package/rpi/*/*.mk
```

This just pulls in all the package-specific makefiles it finds in the `package/rpi/*` directories.

The last thing we must do is to package up the contents of the staging `/boot` folder to `output/images/bootfs.tar.gz`. Let's do this with an images install:

```
RPI_FIRMWARE_INSTALL_IMAGES = YES

define RPI_FIRMWARE_INSTALL_IMAGES_CMDS
	$(INSTALL) -m 0644 $(BINARIES_DIR)/zImage $(STAGING_DIR)/boot/kernel.img
	tar -C $(STAGING_DIR)/boot -cvzf $(BINARIES_DIR)/bootfs.tar.gz .
endef
```

First we copy the kernel zImage to `/boot` on staging (`BINARIES_DIR` is specified by the top-level Makefile), then we create the tar.gz.

As we need the kernel image before we can pack up `bootfs.tar.gz`, we have to declare a dependency on the `linux` package:

```
RPI_FIRMWARE_DEPENDENCIES = linux
```

That's all.

##### Creating a package for RPi userland

`package/rpi/rpi-userland/Config.in`:

```
config BR2_PACKAGE_RPI_USERLAND
	bool "Raspberry Pi userland"
	help
	  Raspberry Pi Userland
	  
	  https://github.com/raspberrypi/userland/
```

Don't forget to source it from `package/rpi/Config.in`.

`package/rpi/rpi-userland/rpi-userland.mk`:

```
#############################################################
#
# rpi-userland
#
#############################################################
RPI_USERLAND_VERSION = 9852ce28826889e50c4d6786b942f51bccccac54
RPI_USERLAND_SITE = https://github.com/raspberrypi/userland/archive
RPI_USERLAND_SOURCE = 9852ce28826889e50c4d6786b942f51bccccac54.tar.gz
RPI_USERLAND_INSTALL_TARGET = YES

define RPI_USERLAND_INSTALL_TARGET_CMDS
        $(INSTALL) -m 0644 $(@D)/build/lib/*.so $(TARGET_DIR)/usr/lib
        $(INSTALL) -m 0755 $(@D)/build/bin/* $(TARGET_DIR)/usr/bin
endef

$(eval $(cmake-package))
```

`$(@D)` is the build directory of the package (`output/build/rpi-userland-9852ce28826889e50c4d6786b942f51bccccac54` in this case).

First I used `master` as the value of `RPI_USERLAND_VERSION`, but this led to clashes between packages in the download directory (each package wanted to download its archive to `master.tar.gz`), so I switched to SHA-1 hashes instead.

One last thing before we can build this: the `interface/vcos/glibc/vcos_backtrace.c` file must be patched because it refers to a C function (`backtrace`) which is not available in µClibc:

`package/rpi/rpi-userland/rpi-userland-disable-backtrace.patch`:

```
--- userland.old/interface/vcos/glibc/vcos_backtrace.c  2013-01-06 21:19:45.642055469 +0100
+++ userland.new/interface/vcos/glibc/vcos_backtrace.c  2013-01-06 21:17:55.592626490 +0100
@@ -26,16 +26,19 @@
 */

 #include <interface/vcos/vcos.h>
-#ifdef __linux__
+#ifdef __GLIBC__
+#ifndef __UCLIBC__
 #include <execinfo.h>
 #endif
+#endif
 #include <stdio.h>
 #include <stdlib.h>
 #include <sys/types.h>

 void vcos_backtrace_self(void)
 {
-#ifdef __linux__
+#ifdef __GLIBC__
+#ifndef __UCLIBC__
    void *stack[64];
    int depth = backtrace(stack, sizeof(stack)/sizeof(stack[0]));
    char **names = backtrace_symbols(stack, depth);
@@ -49,5 +52,6 @@
       free(names);
    }
 #endif
+#endif
 }
```

And if you don't want to fiddle with the files, just use my Git repository: https://github.com/cellux/rpi-buildroot

Happy hacking!
