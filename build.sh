#!/bin/bash
version=`cat VERSION`

version_file=core/baykit/bayserver/version.rb
temp_version_file=/tmp/version.rb
sed "s/VERSION=.*/VERSION='${version}'/" ${version_file} > ${temp_version_file}
mv ${temp_version_file} ${version_file}

target_name=BayServer_Ruby-${version}
target_dir=/tmp/${target_name}
rm -fr ${target_dir}
mkdir ${target_dir}
mkdir ${target_dir}/lib

cp -r core ${target_dir}/lib
cp -r docker ${target_dir}/lib

cp -r test/simple/lib/conf/* stage/lib/conf
cp -r test/simple/www/root stage/www
cp -r test/simple/www/cgi-demo stage/www
cp -r test/simple/www/rack-demo stage/www
cp -r stage/* ${target_dir}
cp LICENSE.BAYKIT ${target_dir}


cd /tmp
tar czf ${target_name}.tgz ${target_name}

