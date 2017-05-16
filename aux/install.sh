#!/bin/bash

pkill snagc
pkill snagc.pl
pkill snagx

ps -ef |grep 'snag[cx]$' |awk '{print $2}' | xargs kill 2>/dev/null
ps -ef |grep 'snag[cx].pl$' |awk '{print $2}' | xargs kill 2>/dev/null

echo "Creating /opt/snag base dir"
mkdir -p -m 0755 /opt/snag   2>/dev/null
mkdir -p -m 0755 /opt/snag/log  2>/dev/null
mkdir -p /opt/snag/bin  2>/dev/null
mkdir -p /opt/snag/sbin 2>/dev/null
mkdir -p /opt/snag/conf 2>/dev/null

chmod 0755 /opt/snag /opt/snag/log
chmod 0644 /opt/snag/log/*

echo "Copying snag binaries to /opt/snag"
dir=`pwd`
echo $dir
cp -a bin/* /opt/snag/bin/
cp -a sbin/* /opt/snag/sbin/

if [ ! -e "/opt/snag/snag.conf" ]
then
  if [ ! -z $1 ]
  then
        echo "Copying $1 config"
        cp snag.conf.$1 /opt/snag/snag.conf
  else
        echo "Copying default config"
        cp snag.conf.def /opt/snag/snag.conf
  fi
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

/opt/snag/bin/snagw
