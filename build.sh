#!/bin/bash
version=`cat VERSION`

version_file=gems/bayserver-core/lib/baykit/bayserver/version.rb
temp_version_file=/tmp/version.rb
sed "s/VERSION=.*/VERSION='${version}'/" ${version_file} > ${temp_version_file}
mv ${temp_version_file} ${version_file}

pushd .
cd gems
today=$(date +%Y-%m-%d)
for d in *; do
  cd $d
  cp ../../LICENSE.* ../../README.* .
  spec=$d.gemspec
  sed -e "s/\\\${VERSION}/${version}/" -e "s/\\\${DATE}/${today}/" ${spec}.template > ${spec}
  gem build $spec
  cd ..
done
popd


target_name=BayServer_Ruby-${version}
target_dir=/tmp/${target_name}
rm -fr ${target_dir}
mkdir ${target_dir}

cp -r stage/* ${target_dir}
cp LICENSE.BAYKIT NEWS.md README.md ${target_dir}


echo "****** Rackup ******"
rackup -p 9292 &
pid=$!
echo "PID: ${pid}"
sleep 5

for name in `ls -r gems`; do
  echo "****** Local uploading Gem: ${name} ******"
  gem inabox --host http://localhost:9292 gems/${name}/${name}-${version}.gem
done

pushd .
cd ${target_dir}
echo "****** Local Install gem: bayserver ******"
gem install -s http://localhost:9292 bayserver:${version} --install-dir=gems
popd

for name in `ls -r gems`; do
  echo "****** Local remove Gem: ${name} ******"
  curl -X DELETE http://localhost:9292/gems/${name}-${version}.gem
done

kill ${pid}

cd ${target_dir}
bin/bayserver.sh -init
sed -i -e '1s%.*%#!/usr/bin/ruby%' gems/bin/bayserver_rb
rm gems/bin/bayserver_rb-e

cd /tmp
tar czf ${target_name}.tgz ${target_name}

