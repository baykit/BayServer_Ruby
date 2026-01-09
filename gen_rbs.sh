file=$1
if [ "$file" == "" ]; then
  exit
fi

target=`echo $file  | sed -e 's/gems/sig/' -e 's/.rb$/.rbs/'`

echo $file
echo $target
#export RBENV_VERSION=3.1.3

typeprof $file > $target
