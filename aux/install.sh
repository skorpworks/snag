#!/bin/sh

pkill snagc
pkill snagc.pl

if [ ! -d "/opt/snag" ]
then
  echo "Creating /opt/snag base dir"
  mkdir /opt/snag
  mkdir /opt/snag/log
fi

echo "Copying snag binaries to /opt/snag"
cp -a bin /opt/snag
cp -a sbin /opt/snag

if [ ! -e "/opt/snag/snag.conf" ]
then
  echo "Copying default config"
  cp snag.conf.def /opt/snag/snag.conf
fi

startup=`grep snagw /etc/conf.d/local.start`

if [ -z "$startup" ]
then
  echo "Adding snagw to local.start"
  echo '/opt/snag/bin/snagw >/dev/null 2>&1' >> /etc/conf.d/local.start
fi

if [ ! -x /etc/cron.hourly/snagw ]
then
  echo "Adding snagw to cron.hourly"
  echo '#!/bin/sh' > /etc/cron.hourly/snagw
  echo '/opt/snag/bin/snagw >/dev/null 2>&1' >>/etc/cron.hourly/snagw
  chmod +x /etc/cron.hourly/snagw
fi 


echo "Starting snag..."
/opt/snag/bin/snagw

