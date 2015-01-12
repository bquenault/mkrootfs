#!/bin/sh

# mypath=/mnt/sda1/space ; ./mkrootfs.sh -i trusty/install.sh -i live/prepare.sh make_live $mypath/live.d make_image squashfs $mypath/live.d $mypath/live-10.04-$(date +%Y%m%d)_amd64.squashfs make_initrd $mypath/live.d/boot/initrd.img-3.13.0-43-generic $mypath/initrd.img-3.13.0-43-generic_amd64

# --------------------------------------------------------------------------- #

# Function dependencies:
# - trusty/install.sh: debootstrap_base ()
MKRFS_DEPS="debootstrap_base"
for x in $MKRFS_DEPS; do is_defined "$x" || error "$x is not defined"; done

# File dependencies:
# - trusty/sources.list: /etc/apt/sources.list template
# - linux/bootst.sh: Bootstrap abstract script used by:
#   1. /sbin/init to mount root filesystem during initrd stage
#   2. LSB init scripts subsystem to finalize boot
#
# Relative to: $MKRFS_DIR/
MKRFS_ATTACHED="$MKRFS_ATTACHED trusty/sources.list \
                                linux/bootst.sh \
                                bin/wget.static.amd64 \
                                bin/wget.static.i386"

# --------------------------------------------------------------------------- #

[ -n "$APTOPT" ] || export APTOPT="--no-install-recommends --yes --force-yes"

[ -n "$LIVE_MIRROR" ] || LIVE_MIRROR='http://fr.archive.ubuntu.com/ubuntu'
[ -n "$LIVE_SMIRROR" ] || LIVE_SMIRROR='http://security.ubuntu.com/ubuntu'
[ -n "$LIVE_DISTRIB" ] || LIVE_DISTRIB='trusty'

DFAM='ubuntu' # Distribution family
DVER='14.04' # Distribution version
case "$( uname -m )" in
  i686)   ARCH='i386'  ;;
  x86_64) ARCH='amd64' ;;
  *) error 'Architecture not supported.'
esac

