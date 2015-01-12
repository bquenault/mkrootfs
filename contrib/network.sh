#!/bin/sh

usage () {
  echo "usage: $0 start|stop|restart" >&2
  exit 1
}

regex_eth='s/auto \(eth[0-9:]*\)/\1/p'

do_start () {
  for x in $( sed -n "$regex_eth" '/etc/network/interfaces' ); do
    echo "ifup $x"
    ifup $x
  done
}

do_stop () {
  for x in $( sed -n "$regex_eth" '/etc/network/interfaces' ); do
    echo "ifdown $x"
    ifdown $x
  done
}

case "$1" in 
  start) do_start ;;
  stop)  do_stop ;;
  retart)
         do_stop
         sleep 1
         do_start
         ;;
  *)
         usage
esac

exit 0
