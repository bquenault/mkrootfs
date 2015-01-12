#!/bin/sh

# --------------------------------------------------------------------------- #
# mkrootfs.sh: make root file-system
#
# To isolate scripts file tree for a given usage:
#   ./mkrootfs.sh -i 'trusty/install.sh live/prepare.sh ubicast/install.sh config/easycast-fq87.conf' selfcopy loader/
#
# To embed scripts file tree in an auto-extracting bootstrap script:
#   ./mkbstrap.xsh loader /space/bootsrv/httpd/loader.xsh /tmp
#
# To do an installation with a specific configuration:
#   MKRFS_DEBUG=1 ./mkrootfs.sh -i 'trusty/install.sh config/easycast-ftest.conf' mkrfs_trusty_server
#   MKRFS_DEBUG=1 ./mkrootfs.sh -i 'ubicast/install.sh config/easycast-ftest.conf' mkrfs_easycast
#
# --------------------------------------------------------------------------- #

basedir='s/\(^.*\)\/.*/\1/p'
getfunc='s/^\([a-zA-Z_]\+[a-zA-Z0-9_]*\) () {$/\1/p'
inhibsl='s/\//\\\//g'

MKRFS_RUN=''
MKRFS_CFN=$( readlink -f "$0" )
MKRFS_DIR=$( echo "$MKRFS_CFN" | sed -n "$basedir" )
[ -n "$MKRFS_INCLUDES" ] || MKRFS_INCLUDES=''
[ -n "$MKRFS_ATTACHED" ] || MKRFS_ATTACHED="$MKRFS_CFN"
MKRFS_BUILTINS=$( sed -n "$getfunc" "$MKRFS_CFN" | tr '\n' ' ' )

usage () {
  cat >&2 << EOF
usage: $0 [-n] [-v] [-a file] [-i file] <function> [argument(s)]

  -n, --dry-run: dry run mode enabled, print without exec
  -v, --verbose: verbose mode enabled, print and exec
  -i file:       file will be sourced and automatically added to attached files
                 file MUST contains ONLY function definitions
  -a file:       attach file to script
  function:      can be one or more of these:

$( echo $MKRFS_BUILTINS | sed 's/ /|/g' )

EOF
  exit 1
}

[ -n "$MKRFS_DEBUG" ] || MKRFS_DEBUG='False'
export MKRFS_DEBUG

error () {
  [ -n "$1" ] && echo "$0: error: $1" >&2
  [ -n "$2" ] && rc=$2 || rc=1
  case "$MKRFS_DEBUG" in
    1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss])
      echo "DEBUG enabled! Loading /bin/bash:"
      /bin/bash
      return $rc
  esac
  exit $rc
}

# test if $1 is defined in name space of shell
is_defined () {
  # /!\ Bug of Dash (/bin/sh)
  # IF shell is '/bin/sh' AND $1 is a directory AND $1 has a trailing slash:
  #   Dash' type return TRUE
  # So, force returning of FALSE in this case
  bug=$( echo "$1" | sed -n 's/\(.*\/$\)/\1/p' )
  [ "x$bug" != "x" -a -d "$bug" ] && return 1

  type "$1" 1>/dev/null 2>&1
  return $?
}

is_builtin () {
  for x in $( echo "$MKRFS_BUILTINS" ); do [ "x$1" = "x$x" ] && return 0; done
  return 1
}

run () {
  [ "x$MKRFS_VERBOSE" = "x1" ] && echo "$0: RUN $@"
  [ "x$MKRFS_DRY_RUN" = "x1" ] && echo "$@" || "$@"
  return $?
}

try () {
  echo "$0: $@" && "$@" || error "$1 command failed!" $?
  return $?
}

existing_path () {
  [ -n "$1" ] || return 255
  [ -n "$2" ] && n="$2" || n=0
  if [ -d "$1" ]; then
    rc=0
  else
    next="${1%/*}"
    [ "x$1" != "x$next" ] || return 254
    existing_path "$next" "$n"
    rc=$(( $? + 1 ))
  fi
  [ $rc -eq $n ] && echo "$1"
  return $rc
}

