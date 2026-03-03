#!/usr/bin/env bash

# DEPENDENCIES
# qemu-user-static is required to run arm software using the "qemu-arm-static" command (I suppose you use this script on a X86_64 computer)
# Please install it via your package manager (e.g. Ubuntu) or whatever way is appropriate for your distribution (Arch has it in AUR)

# BASIC CONFIGURATION
REPO="https://dl-cdn.alpinelinux.org/alpine/"
MNT="/mnt/alpine"
IMAGE="./alpine.ext3"
IMAGESIZE=2048 # Megabytes
ALPINESETUP="source /etc/profile
echo kindle > /etc/hostname
echo \"nameserver 8.8.8.8\" > /etc/resolv.conf
mkdir /run/dbus
apk update
apk upgrade
cat /etc/alpine-release
apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano git neofetch
apk add desktop-file-utils gtk-engines consolekit gtk-murrine-engine thunar marco gnome-themes-extra
apk add xfce4 thunar
apk add \$(apk search -q ttf- | grep -v '\-doc')
apk add onboard chromium
adduser alpine -D
echo -e \"alpine\nalpine\" | passwd alpine
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers
addgroup sudo
addgroup alpine sudo
su alpine -c \"cd ~
git init
git remote add origin https://github.com/schuhumi/alpine_kindle_dotfiles
git pull origin master
git reset --hard origin/master
dconf load /org/mate/ < ~/.config/org_mate.dconf.dump
dconf load /org/onboard/ < ~/.config/org_onboard.dconf.dump\"

echo '# Default settings for chromium. This file is sourced by /bin/sh from
# the chromium launcher.

# Options to pass to chromium.
mouseid=\"\$(env DISPLAY=:1 xinput list --id-only \"Xephyr virtual mouse\")\"
CHROMIUM_FLAGS='\''--force-device-scale-factor=2 --touch-devices='\''\$mouseid'\'' --pull-to-refresh=1 --disable-smooth-scrolling --enable-low-end-device-mode --disable-login-animations --disable-moda[...]
mkdir -p /usr/share/chromium/extensions
# Install uBlock Origin
echo '{
	\"external_update_url\": \"https://clients2.google.com/service/update2/crx\"
}' > /usr/share/chromium/extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm.json

echo \"You're now dropped into an interactive shell in Alpine, feel free to explore and type exit to leave.\"
sh"
STARTGUI='#!/bin/sh
chmod a+w /dev/shm # Otherwise the alpine user cannot use this (needed for chromium)
SIZE=$(xwininfo -root -display :0 | egrep "geometry" | cut -d " "  -f4)
env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -ac -br -screen $SIZE -cc 4 -reset -terminate & sleep 3 && su alpine -c "env DISPLAY=:1 startxfce4"
killall Xephyr'

# ENSURE ROOT
if [ "$(whoami)" != "root" ]; then
    echo "This script needs to be run as root"
    exec sudo -- "$0" "$@"
fi

# GETTING APK-TOOLS-STATIC
echo "Determining version of apk-tools-static"
curl "$REPO/latest-stable/main/armhf/APKINDEX.tar.gz" --output /tmp/APKINDEX.tar.gz
tar -xzvf /tmp/APKINDEX.tar.gz -C /tmp
APKVER="$(cut -d':' -f2 <<<"$(grep -A 5 "P:apk-tools-static" /tmp/APKINDEX | grep "V:")")"
rm /tmp/APKINDEX /tmp/APKINDEX.tar.gz /tmp/DESCRIPTION
echo "Version of apk-tools-static is: $APKVER"
echo "Downloading apk-tools-static"
curl "$REPO/latest-stable/main/armv7/apk-tools-static-$APKVER.apk" --output "/tmp/apk-tools-static.apk"
tar -xzvf "/tmp/apk-tools-static.apk" -C /tmp

# CREATING IMAGE FILE
echo "Creating image file"
dd if=/dev/zero of="$IMAGE" bs=1M count=$IMAGESIZE
mkfs.ext3 "$IMAGE"
tune2fs -i 0 -c 0 "$IMAGE"

# MOUNTING IMAGE
echo "Mounting image"
mkdir -p "$MNT"
mount -o loop -t ext3 "$IMAGE" "$MNT"

# BOOTSTRAPPING ALPINE
echo "Bootstrapping Alpine"
qemu-arm-static /tmp/sbin/apk.static -X "$REPO/edge/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base

# COMPLETE IMAGE MOUNTING FOR CHROOT
mkdir -p "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/etc" "$MNT/usr/bin"
mount /dev/ "$MNT/dev/" --bind
mount -t proc none "$MNT/proc"
mount -o bind /sys "$MNT/sys"

# CONFIGURE ALPINE
cp /etc/resolv.conf "$MNT/etc/resolv.conf"
mkdir -p "$MNT/etc/apk"
echo "$REPO/edge/main/
$REPO/edge/community/
$REPO/edge/testing/
$REPO/latest-stable/community" > "$MNT/etc/apk/repositories"
echo "$STARTGUI" > "$MNT/startgui.sh"
chmod +x "$MNT/startgui.sh"

# CHROOT
cp $(which qemu-arm-static) "$MNT/usr/bin/"
chroot /mnt/alpine/ qemu-arm-static /bin/sh -c "$ALPINESETUP"
rm "$MNT/usr/bin/qemu-arm-static"

# UNMOUNT IMAGE & CLEANUP
sync
kill $(lsof +f -t "$MNT")
echo "Unmounting image"
umount "$MNT/sys"
umount "$MNT/proc"
umount -lf "$MNT/dev"
umount "$MNT"
while [[ $(mount | grep "$MNT") ]]; do
	echo "Alpine is still mounted, please wait.."
	sleep 3
	umount "$MNT"
done
echo "Alpine unmounted"
echo "Cleaning up"
rm /tmp/apk-tools-static.apk
rm -r /tmp/sbin
