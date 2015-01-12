#!/bin/sh

parse_cmdline () {
  [ "x$1" != "x" ] && STAGE="$1" && export STAGE
  for ARG in `cat /proc/cmdline`; do
    case "$ARG" in
      # Root File-System images (SquashFS)
      rfs=*)
        RFS="$( echo ${ARG#rfs=} | sed -e 's/;/ /g' )"
        export RFS
        ;;
      # Configuration scripts
      cfg=*)
        CFG="$( echo ${ARG#cfg=} | sed -e 's/;/ /g' )"
        export CFG
        ;;
      net=*)
        BMAC="$( echo ${ARG#net=} | cut -f1 -d '|' )"
        BIP="$( echo ${ARG#net=} | cut -f2 -d '|' )"
        [ "x$BIP" = "x" -o "x$BIP" = "xdhcp" ] && BIP='DHCP'
        BMSK="$( echo ${ARG#net=} | cut -f3 -d '|' )"
        BGW="$( echo ${ARG#net=} | cut -f4 -d '|' )"
        BDNS="$( echo ${ARG#net=} | cut -f5 -d '|' )"
        BHOST="$( echo ${ARG#net=} | cut -f6 -d '|' )"
        BDOM="$( echo ${ARG#net=} | cut -f7 -d '|' )"
        export BMAC BIP BMSK BGW BDNS BHOST BDOM
        ;;
      # DEPRECATED: PXELINUX (option "IPAPPEND 3")
      ip=*)
        BIP="$( echo ${ARG#ip=} | cut -f1 -d ':' )"
        BSRV="$( echo ${ARG#ip=} | cut -f2 -d ':' )"
        BGW="$( echo ${ARG#ip=} | cut -f3 -d ':' )"
        BMSK="$( echo ${ARG#ip=} | cut -f4 -d ':' )"
        export BIP BSRV BGW BMSK
        ;;
      BOOTIF=*)
        BMAC=$( echo ${ARG#BOOTIF=} | sed -e 's/^0[01]-//' -e 's/-/:/g' )
        export BMAC
        ;;
      debug=*)
	DEBUG=${ARG#DEBUG=}
        export DEBUG
        ;;
    esac
  done
}

fatal_error () {
  case "$STAGE" in
    1)
      echo "FATAL: $1" 1>&2
      [ "x$DEBUG" = "x1" ] && /bin/sh
      ;;
    2)
      [ "x$DEBUG" = "x1" ] && echo "$0: $1" 1>&2
      ;;
  esac
  exit 1
}

replace_pattern () {
  sed -e "s/___MAC___/$BMAC/g"       -e "s/___NIC___/$BNIC/g" \
      -e "s/___IP___/$BIP/g"         -e "s/___NETMASK___/$BMSK/g" \
      -e "s/___GATEWAY___/$BGW/g"    -e "s/___DNS___/$BDNS/g" \
      -e "s/___HOSTNAME___/$BHOST/g" -e "s/___DOMAIN___/$BDOM/g"
}

get_netdev () {
  if [ "x$1" != "x" ]; then
    for nic in $( ls "/sys/class/net" ); do
      mac=$( cat "/sys/class/net/$nic/address" )
      [ "x$1" = "x$mac" ] && echo "$nic" && return 0
    done
  fi
  return 1
}

get_loopdev () {
  for loop in /sys/block/loop*; do
    if [ $( cat ${loop}/size ) -eq 0 ]; then
      dev="/dev/$( udevinfo -q name -p $loop 2>/dev/null || echo ${loop##*/} )"
      [ -b $dev ] && echo "$dev" && return 0
    fi
  done
  return 1
}

# Configure network in stage1 (initrd temporary root file-system environment)
stage1_config_network () {
  if [ "x$BNIC" != "x" ]; then
    if [ "x$BIP" = "xDHCP" ]; then
      ipconfig ":::::$BNIC:dhcp" || return 1
      dns=$( ipconfig -n $BNIC | awk '/dns0/ { print $5 }' )
      [ "x$dns" != "x0.0.0.0" ] && echo "nameserver $dns" > /etc/resolv.conf
    else
      ipconfig "$BIP::$BGW:$BMSK::$BNIC:none" || return 1
      [ "x$BDNS" != "x" ] && echo "nameserver $BDNS" > /etc/resolv.conf
    fi
    return 0
  fi
  return 1
}

