#!/bin/bash

pkill snagc
pkill snagc.pl
pkill snagx

echo "Creating /opt/snag base dir"
mkdir -p /opt/snag   2>/dev/null
mkdir /opt/snag/log  2>/dev/null
mkdir /opt/snag/bin  2>/dev/null
mkdir /opt/snag/sbin 2>/dev/null
mkdir /opt/snag/conf 2>/dev/null

echo "Copying snag binaries to /opt/snag"
dir=`pwd`
echo $dir
cp -a bin/* /opt/snag/bin/
cp -a sbin/* /opt/snag/sbin/

if [ ! -e "/opt/snag/snag.conf" ]
then
  echo "Copying default config"
  cp snag.conf.def /opt/snag/snag.conf
fi

if [[ -d /etc/cron.hourly && ! -x /etc/cron.hourly/snagw ]]
then
  echo "Adding snagw to cron.hourly"
  echo '#!/bin/sh' > /etc/cron.hourly/snagw
  echo '/opt/snag/bin/snagw >/dev/null 2>&1' >>/etc/cron.hourly/snagw
  chmod +x /etc/cron.hourly/snagw
fi 


if [ -e '/etc/conf.d/local.start' ]
then
  startup=`grep snagw /etc/conf.d/local.start|grep -v '^#'`
  
  if [[ -z "$startup" ]]
  then
    echo "Adding snagw to local.start"
    echo '/opt/snag/bin/snagw >/dev/null 2>&1' >> /etc/conf.d/local.start
  fi
  
fi

if [[ -e "/etc/rc.local" ]]
then
  endexit=`grep -v '^$' /etc/rc.local | grep -v '^#' | tail -n 1 |grep 'exit 0'`
  startup=`grep snagw /etc/rc.local |grep -v '^#'`

  if [[ -z "$startup" ]]
  then
    echo "Adding snagw to rc.local"
    echo '' >> /etc/rc.local
    echo '/opt/snag/bin/snagw >/dev/null 2>&1' >> /etc/rc.local
  fi

  if [[ ! -z "$endexit" ]]
  then
    sed -i -e 's/^exit 0//' /etc/rc.local
    echo 'exit 0' >> /etc/rc.local
  fi
fi

if [[ -d "/etc/local.d" ]]
then
    echo "Adding snagw to /etc/local.d/snagw.start"
    echo '/opt/snag/bin/snagw >/dev/null 2>&1' >/etc/local.d/snagw.start
    chmod +x /etc/local.d/snagw.start
fi

echo "Starting snag..."

if [[ ! -e "/opt/snag/log/client.conf" ]]
then
  /opt/snag/bin/snagc --init
else
  /opt/snag/bin/snagw
fi