_make_live () {
  # Inhibit Upstart init control tool
  dpkg-divert --local --rename --add /sbin/initctl
  ln -s /bin/true /sbin/initctl

  sourceslist="$MKRFS_DIR/trusty/sources.list"
  [ -f "$sourceslist" ] || error "Cannot found $sourceslist"

  mirror=$( echo "$LIVE_MIRROR" | sed 's/\//\\\//g' )
  smirror=$( echo "$LIVE_SMIRROR" | sed 's/\//\\\//g' )
  distrib="$LIVE_DISTRIB"
  cp -f "$sourceslist" '/etc/apt/sources.list'
  sed -e "s/___MIRROR___/$mirror/g" \
      -e "s/___SMIRROR___/$smirror/g" \
      -e "s/___DISTRIB___/$distrib/g" \
      -i '/etc/apt/sources.list'

  apt-get update
  apt-get upgrade --yes

  # First: install Linux Kernel
  apt-get $APTOPT install linux-signed-generic
  # linux-signed-generic
  # > linux-headers-generic
  #   > linux-headers-$kver-$kfla
  #     > linux-headers-$kver
  # > linux-signed-image-$kfla
  #   > linux-firmware
  #   > linux-signed-image-$kver-$kfla
  #     > linux-image-$kver-$kfla
  #     > linux-image-extra-$kver-$kfla
  #       > linux-image-$kver-$kfla
  #       > sbsigntool

  # Add Debian package management system tools:
  # - debootstrap
  # - apt-file
  apt-get $APTOPT install debootstrap apt-file

  # Add system tools:
  # - iptables
  # - grub (grub-install, update-grub)
  # - parted (parted, partprobe)
  # - kpartx (device mapping creation)
  # - hdparm (hard disk parameters tunning)
  # - time (CPU resource usage measuring)
  # - sysstat (sar, iostat, mpstat, pidstat, sadf)
  # - lsof (open file lister)
  # - psmisc (fuser, killall, peekfd, pstree)
  # - strace (system call tracer)
  # - ltrace (runtime library call tracer)
  # - pciutils (lspci, pcimodules, setpci, update-pciids)
  # - usbutils (lsusb, usb-devices, usbhid-dump, update-usbids)
  # - wget curl zip unzip (HTTP/FTP clients and ZIP archivers)
  # - syslinux (boot loaders)
  # - genisoimage (mkisofs, isodump, isoinfo, isovfy, dirsplit)
  # - squashfs-tools (mksquashfs, unsquashfs)
  # - qemu-utils (qemu-img, qemu-io, qemu-nbd)
  apt-get $APTOPT install iptables grub parted kpartx hdparm time \
                          sysstat lsof psmisc strace ltrace \
                          pciutils usbutils wget curl xz-utils zip unzip \
                          syslinux genisoimage squashfs-tools qemu-utils

  # Add network tools:
  # - bind9-host (host)
  # - dnsutils (dig, nslookup, nsupdate)
  # - whois (whois, mkpasswd)
  # - mtr-tiny (mtr)
  # - iptraf tcpdump nmap (network analysis)
  apt-get $APTOPT install bind9-host dnsutils whois mtr-tiny iptraf tcpdump nmap

  # Add development tools
  apt-get $APTOPT install vim binutils nasm gcc g++ gdb libc6-dev make autoconf\
                          perl python

  # Optional documentation
  apt-get $APTOPT install man-db manpages-fr manpages-fr-extra language-pack-fr

  # Add sshd
  apt-get $APTOPT install openssh-server
  service ssh stop
  echo 'manual' > /etc/init/ssh.override
  rm -f /etc/ssh/ssh_host_*_key*

  # Add rsync and duplicity (usefull backup tools)
  apt-get $APTOPT install rsync duplicity
  update-rc.d -f rsync remove

  # We do not need to set CPU Frequency Scaling governor to "ondemand"
  update-rc.d -f ondemand remove

  # Clean-up
  apt-get autoremove --yes
  apt-get clean

  # Add post-boot script
  postboot="$MKRFS_DIR/linux/bootst.sh"
  [ -f "$postboot" ] || error "Cannot found $postboot"
  mv "$postboot" '/usr/local/sbin/postboot'
  chmod +x '/usr/local/sbin/postboot'
  sed -e 's/^\(exit 0\)$/\/usr\/local\/sbin\/postboot\n\1/g' -i '/etc/rc.local'

  # Localization
  rm -rf /usr/lib/locale/*
  rm -f /var/lib/locales/supported.d/*
  lc='fr_FR.UTF-8'
  grep $lc /usr/share/i18n/SUPPORTED > /var/lib/locales/supported.d/$lc
  locale-gen
  echo 'LANG=fr_FR.UTF-8'   > '/etc/default/locale'
  echo 'LANGUAGE=fr_FR:fr' >> '/etc/default/locale'
  sed -e 's/XKBLAYOUT=.*$/XKBLAYOUT=\"fr\"/g' \
      -e 's/XKBVARIANT=.*$/XKBVARIANT=\"latin9\"/g' \
      -i '/etc/default/keyboard'
  setupcon --save-only --force
  cp -p /usr/share/zoneinfo/Europe/Paris /etc/localtime

  # Create new user
  user='ubicast'
  plain='ubicast'
  crypt=$( echo $plain | mkpasswd -s -m SHA-512 )
  useradd "$user" --password "$crypt" --groups 'adm,cdrom,sudo,dip,plugdev' \
                  --user-group --comment "$user" --create-home --shell /bin/bash

  # Default network configuration
  cat > /etc/network/interfaces <<EOF
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback

EOF

  # rsyslogd: comments the 4 last lines of /etc/rsyslog.d/50-default.conf
  #
  # #!/bin/sed -nf
  # # copy 1st line in pattern space to hold space
  # 1   { h; }
  # # append 2nd an 3rd lines in pattern space to hold space, then
  # # copy hold space to pattern space
  # 2,4 { H; g; }
  # $   { s/\n/\n#/g; s/\(.*\)/#\1/; p; q; }
  # # empty pattern space and immediately start next cycle
  # 1,3 { d; }
  # # append new line to pattern space
  # N
  # # print and delete 1st line in pattern space and start next cycle
  # P
  # D
  # sed_script='1{h};2,4{H;g};${s/\n/\n#/g;s/\(.*\)/#\1/;p;q};1,3{d};N;P;D'
  #
  # Optimized alternative
  # #!/bin/sed -nf
  # 1!   { H; g; }
  # 1,4! { P; s/[^\n]*\n//; }
  # $    { s/\n/\n#/g; s/\(.*\)/#\1/; p; }
  # h
  sed_script='1!{H;g};1,4!{P;s/[^\n]*\n//};${s/\n/\n#/g;s/\(.*\)/#\1/;p};h'
  sed -n -e "$sed_script" -i '/etc/rsyslog.d/50-default.conf'

  # Clean-up of /var
  rm -rf /var/lib/apt/lists/*
  mkdir -p /var/lib/apt/lists/partial
  rm -f /var/cache/debconf/*-old
  rm -f /var/cache/ldconfig/aux-cache
  rm -rf /var/log/*
  rm -rf /var/run/*

  utmp_files="/var/log/btmp /var/log/lastlog /var/log/wtmp /var/run/utmp"
  touch $utmp_files
  chgrp utmp $utmp_files
  syslog_files="/var/log/auth.log /var/log/kern.log /var/log/syslog"
  touch /var/log/dmesg $syslog_files
  chown syslog $syslog_files
  chgrp adm /var/log/dmesg $syslog_files
  mkdir /var/log/fsck
  echo "(Nothing has been logged yet.)" > /var/log/fsck/checkfs
  echo "(Nothing has been logged yet.)" > /var/log/fsck/checkroot
  mkdir /var/log/upstart

  # Anonymize configuration
  rm -f /etc/hostname
  rm -f /etc/resolv.conf
  rm -f /etc/resolvconf/resolv.conf.d/original
  rm -f /etc/resolvconf/resolv.conf.d/tail

  # Restore Upstart init control tool
  rm -f /sbin/initctl
  dpkg-divert --rename --remove /sbin/initctl
}

make_live () {
  [ -n "$1" ] && livefs="$1" || livefs='./livefs.d'

  cdn=$( readlink -f "$livefs" )
  [ -d "$cdn" ] && rm -rf "$cdn"
  mkdir -p "$cdn"
  debootstrap_base "$cdn"
  chrootme "$cdn" _make_live
}

make_initrd () {
  [ -n "$2" ] || error "usage: make_initrd <src-initrd> <new-initrd> [ird-dir]"
  [ -e "$1" ] && src=$( readlink -f "$1" ) || error "Cannot found $1"
  [ ! -e "$2" ] && dst=$( readlink -m "$2" ) || error "$2 already exist"
  [ -n "$3" ] && initrd="$3" || initrd="${dst%/*}/initrd.d"

  rootfs=${src%/boot/*}

  [ -d "$initrd" ] && rm -rf "$initrd"
  mkdir -p "$initrd"
  cd "$initrd"
  zcat $src | cpio --extract --make-directories
  cd - > /dev/null

  # Add mountroot script
  mountroot="$MKRFS_DIR/linux/bootst.sh"
  [ -e "$mountroot" ] || error "Cannot found $mountroot"
  cp -f "$mountroot" "$initrd/scripts/live"

  # Add static wget
  wget="$MKRFS_DIR/bin/wget.static.$ARCH"
  [ -e "$wget" ] || error "Cannot found $wget"
  [ -e "$initrd/bin/wget" ] && rm -f "$initrd/bin/wget"
  cp "$wget" "$initrd/bin/wget"
  chmod +x "$initrd/bin/wget"

  # Add glibc libraries to resolve DNS
  libs="libnss_dns.so libresolv.so"
  for l in $libs; do
    lib=$( find $rootfs/lib -name "$l.*" )
    if [ -n "$lib" ]; then
      dir=$( dirname $lib )
      [ -d "$initrd/$dir" ] || mkdir -p "$initrd/$dir"
      cp "$lib" "$initrd/$dir"
    fi
  done

  # Add losetup
  [ -e $rootfs/sbin/losetup ] || error "Cannot found $rootfs/sbin/losetup"
  cp $rootfs/sbin/losetup $initrd/sbin/losetup

  # Get kernel version en flavour
  kver=$( ls -d $rootfs/lib/modules/* | sed -n 's/.*\/\(.*\)-\(.*\)/\1/p' )
  kfla=$( ls -d $rootfs/lib/modules/* | sed -n 's/.*\/\(.*\)-\(.*\)/\2/p' )

  # initrd MUST have SquashFS et AUFS support
  m=lib/modules/${kver}-${kfla}
  cp -r $rootfs/$m/kernel/fs/squashfs $initrd/$m/kernel/fs/
  cp -r $rootfs/$m/kernel/ubuntu/aufs $initrd/$m/kernel/ubuntu/

  depmod -a "${kver}-${kfla}" -b "$initrd"

  cd "$initrd"
  find . | cpio --create --format=newc | gzip --stdout > "$dst"
  cd - > /dev/null
}

make_image () {
  [ -n "$3" ] || error "usage: 
$0 make_image <squashfs|raw|qcow2|vmdk|vdi|vpc> <dir|dev> <image>"
  [ ! -e "$3" ] && img="$3" || error "$3 already exist"

  case "$1" in
    squashfs)
      ret=$( which mksquashfs )
      [ "x$ret" != "x" ] || error "try: apt-get install squashfs-tools"
      [ -d "$2" ] && dir="$2" || error "$2 is not a directory"
      mksquashfs "$dir" "$img" -noappend -e /boot
      ;;
    raw|qcow2|vmdk|vdi|vpc)
      ret=$( which qemu-img )
      [ "x$ret" != "x" ] || error "try: apt-get install qemu-utils"
      [ -b "$2" ] && dev="$2" || error "$2 is not a block device"
      qemu-img convert -f raw "$dev" -O "$1" "$img"
      ;;
    *) error "$1 format is not supported"
  esac
  [ $? -eq 0 ] && chmod -x+r+r "$img" || error "image could not be created"
}

make_blockdev () {
  [ -n "$2" ] && sz="$2" || sz="700"
  [ -n "$1" ] && fn="$1" || fn="${sz}mb.bin"

  [ -f "$fn" ] && rm -f "$fn"
  dd if='/dev/zero' of="$fn" bs=1024 count=$(( sz * 1000 ))

  loop=$( losetup --show -f "$fn" )
  if [ -b "$loop" ]; then
    parted -a optimal -s "$loop" mklabel msdos mkpart primary ext2 0% 100%
  fi

  kpartx -a "$loop"
  loopp="/dev/mapper/$( basename "$loop" )p1"
  if [ -b "$loopp" ]; then
    mkfs.ext4 "$loopp"
  fi

  mnt="${fn%.bin}.d"
  [ -f "$mnt" ] || mkdir -p "$mnt"
  mount "$loopp" "$mnt"
  echo "$loopp $mnt"
}

unload_container () {
  [ -b "$1" ] || error "Container device $1 does not exit!"
  [ -n "$1" ] && dn="$1" || error "Missing container device name"

  kpartx -d "$dn"
}

load_container () {
  [ -n "$1" ] && fn="$1" || error "Missing container file name"

  loopdev=$( losetup --show -f "$fn" )
  loopname=$( basename "$loopdev" )
  # size of device (in sectors)
  size=$( cat /sys/block/$loopname/size )
  # major and minor device numbers
  mami=$( cat /sys/block/$loopname/dev )

  dev='hda'
  if [ ! -b "/dev/mapper/$dev" ]; then
    echo "0 $size linear $mami 0" | dmsetup create "$dev" >/dev/null 2>&1
    kpartx -a "/dev/mapper/$dev" >/dev/null 2>&1
  fi

  echo "/dev/mapper/$dev"
}

new_container () {
  [ -n "$1" ] && fn="$1" || error "Missing container file name"
  # input size of container (in sectors), default is 2GB=4*1024*1024*512
  [ -n "$2" ] && sz="$2" || sz="4194304"

  [ -f "$fn" ] && rm -f "$fn"
  dd if='/dev/zero' of="$fn" bs=512 count=$sz

  dn=$( load_container "$fn" )

  if [ -n "$dn" -a -b "$dn" ]; then
    parted -a optimal -s "$dn" mklabel msdos mkpart primary ext2 0% 100%
    kpartx -a "$dn" >/dev/null 2>&1
    echo "$dn"
  fi
}