# --------------------------------------------------------------------------- #

check_defines () {
  while [ $# -gt 0 ]; do
    [ -n "$( eval echo "\$$1" )" ] || error "$1 is undefined."
    shift
  done
}

check_file () {
  [ -n "$1" ] || error 'check_file: missing file argument!'

  # Without optional argument FTO, test only existence of file and return
  if [ ! -n "$2" ]; then
    [ -e "$1" ] && return 0 || return 1
  fi

  # File Test Operator list (ex. 'efsr')
  for fto in $( echo "$2" | sed 's/./& /g' ); do
    [ "-$fto" "$1" ] && return 0
    case "$fto" in
      e) error "$1 does not exist." ;;
      s) error "$1 is empty." ;;
      f) error "$1 is not a regular file." ;;
      d) error "$1 is not a directory." ;;
      b) error "$1 is not a block device." ;;
      r) error "$1 has not read permission." ;;
      w) error "$1 has not write permission." ;;
      x) error "$1 has not execute permission." ;;
      *) error "-$fto $1 is false."
    esac
  done
}

selfcopy () {
  [ -n "$1" ] || error "selfcopy: missing directory argument!"
#  [ -e "$1" ] && error "selfcopy: $1 already exists!"
  for cfn in $MKRFS_ATTACHED; do
    base=$( echo "$cfn" | sed -n "$basedir" )
    dest="${1%/}/${base#$MKRFS_DIR}"
    [ -d "$dest" ] || run mkdir -p "$dest"
    run cp -f "$cfn" "$dest"
  done
}

chroot_exit () {
  # insert here specific post chrooted command(s)

  echo "$0: Unmounting all file-systems in /etc/mtab"
  umount -a

  echo "$0: Unmounting /proc /sys /dev/pts"
  umount -lf /dev/pts
  umount -lf /sys
  umount -lf /proc
}

chrooted () {
  [ -n "$1" ] || return 1

  export HOME=/root
  export LC_ALL=C
  trap chroot_exit 0

  echo "$0: Mounting /proc /sys /dev/pts"
  mount -t proc proc /proc
  mount -t sysfs sysfs /sys
  mount -t devpts devpts /dev/pts

  #echo "$0: Mounting all file-systems in /etc/fstab"
  #mount -a

  # insert here specific pre chrooted command(s)
  
  echo "$0: Executing $@"
  "$@"
  return $?
}

