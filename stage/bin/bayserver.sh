#!/bin/bash
base=`dirname $0`

args=$*
daemon=
for arg in $args; do
  if [ "$arg" = "-daemon" ]; then
    daemon=1
  fi
done

export GEM_HOME=${base}/../gems

cmd=${base}/../gems/bin/bayserver
if [ "$daemon" = 1 ]; then
   ${cmd} $* < /dev/null  > /dev/null 2>&1 &
else
   ${cmd} $*
fi
