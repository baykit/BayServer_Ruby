#!/bin/bash
base=`dirname $0`

args=$*
daemon=
for arg in $args; do
  if [ "$arg" == "-daemon" ]; then
    daemon=1
  fi
done

if [ "$daemon" == 1 ]; then
   ruby $base/bootstrap.rb $* < /dev/null  > /dev/null 2>&1 &
else
   ruby $base/bootstrap.rb $*
fi