chrootme () {
  check_file "$1" 'edw' && chroot="${1%/}" ; shift
  [ -n "$1" ] && cmd="$1" && shift || cmd='/bin/sh'
  dir="${cmd%/*}"

  if ! is_builtin "$cmd"; then
    # Copy to chroot external file to execute
    if [ ! -e "$chroot$cmd" -a -e "$cmd" ]; then
      echo "$0: Copying temporary $chroot$cmd"
      if [ ! -d "$chroot$dir" ]; then
        rmd=$( existing_path $chroot$dir 1 )
        mkdir -p "$chroot$dir"
      fi
      cp -f "$cmd" "$chroot$cmd"
      rev="echo \"$0: Removing temporary $chroot$cmd\""
      [ -n "$rmd" ] && rev="$rev; rm -rf $rmd" || rev="$rev; rm -f $chroot$cmd"
    fi
    [ -x "$chroot$cmd" ] || chmod +x "$chroot$cmd"
  fi

  echo "$0: Copying itself to $chroot/tmp"
  [ -d "$chroot/tmp" ] || mkdir "$chroot/tmp"
  selfcopy "$chroot/tmp/"

  echo "$0: Copying /etc/resolv.conf /etc/hosts"
  for f in '/etc/resolv.conf' '/etc/hosts'; do
    [ -f "$chroot/$f" ] && mv "$chroot/$f" "$chroot/${f}.chrooted"
    cp -f "$f" "$chroot/$f"
  done

  echo "$0: Mounting $chroot/dev"
  [ -d "$chroot/dev" ] || mkdir "$chroot/dev"
  mount --bind "/dev" "$chroot/dev"

  echo "$0: chroot \"$chroot\" \"/tmp/${0##*/}\" 'chrooted' \"$cmd\" $*"
  chroot "$chroot" "/tmp/${0##*/}" 'chrooted' "$cmd" "$@"
  rc=$?

  for pid in $( lsof -atp ^$$ "$chroot" | xargs ); do
    args=$( ps -o args= $pid )
    if [ "x$args" != "x" ]; then
      echo "$0: Killing process: $pid [$args]"
      kill -9 $pid
      sleep 1
    fi
  done

  echo "$0: Unmounting $chroot/dev"
  umount "$chroot/dev"

  echo "$0: Restoring chrooted /etc/resolv.conf /etc/hosts"
  for f in '/etc/resolv.conf' '/etc/hosts'; do
    if [ -f "$chroot/${f}.chrooted" ]; then
      rm -f "$chroot/$f"
      mv "$chroot/${f}.chrooted" "$chroot/$f"
    fi
  done

  # Reverse temporary stuff
  [ -n "$rev" ] && /bin/sh -c "$rev"

  echo "$0: Removing /tmp/*"
  rm -rf $chroot/tmp/*

  return $rc
}

# Linux specific (>= 2.6.12)
get_nic () {
  [ -n "$1" ] && mac="$( echo "$1" | tr '[:upper:]' '[:lower:]' )" || return 1
  for nic in $( ls /sys/class/net ); do
    cur=$( cat "/sys/class/net/$nic/address" )
    [ "x$cur" = "x$mac" ] && echo "$nic" && return 0
  done
  return 1
}

mask2cidr () {
  bitmask=0
  IFS=.
  for byte in $1; do
    case $byte in
      255) bitmask=$(( bitmask + 8 )) ;;
      254) bitmask=$(( bitmask + 7 )) ;;
      252) bitmask=$(( bitmask + 6 )) ;;
      248) bitmask=$(( bitmask + 5 )) ;;
      240) bitmask=$(( bitmask + 4 )) ;;
      224) bitmask=$(( bitmask + 3 )) ;;
      192) bitmask=$(( bitmask + 2 )) ;;
      128) bitmask=$(( bitmask + 1 )) ;;
      0) ;;
    esac
  done
  echo "/$bitmask"
}

config_nic () {
  [ -n "$1" ] || error "Missing mac address argument"
  # byte in hexadecimal
  bhex='[0-9a-fA-F]\{2\}'
  mac=$( echo "$1" | sed -n "s/^\(\($bhex:\)\{5\}$bhex\)$/\1/p" )
  [ "x$mac" != "x" ] || error "Wrong mac address"
  nic=$( get_nic "$mac" ) || error "Could not found network interface $mac"

  [ -n "$2" ] || error "Missing ip address argument"
  case "$2" in
    [Aa][Uu][Tt][Oo]|[Dd][Hh][Cc][Pp])
      /sbin/dhclient -4 -q $nic
    ;;
    *)
      # unsigned char: 0-255
      uc='\(25[0-5]\|2[0-4][0-9]\|1\?[0-9][0-9]\?\)'
      # netmask in CIDR notation
      cidr='\/\(3[0-2]\|[1-2][0-9]\|[1-9]\)'
      ip=$( echo "$2" | sed -n "s/^\(\($uc\.\)\{3\}$uc\)\($cidr\)\?$/\1/p" )
      [ "x$ip" != "x" ] || error "Wrong ip address"

      msk=$( echo "$2" | sed -n "s/^\(\($uc\.\)\{3\}$uc\)\($cidr\)\?$/\5/p" )
      if [ "x$msk" = "x" ]; then
        [ -n "$3" ] || error "Missing netmask argument"
        msk=$( echo "$3" | sed -n "s/^\(\($uc\.\)\{3\}$uc\)$/\1/p" )
        [ "x$msk" != "x" ] || error "Wrong netmask address"
        msk=$( mask2cidr "$msk")
      fi

      /sbin/ip addr add $ip$msk dev $nic
      /sbin/ip link set $nic up
    ;;
  esac
}

config_network () {
  check_defines NET

#  gw_nic=$( ip route | awk '/default/ { print $5 }' )

  for cfg in $( echo "$NET" | sed 's/|/ /g' ); do
    mac=$( echo $cfg | cut -d';' -f1 )
    ip=$( echo $cfg | cut -d';' -f2 )
    msk=$( echo $cfg | cut -d';' -f3 )
    config_nic "$mac" "$ip" "$msk"
  done

# DEPRECATED VERSION
#    nic=$( get_nic "$mac" ) || error "Could not found network interface $mac"
#    # Interface with default gateway is already configured
#    if [ "x$nic" != "x$gw_nic" ]; then
#      ip=$( echo $cfg | cut -d';' -f2 )
#      msk=$( echo $cfg | cut -d';' -f3 )
#      if [ -n "$ip" -a -n "$msk" ]; then
#        ifconfig $nic $ip netmask $msk up
#      fi
#    fi
#  done
}

# --------------------------------------------------------------------------- #

parse () {
  while [ -n "$1" ]; do
    case "$1" in
      --dry-run|-n) export MKRFS_DRY_RUN='1' ;;
      --verbose|-v) export MKRFS_VERBOSE='1' ;;
      -a|-i)
        if [ -n "$2" ]; then
          case "$1" in
            -a) MKRFS_ATTACHED="$MKRFS_ATTACHED $2" ;;
            -i) MKRFS_INCLUDES="$MKRFS_INCLUDES $2" ;;
          esac
          shift
        fi
      ;;
      *) [ ! -n "$MKRFS_RUN" ] && MKRFS_RUN="$1" || MKRFS_RUN="$MKRFS_RUN $1"
      ;;
    esac
    shift
  done
}

# Relative File List
rflist () {
  ret=''
  while [ -n "$1" ]; do
    # Absolute or relative path?
    echo "$1" | grep -q "^/.*" && cfn="$1" || cfn="$MKRFS_DIR/$1"
    if [ -f "$cfn" ]; then
      rfn=${cfn#$MKRFS_DIR/}
      [ -z "$ret" ] && ret="$rfn" || ret="$ret $rfn"
    fi
    shift
  done
  [ -n "$ret" ] && echo "$ret"
}

launch2 () {
  while [ -n "$1" ]; do
    if is_builtin "$1"; then
      echo "$0: Running $@"
      run "$@"
    fi
    shift
  done
}

launch () {
  func=''
  args=''
  while [ -n "$1" ]; do
    case "$1" in
      # exec in mkrootfs forked process
      chrooted)
        func="$1";
        while [ -n "$2" -a "x$2" != "x:" ]; do
          [ ! -n "$args" ] && args="$2" || args="$args $2"
          shift
        done
        try $func $args
        func='' ; args=''
      ;;
      # exec in mkrootfs main process
      *)
        if [ ! -n "$func" ]; then
          is_builtin "$1" && func="$1" || usage
        else
          if ! is_builtin "$1"; then
            [ ! -n "$args" ] && args="$1" || args="$args $1"
          else
            try $func $args
            func="$1" ; args=''
          fi
        fi
      ;;
    esac
    shift
  done
  if [ -n "$func" ]; then
    try $func $args
  fi
}

# --------------------------------------------------------------------------- #

# Idiom to detect if script is being sourced
[ "${0##*/}" = "mkrootfs.sh" ] || return 0

parse "$@"

MKRFS_ATTACHED=$( rflist $MKRFS_ATTACHED )
MKRFS_INCLUDES=$( rflist $MKRFS_INCLUDES )
for rfn in $MKRFS_INCLUDES; do
  cfn="$MKRFS_DIR/$rfn"
  echo "$0: Sourcing $cfn"
  . "$cfn"
  if [ $? -eq 0 ]; then
    MKRFS_ATTACHED="$MKRFS_ATTACHED $rfn"
    MKRFS_BUILTINS="$MKRFS_BUILTINS $( sed -n "$getfunc" "$cfn" | tr '\n' ' ' )"
  fi
done

export MKRFS_ATTACHED
export MKRFS_INCLUDES
[ -n "$MKRFS_RUN" ] || usage
launch $MKRFS_RUN
exit $?