extract_hostname () {
  echo "$1" | sed -n 's/^\([a-z0-9]*\)\.\{0,1\}\([a-z0-9\.]*\)$/\1/p'
}
extract_domain () {
  echo "$1" | sed -n 's/^\([a-z0-9]*\)\.\{0,1\}\([a-z0-9\.]*\)$/\2/p'
}

stage2_get_fqdn () {
  result=$( host -4 -t NS "$1" "$2" 2>/dev/null )
  if [ $? -eq 0 ]; then
    echo $result | sed -n 's/.* \([a-z0-9\.]*\)\.$/\1/p'
    return 0
  fi
  return 1
}

stage2_get_ip () {
  result=$( ifconfig "$1" 2>/dev/null )
  if [ $? -eq 0 ]; then
    echo $result | sed -n 's/.*inet addr:\(\([0-9]*\.\)\{3\}[0-9]*\).*/\1/p'
    return 0
  fi
  return 1
}

# Configure network in stage2 (distrib specific root file-system environment)
stage2_config_network () {
  if [ "x$BNIC" != "x" ]; then
    echo "auto $BNIC" >> /etc/network/interfaces
    if [ "x$BIP" = "xDHCP" ]; then
      echo "iface $BNIC inet dhcp" >> /etc/network/interfaces
    else
      echo "iface $BNIC inet static" >> /etc/network/interfaces
      echo "    address $BIP" >> /etc/network/interfaces
      [ "x$BMSK" != "x" ] && echo "    netmask $BMSK" >> /etc/network/interfaces
      [ "x$BGW" != "x" ] && echo "    gateway $BGW" >> /etc/network/interfaces
    fi

    ifdown --force $BNIC 1>/dev/null 2>&1
    ifup $BNIC 1>/dev/null 2>&1

    ip=$( stage2_get_ip "$BNIC" ) || return 1
    BIP="$ip" && export BIP

    [ "x$BDNS" != "x" ] && host . $BDNS 1>/dev/null 2>&1
    if [ $? -eq 0 ]; then
      fqdn=$( stage2_get_fqdn "$ip" "$BDNS" )
      echo "nameserver $BDNS" > /etc/resolv.conf
    fi

    host="$BHOST"
    # based on current : not set (localhost) or provided by DHCP
    current=$( hostname )
    [ "x$host" = "x" -a "x$current" != "xlocalhost" ] && host=$current
    # based on Reverse DNS
    [ "x$host" = "x" -a "x$fqdn" != "x" ] && host=$( extract_hostname "$fqdn" )
    # based on ip address: a-b-c-d
    [ "x$host" = "x" -a "x$ip" != "x" ] && \
      host=$( echo "$ip" | sed 's/\./-/g' )
    echo "$host" > /etc/hostname
    hostname "$host"
    BHOST="$host" && export BHOST

    dom="$BDOM"
    [ "x$dom" = "x" -a "x$fqdn" != "x" ] && dom=$( extract_domain "$fqdn" )
    if [ "x$dom" != "x" ]; then
      echo "domain $dom" >> /etc/resolv.conf
      echo "search $dom" >> /etc/resolv.conf
      echo "$ip $host.$dom $host" >> /etc/hosts
      BDOM="$dom" && export BDOM
    else
      echo "$ip $host" >> /etc/hosts
    fi

    return 0
  fi
  return 1
}

fetch_url () {
  [ "x$3" != "x" ] && retry=$3 || retry=3
  count=0
  while [ $count -lt $retry ]; do
    wget "$1" -O "$2" 1>/dev/null 2>&1
    [ $? -eq 0 ] && return 0
    count=$(( count + 1 ))
    sleep $count
  done
  return 1
}

