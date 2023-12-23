#!/bin/sh
version=`cat VERSION`
push=$1

gems="
bayserver-core
bayserver-docker-ajp
bayserver-docker-cgi
bayserver-docker-fcgi
bayserver-docker-http
bayserver-docker-terminal
bayserver-docker-wordpress
bayserver"

for gem in $gems; do
   gemfile=gems/${gem}/${gem}-${version}.gem
   if [ "$push" != "" ]; then
      gem push $gemfile
   else
      ls $gemfile
   fi
done
