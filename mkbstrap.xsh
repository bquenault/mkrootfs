#!/bin/sh
# Make bootstrap script loader
#
# Require: dd, tar (for extraction and exec)
#          cat, let, sed, tar (for encapsulation)

# DO NOT EDIT THESE VARIABLES BY HAND #
IDX='' #
DIR='' #
CMD='' #

usage () {
  echo "Usage: $0 output-script directory [path] [cmd] [args]" >&2
  [ -n "$1" ] && echo "$1" >&2
  exit 1
}
parse () {
  for o in $*; do
    [ -z "$F" -a ! -e "$o" ] && F="$o"    && continue
    [ -z "$D" -a   -d "$o" ] && D="$o"    && continue
    [ -n "$F" -a   -z "$P" ] && P="$o"    && continue
    [ -n "$P" -a   -z "$X" ] && X="$o"    && continue
    [ -n "$X"              ] && X="$X $o" && continue
  done
  [ -z "$F" ] && usage "Existing or missing output script."
  [ -z "$D" ] && usage "Missing directory to encapsulate."
}
loader () {
  [ -d "$DIR" ] && cd "$DIR" #
  [ -n "$IDX" ] && dd if="$0" bs=1 skip=$IDX 2>/dev/null | tar -xzv #
  [ -n "$CMD" ] && $CMD #
  exit $? #
}
savekv () {
  sed -e "s/^$1='.*'/$1='$( echo $2 | sed 's/\//\\\//g' )'/" -i "$3"
}
addlen () {
  expr $1 + $2
}
strlen () {
  expr $( echo "$1" | wc -c ) - 1
}
offset () {
  s=$( addlen $1 $2 ) ; l=$( strlen $s )
  [ $2 -eq $l ] && echo $s || echo $( offset $1 $l )
}
create () {
  echo '#!/bin/sh' > "$2"
  sed -n 's/^[ ]*\(.*\) #$/\1/p' "$1" >> "$2"
  chmod +x "$2"
  [ -n "$4" ] && savekv 'DIR' "$4" "$2"
  [ -n "$5" ] && savekv 'CMD' "$5" "$2"
  savekv 'IDX' "$( offset $( cat "$2" | wc -c ) 0 )" "$2"
  tar -czv "$3" >> "$2"
}
parse $*
create "$0" "$F" "$D" "$P" "$X"
exit 0