# name of this function is imposed
mountroot () {
  set +x
  exec 6>&1
  exec 7>&2
  exec 2>&1

  udevadm trigger
  udevadm settle

  parse_cmdline 1
  [ "x$BMAC" = "x" ] && fatal_error "Missing net=MAC in /proc/cmdline"
  [ "x$RFS" = "x" ] && fatal_error "Missing rfs=URL in /proc/cmdline"

  BNIC=$( get_netdev "$BMAC" ) || fatal_error "Could not found NIC $BMAC"
  export BNIC

  modprobe af_packet # need for DHCP
  echo "INFO: Configuring network $BNIC: $BIP $BMSK $BGW $BDNS $BHOST $BDOM"
  stage1_config_network \
    || fatal_error "Could not set initial network configuration."

  mkdir "/live"
  x=1
  for url in $RFS; do
     url=$( echo "$url" | replace_pattern )
     sqshimg="/live/$x.squashfs"
     echo "INFO: Get $url"
     fetch_url "$url" "$sqshimg" || fatal_error "Could not fetch $url"
     [ $? -eq 0 ] && imglist="$imglist $sqshimg"
     x=$(( x + 1 ))
  done

  modprobe loop         # /dev/loop/*
  modprobe squashfs     # SquashFS support
  for sqshimg in $imglist; do
    loop=$( get_loopdev ) || fatal_error "Could not found free loop device."
    losetup "$loop" "$sqshimg"

    mntptro="/live/ro.$( basename $sqshimg | sed 's/.squashfs//g' )"
    mkdir -p "$mntptro"
    mount -t squashfs -o ro "$loop" "$mntptro"
    if [ $? -eq 0 ]; then
      ro="$ro:$mntptro=ro"
      rolist="$rolist $mntptro"
    else
      fatal_error "Could not mount squashfs image $sqshimg on $mntptro."
    fi
  done

  mntptrw="/rw"
  mkdir -p "$mntptrw"
  mount -t tmpfs -o rw tmpfs "$mntptrw"
  if [ $? -eq 0 ]; then
    rw="$mntptrw=rw"
  else
    fatal_error "Could not mount tmpfs on $mntptrw."
  fi

  # UnionFS support
  union="unionfs"
  modprobe -b $union
  if [ $? -ne 0 ]; then
    union="aufs"
    modprobe -b $union
  fi
  mount -t $union -o dirs=$rw$ro $union $rootmnt || \
    fatal_error "Could not mount unionfs root file-system."

  mkdir -p "$rootmnt/live/rw"
  mount -o bind "$mntptrw" "$rootmnt/live/rw"
  for mntptro in $rolist; do
    mkdir -p "$rootmnt$mntptro"
    mount -o move "$mntptro" "$rootmnt$mntptro"
  done

  [ -d "$rootmnt/boot" ] || mkdir "$rootmnt/boot"

  exec 1>&6 6>&-
  exec 2>&7 7>&-
  set +x
}

postboot () {
  parse_cmdline 2
  [ "x$BMAC" = "x" -o "x$CFG" = "x" ] && exit 0

  BNIC=$( get_netdev "$BMAC" ) || fatal_error "Could not found NIC $BMAC"
  export BNIC

  stage2_config_network

  dir="/tmp/postboot"
  mkdir -p "$dir"

  x=1
  for url in $CFG; do
    url=$( echo "$url" | replace_pattern )
    fetch_url "$url" "$dir/$x" || fatal_error "Could not fetch $url"
    [ $? -eq 0 ] && list="$list $x"
    x=$(( x + 1 ))
  done

  for x in $list; do
    mv "$dir/$x" "$dir/$x.orig"
    cat "$dir/$x.orig" | replace_pattern > "$dir/$x"
    chmod +x "$dir/$x"
    sh -c "$dir/$x" 2>"$dir/$x.log" 1>&2
  done
}

# Idiom to detect if script is being sourced
[ "${0##*/}" = "postboot" ] || return 0

postboot

exit 0
