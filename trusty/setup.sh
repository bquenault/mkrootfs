#!/bin/sh

# --------------------------------------------------------------------------- #

# File dependencies:
# - trusty/trusty.packages: list of Ubuntu 14.4 Server packages
#
# Relative to: $MKRFS_DIR/
TRUSTY_PACKAGES='trusty/trusty.packages'
MKRFS_ATTACHED="$MKRFS_ATTACHED $TRUSTY_PACKAGES"

# --------------------------------------------------------------------------- #

[ -n "$APTOPT" ] || export APTOPT="--no-install-recommends --yes --force-yes"

# --------------------------------------------------------------------------- #
# Configure APT sources.list with standard Ubuntu repositories
# --------------------------------------------------------------------------- #
config_apt_sourceslist () {
  check_defines CC

  cat << EOF > '/etc/apt/sources.list'
deb http://${CC}.archive.ubuntu.com/ubuntu/ trusty main restricted
deb http://security.ubuntu.com/ubuntu/ trusty-security main restricted
deb http://${CC}.archive.ubuntu.com/ubuntu/ trusty universe multiverse
deb http://security.ubuntu.com/ubuntu/ trusty-security universe multiverse
EOF
}

config_l10n () {
  check_defines LC CC

  lc="$LC"
  kblayout="$CC"
  case "$kblayout" in
    fr) kbvariant='latin9'
        localzone='Europe/Paris'
        ;;
    gb) kbvariant='intl'
        localzone='Europe/London'
        ;;
    de) kbvariant='nodeadkeys'
        localzone='Europe/Berlin'
        ;;
    es) kbvariant='nodeadkeys'
        localzone='Europe/Madrid'
        ;;
    ch) kbvariant='nodeadkeys'
        localzone='Europe/Zurich'
        ;;
    nl) kbvariant='std'
        localzone='Europe/Amsterdam'
        ;;
     *) kbvariant='altgr-intl'
        localzone='GMT'
        ;;
  esac
  lang=$( echo "$lc" | awk -F'[_.]+' '{ print $1 }' )
  country=$( echo "$lc" | awk -F'[_.]+' '{ print $2 }' )
  charset=$( echo "$lc" | awk -F'[_.]+' '{ print $3 }' )

  rm -rf /usr/lib/locale/*
  rm -f /var/lib/locales/supported.d/*
  grep $lc /usr/share/i18n/SUPPORTED > /var/lib/locales/supported.d/$lc
  locale-gen
  echo "LANG=$lc"   > '/etc/default/locale'
  echo "LANGUAGE=${lang}_${country}:${lang}" >> '/etc/default/locale'
  sed -e "s/XKBLAYOUT=.*$/XKBLAYOUT=\"$kblayout\"/g" \
      -e "s/XKBVARIANT=.*$/XKBVARIANT=\"$kbvariant\"/g" \
      -i '/etc/default/keyboard'
  setupcon --save-only --force
  cp -p "/usr/share/zoneinfo/$localzone" /etc/localtime
}

config_hostname () {
  check_defines HOSTNAME

  echo "$HOSTNAME" > '/etc/hostname'
  hostname "$HOSTNAME"

  if [ -n "$IPADDR" ]; then
    echo "127.0.0.1       localhost" > '/etc/hosts'
    if [ -n "$ALIASES" ]; then
      echo "$IPADDR $ALIASES $HOSTNAME" >> '/etc/hosts'
    else
      echo "$IPADDR $HOSTNAME" >> '/etc/hosts'
    fi
  else
    echo "127.0.0.1       localhost $HOSTNAME" > '/etc/hosts'
  fi
  cat << EOF >> '/etc/hosts'
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
}

config_interfaces () {
  check_defines NET

  cat << EOF > '/etc/network/interfaces'
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback
EOF
  for cfg in $( echo "$NET" | sed 's/|/ /g' ); do
    mac=$( echo $cfg | cut -d';' -f1 )
    nic=$( get_nic "$mac" ) || error "Could not found network interface $mac"
    if [ -e '/lib/udev/rules.d/71-biosdevname.rules' ]; then
      nic=$( /sbin/biosdevname -i $nic )
    fi
    echo >> '/etc/network/interfaces'
    echo "auto $nic" >> '/etc/network/interfaces'
    ip=$( echo $cfg | cut -d';' -f2 )
    if [ "x$ip" = "xdhcp" -o "x$ip" = "xDHCP" ]; then
      echo "iface $nic inet dhcp" >> '/etc/network/interfaces'
    else
      echo "iface $nic inet static" >> '/etc/network/interfaces'
      echo "  address $ip" >> '/etc/network/interfaces'
      msk=$( echo $cfg | cut -d';' -f3 )
      [ "x$msk" != "x" ] && echo "  netmask $msk" >> '/etc/network/interfaces'
      gw=$( echo $cfg | cut -d';' -f4 )
      [ "x$gw" != "x" ] && echo "  gateway $gw" >> '/etc/network/interfaces'
      dns=$( echo $cfg | cut -d';' -f5 )
      [ "x$dns" != "x" ] && echo "nameserver $dns" > '/etc/resolv.conf'
    fi
  done
}

config_users () {
  check_defines ROOT_PWD SYS_SU_NAME SYS_SU_PWD SYS_ADM_NAME SYS_ADM_PWD

  cat << EOF | passwd -q >/dev/null
$ROOT_PWD
$ROOT_PWD
EOF
  if [ -n "$UBICAST_SSH_KEY" ]; then
    [ -d '/root/.ssh' ] || mkdir -p '/root/.ssh'
    echo "$UBICAST_SSH_KEY" > '/root/.ssh/authorized_keys'
    chmod 700 '/root/.ssh/'
    chmod 600 '/root/.ssh/authorized_keys'
  fi
  echo "colorscheme ron" > '/root/.vimrc'

  # Force rights settings of NFS mount (by default, Synology export is 000)
  chmod 755 /home/

  user="$SYS_SU_NAME"
  pass="$SYS_SU_PWD"
  crypt=$( echo $pass | mkpasswd -s -m SHA-512 )
  useradd "$user" --password "$crypt" --groups 'adm,cdrom,sudo,dip,plugdev' \
                  --user-group --comment "$user" --create-home --shell /bin/bash
  if [ -n "$UBICAST_SSH_KEY" ]; then
    [ -d "/home/$user/.ssh" ] || mkdir -p "/home/$user/.ssh"
    echo "$UBICAST_SSH_KEY" > "/home/$user/.ssh/authorized_keys"
    chmod 700 "/home/$user/.ssh/"
    chmod 600 "/home/$user/.ssh/authorized_keys"
  fi
  echo "colorscheme ron" > "/home/$user/.vimrc"

  user="$SYS_ADM_NAME"
  pass="$SYS_ADM_PWD"
  crypt=$( echo $pass | mkpasswd -s -m SHA-512 )
  useradd "$user" --password "$crypt" --groups 'adm,cdrom,sudo,dip,plugdev' \
                  --user-group --comment "$user" --create-home --shell /bin/bash
}

config_fstab () {
  check_defines FS

  cat << EOF > '/etc/fstab'
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
EOF
  for cfg in $( echo "$FS" | sed 's/|/ /g' ); do
    fsname="$( echo $cfg | cut -d';' -f1 )"
    blkdev="$( echo $cfg | cut -d';' -f2 )"
    if [ -b "/dev/$blkdev" ]; then
      fsspec="UUID=$( blkid -o value -s UUID "/dev/$blkdev" )"
      fstype=$( blkid -o value -s TYPE "/dev/$blkdev" )
      case "$fstype" in
        ext2|ext3|ext4)
          mntpt="$( echo $cfg | cut -d';' -f5 )"
          param='   errors=remount-ro 0       1'
          ;;
        swap)
          mntpt='none           '
          param='   sw              0       0'
          ;;
      esac
    else # remote file-system
      fsspec="$fsname"
      mntpt="$blkdev"
      fstype='nfs'
      #param='noatime,hard,intr,sync,_netdev,timeo=200,local_lock=all 0 0'
      param='noatime,hard,intr,sync,_netdev,timeo=200,nolock 0 0'
    fi
    if [ -n "$mntpt" ]; then
      if [ "$mntpt" != "none" ]; then
         [ -d "$mntpt" ] || mkdir -p "$mntpt"
      fi
      echo "$fsspec $mntpt $fstype $param" >> '/etc/fstab'
    fi
  done
}

config_grub () {
  check_defines SYS_SU_NAME

  grub-install --root-directory=/ '/dev/sda'
  sed -e 's/\(GRUB_DEFAULT\)=.*/\1=0/g' \
      -e 's/\(GRUB_HIDDEN_TIMEOUT\)=.*/\1=0/g' \
      -e 's/\(GRUB_HIDDEN_TIMEOUT_QUIET\)=.*/\1=true/g' \
      -e 's/\(GRUB_TIMEOUT\)=.*/\1=0/g' \
      -e 's/\(GRUB_CMDLINE_LINUX_DEFAULT\)=.*/\1="nomodeset"/g' \
      -i '/etc/default/grub'
