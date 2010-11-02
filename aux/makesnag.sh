#!/bin/sh

sh prep.sh

mkdir /var/tmp/snag_installer
mkdir /var/tmp/snag_installer/bin
mkdir /var/tmp/snag_installer/sbin

cp /var/tmp/snagc /var/tmp/snag_installer/bin
cp /var/tmp/snagw /var/tmp/snag_installer/bin
cp /opt/snag/snag.conf /var/tmp/snag_installer/snag.conf.def
cp `which dmidecode` /var/tmp/snag_installer/sbin

cp install.sh /var/tmp/snag_installer/

cd /var/tmp/

makeself=`which makeself.sh`
if [ ! -z $makeself ]
then
  makeself.sh --copy snag_installer snag_installer.sh "SNAG binary installer" ./install.sh
fi

makeself=`which makeself`
if [ ! -z $makeself ]
then
  makeself --copy snag_installer snag_installer.sh "SNAG binary installer" ./install.sh
fi

cd -

