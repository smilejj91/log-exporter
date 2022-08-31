#!/bin/bash

export LC_ALL=C

function finish {
	CODE=$1
	cd ..
	rm -rf "$TMPDIR"
	exit $CODE
}
trap finish $? EXIT

function sanitize {
	KEYWORD=$(echo "$2" | sed 's/\([\/&]\)/\\\1/g')
	if [[ -n "$KEYWORD" ]]; then sed -i "s/${KEYWORD}/$1/g" *; fi
}

TMPDIR=$(mktemp -d --tmpdir sysinfo.XXXXXXXXXX) || { echo "Failed."; exit 1; }
OUTFILE=$(readlink -m "$TMPDIR/../$(basename "$TMPDIR").tar.gz")
cd "$TMPDIR"

exec 2> "sysinfo.log"
set -v


if [[ "$EUID" -ne 0 ]]; then echo "NOTE: It is recommended to run this tool as root."; fi

MODULES=`lsmod | awk '{print $1}'`

echo "Gathering system and tablet information. This may take a few seconds."

## General host information
echo "  * General host information..."
uname -a >> host.txt 2>&1
HOST=$(lsb_release -a 2>/dev/null || hostnamectl 2>/dev/null || cat /etc/*release 2>/dev/null)
echo "$HOST" >> host.txt

grep "" /sys/class/dmi/id/* 2>&1 | grep -v -e "_serial:" -e "_uuid:" -e "asset_tag:" >> machine.txt

cat /proc/uptime >> uptime.txt


## Kernel driver information
echo "  * Kernel driver information..."
ls /etc/depmod.d | xargs -I{} sh -c 'ls -l {}; cat {}' >> kernel_drivers.txt
ls /etc/modprobe.d | xargs -I{} sh -c 'ls -l {}; cat {}' >> kernel_drivers.txt
echo >> kernel_drivers.txt
find /lib/modules -type f | xargs ls -l >> kernel_drivers.txt
echo >> kernel_drivers.txt
find /sys/module/ -type f | xargs grep "" >> kernel_drivers.txt
echo >> kernel_drivers.txt
for MODULE in $MODULES; do
	modinfo $MODULE >> kernel_drivers.txt 2>&1
	echo >> kernel_drivers.txt
done


DO_PRINT=1
echo "     - udev..."
udevadm info -e | while read -r LINE; do
	if [[ "$LINE" == "P: "* ]]; then
		DEVICE=$(echo "$LINE" | cut -d' ' -f 2-)
		if grep -q "$DEVICE" udevadm_*.txt 2>/dev/null; then
			DO_PRINT=1
		else
			DO_PRINT=0
		fi
	fi
	if [[ $DO_PRINT == 1 ]]; then
		echo "$LINE" >> udevadm.txt
	fi
done

BINDLIST=""
echo "  * Unbinding devices..."
for D in /sys/module/wacom/drivers/usb:wacom/*; do
	if test -d "$D/input"; then
		# Temporarily unbind usb:wacom devices so lsusb
		# can retrieve the HID descriptor
		echo "     - $DEV..."
		DEV=$(basename $D)
		BINDLIST="$BINDLIST $DEV"
		echo -n $DEV > /sys/module/wacom/drivers/usb:wacom/unbind
	fi
done

apt install -y usbutils

lsusb -v >> lsusb.txt 2>&1
lsusb -t > lsusb_tree.txt 2>&1


## Userspace driver information
echo "  * Userspace driver information..."
find /usr/lib{,64}/* -name "*.so*" >> userspace_dynamic_library.txt 2>&1
find /usr/lib{,64}/* -name "*.a*" >> userspace_static_library.txt 2>&1

PACKAGES=$(apt list --installed)
echo "$PACKAGES" >> packages.txt

## Userspace device information

apt install -y xinput xserver-xorg-input-wacom libwacom2 libwacom-bin libinput-tools
echo "  * Userspace device information..."
xinput list >> xinput.txt 2>&1
xsetwacom -v list >> xsetwacom.txt 2>&1
libwacom-list-local-devices >> libwacom.txt 2>&1
if command -v libinput-list-devices; then
	libinput-list-devices >> libinput.txt 2>&1
else
	libinput list-devices >> libinput.txt 2>&1
fi


# RandR display information
echo "  * Device display information..."
xrandr --verbose >> xrandr.txt 2>&1


## Logfiles
echo "  * System logs..."
find /home/ -name "Xorg.*.log*" | xargs -I{} sh -c 'ls -al {}; cat {}' > xorg.log
journalctl -b > journalctl.log 2>&1
dmesg  > dmesg.log


## Configuration Files
echo "  * System config files..."
tar czf xorg-configs.tar.gz --ignore-failed-read \
    /etc/X11/xorg.conf /etc/xorg.conf /usr/etc/X11/xorg.conf \
    /usr/lib/X11/xorg.conf /usr/share/X11/xorg.conf \
    /etc/X11/xorg.conf.d /usr/lib/X11/xorg.conf.d \
    /usr/share/X11/xorg.conf.d
tar czf udev-configs.tar.gz --ignore-failed-read \
    /usr/lib/udev/rules.d /etc/udev/rules.d
tar czf libwacom-configs.tar.gz --ignore-failed-read \
    /usr/share/libwacom

## Desktop configuration
echo "  * Desktop configuration data..."
for D in gnome; do for X in desktop settings-daemon; do DIR=/org/$D/$X/peripherals/; echo "==== $DIR ===="; dconf dump $DIR; done; done > dconf-dump.txt

## Tarball generation
echo "  * Tarball generation..."
tar czf "$OUTFILE" -C .. "$(basename "$TMPDIR")"
echo "Finished. Data available in '$OUTFILE'"