#  if [ -n "$GRUB_PWD" ]; then
#    cat << EOF2 > '/etc/grub.d/01_auth' 
##! /bin/sh -e
#cat << EOF
#set superusers="$SYS_SU_NAME"
#password $SYS_SU_NAME $GRUB_PWD
#EOF
#EOF2
#    sed -e "s/\(menuentry 'Ubuntu'.*\) {/\1 --unrestricted {/" \
#        -i '/boot/grub/grub.cfg'
#  fi
  update-grub
}

# Install set of packages listed in a file (one per line)
install_pkgset () {
  check_file "$1" 'efsr' && list="$1"

  pkgset=$( cat "$list" | tr '\n' ' ' )
  apt-get $APTOPT install $pkgset
}

# Populate freshly debootstrapped chroot environment to become :
#   Ubuntu 14.04 Server (trusty) release
install_trusty_server () {
  config_apt_sourceslist

  # Inhibit Upstart init control tool
  dpkg-divert --local --rename --add /sbin/initctl
  ln -s /bin/true /sbin/initctl

  apt-get update
  apt-get --yes upgrade

  # First: install Linux Kernel
  apt-get $APTOPT  install linux-signed-generic
  # linux-signed-generic
  # > linux-headers-generic
  #   > linux-headers-$KVER-$KFLAVOUR
  #     > linux-headers-$KVER
  # > linux-signed-image-$KFLAVOUR
  #   > linux-firmware
  #   > linux-signed-image-$KVER-$KFLAVOUR
  #     > linux-image-$KVER-$KFLAVOUR
  #     > linux-image-extra-$KVER-$KFLAVOUR
  #       > linux-image-$KVER-$KFLAVOUR
  #       > sbsigntool

  # Workaround to not be prompt by installation of grub
  export DEBIAN_FRONTEND=noninteractive
  install_pkgset "$MKRFS_DIR/$TRUSTY_PACKAGES"

  # Fix errors encountered while processing: libpam-systemd:amd64
  #   Setting up of libpam-systemd package try to exec System V init script
  #   '/etc/init.d/systemd-logind' but this script does not exist because
  #   it was replaced by Upstart init script '/etc/init/systemd-logind.conf'.
  ln -s /bin/true /etc/init.d/systemd-logind
  dpkg --configure -a
  rm -f /etc/init.d/systemd-logind

  # Install whois for /usr/bin/mkpasswd and nfs-common
  apt-get $APTOPT install whois nfs-common

  # Fix errors encountered while processing: nfs-common
  #   Setting up of nfs-common package try to exec System V init script
  #   '/etc/init.d/{statd,gssd,idmapd' but these scripts do not exist
  #   because there were replaced by Upstart init script...
  initscripts='statd gssd idmapd'
  for script in $initscripts; do ln -s /bin/true /etc/init.d/$script; done
  dpkg --configure -a
  for script in $initscripts; do rm -f /etc/init.d/$script; done

  config_l10n
  config_users
  config_hostname
  config_network
  config_fstab
  mount -a
  rm -rf /home/*
  config_interfaces
  config_grub

  # Restore Upstart init control tool
  rm -f /sbin/initctl
  dpkg-divert --rename --remove /sbin/initctl

  # Anonymize configuration
  rm -f "/etc/ssh/ssh_host_*"
  rm -f "/etc/hostname"
  rm -f "/etc/resolvconf/resolv.conf.d/original"
  rm -f "/etc/resolvconf/resolv.conf.d/tail"
  #rm -f "/var/run/resolvconf/resolv.conf"
}

debootstrap_base () {
  check_file "$1" 'edw' && dir="${1%/}"

  [ -n "$2" ] && arch="$2" || arch='amd64'
  [ -n "$3" ] && dist="$3" || dist='trusty'
  mirror='http://fr.archive.ubuntu.com/ubuntu/'
  debootstrap --version >/dev/null || error 'debootstrap is not installed.'
  debootstrap $dopt --arch="$arch" "$dist" "$dir" "$mirror"
}

prepare_disk () {
  # Partition Table Type: mbr|gpt (default: mbr)
  [ -n "$1" ] && ptt="$1" || ptt='mbr'
  [ "$ptt" = "mbr" -o "$ptt" = "gpt" ] || ptt='mbr'

  check_defines FS
  parted --version >/dev/null || error 'parted is not installed.'

  boot='todo'
  for cfg in $( echo "$FS" | sed 's/|/ /g' ); do
    fsname="$( echo $cfg | cut -d';' -f1 )"
    devn="/dev/$( echo $cfg | cut -d';' -f2 )"
    dev="${devn%[1-9]}"
    if [ -b "$dev" ]; then
      cmd=''
      if [ "$boot" = "todo" ]; then
        devb=$dev
        dd if=/dev/zero of=$dev bs=512 count=34 2>/dev/null
        # Restore MBR sector signature 0x55AA
        echo '55AA' | xxd -r -p | dd of=$dev bs=1 seek=510 count=2 2>/dev/null
        partprobe
        case "$ptt" in
          mbr) cmd="mklabel msdos"; start='0%' ;;
          gpt) cmd="mklabel gpt mkpart non-fs 0% 3145727B"; start='3145728B' ;;
        esac
      fi
      size=$( echo $cfg | cut -d';' -f3 )
      if [ "x$size" != "x*" ]; then
        case "$start" in
          0%|3145728B) end=$size; geom="$start ${end}GB" ;;
          *) end=$(( start + size )); geom="${start}GB ${end}GB" ;;
        esac
      else
        geom="${start}GB 100%"
      fi
      start=$end
      case "$ptt" in
        mbr) cmd="$cmd mkpart primary $geom" ;;
        gpt) cmd="$cmd mkpart \"$fsname\" $geom" ;;
      esac
      if [ "$boot" = "todo" ]; then
        case "$ptt" in
          mbr) cmd="$cmd set 1 boot on" ;;
          gpt) cmd="$cmd set 1 bios_grub on" ;;
        esac
        boot='done'
      fi
      cmd="parted -s -a optimal $dev $cmd"
      echo "$cmd" && $cmd
      partprobe
    fi
    if [ -b "$devn" ]; then
      case "$( echo $cfg | cut -d';' -f4 )" in
        ext4) mkfs.ext4 -q -L "$fsname" $devn ;;
        swap) mkswap $devn >/dev/null 2>&1 ;;
      esac
    fi
  done
  # Optional signature
  echo '57CAB100' | xxd -r -p | dd of=$devb bs=1 seek=440 count=4 2>/dev/null
}

mkrfs_trusty_server () {
  prepare_disk 'mbr'
  rootfs='/mnt/rootfs'
  [ -d "$rootfs" ] || mkdir -p "$rootfs"
  mount '/dev/sda1' "$rootfs"
  debootstrap_base "$rootfs"
  chrootme "$rootfs" install_trusty_server
  umount "$rootfs"
}
