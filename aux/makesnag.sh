#!/bin/bash

bash prep.sh

mkdir /var/tmp/snag_installer       >/dev/null 2>&1
mkdir /var/tmp/snag_installer/bin   >/dev/null 2>&1
mkdir /var/tmp/snag_installer/sbin  >/dev/null 2>&1

cp /var/tmp/snagc /var/tmp/snag_installer/bin
cp /var/tmp/snagw /var/tmp/snag_installer/bin
cp /var/tmp/snagp /var/tmp/snag_installer/bin
cp /var/tmp/snagx /var/tmp/snag_installer/bin
cp /opt/snag/snag.conf /var/tmp/snag_installer/snag.conf.def
cp /var/tmp/snag_installer/snag.conf.def /var/tmp/snag_installer/snag.conf.sp
sed -i -e "s/^[[:space:]]\{1,\}host[[:space:]]\{1,\}snag.easynews.com/\thost\tsnag-server.puregig.net/" /var/tmp/snag_installer/snag.conf.sp
sed -i -e "s/^[[:space:]]\{1,\}fallbackip[[:space:]]\{1,\}69.16.160.218/\tfallbackip\t69.16.128.254/" /var/tmp/snag_installer/snag.conf.sp
sed -i -e "s/^[[:space:]]\{1,\}port[[:space:]]\{1,\}13341/\tport\t13340/" /var/tmp/snag_installer/snag.conf.sp

dmidecode=`which dmidecode 2>/dev/null`
if [[ -x $dmidecode ]]
then
  cp $dmidecode /var/tmp/snag_installer/sbin
fi

cp install.sh /var/tmp/snag_installer/

cd /var/tmp/

makeself=`which makeself 2>/dev/null || which makeself.sh  2>/dev/null`
if [[ -z $makeself ]]
then
  echo "No makeself found"
fi

$makeself --copy snag_installer snag_installer.sh "SNAG binary installer" ./install.sh

os=`uname -a | awk 'BEGIN {IGNORECASE=1} {if ($0 ~ /Gentoo/) {printf "gentoo"} else if ($0 ~ /Ubuntu/) {printf "ubuntu"} else if ($0 ~ /SunOS/) {printf "solaris"} }'`
arch=`uname -a | awk '{if ($0 ~ /x86_64/) {printf "x86_64"} else {printf "x86"}}'`
: ${os:="gentoo"}
package=$os-$arch

mv snag_installer.sh snag-installer-${package}.sh

cd -

