#!/bin/sh

if [ ! -O "$DESTDIR/etc/rc.d" ]; then
  echo "don't have permissions to $DESTDIR/etc/rc.d" 1>&2
  exit 1
fi

cd "$DESTDIR/etc/rc.d" || exit 1

provide_list=`awk '/^# PROVIDE: / { gsub("# PROVIDE: ",""); gsub(" ", "$\n^"); print "^" $0 "$" }' * | tr '\n' '|'`
require_missing_list=`awk '/^# REQUIRE: / { gsub("# REQUIRE: ",""); gsub(" ", "\n"); print $0 }' * | sed -E -e "/${provide_list%%|}/d" -e '/^$/d' -e 's/^/ /' | sort -u | tr '\n' '|'`

if [ -n "$require_missing_list" ]; then
  sed -i.orig -E -e "/^# REQUIRE: /s/${require_missing_list%%|}//g" -e '/^# REQUIRE:$/d' * || exit 1
  rm -f *.orig || exit 1
fi
