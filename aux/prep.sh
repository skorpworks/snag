

pkill -f /opt/snag/bin/snagc
ps -ef |grep 'snagc.pl' |grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null

cd /var/tmp/snag \
&& perl Makefile.PL && make && make test && make install \
&& cd /var/tmp \
&& perl /opt/snag/perls/current/bin/snagc.pl --compile --debug \
&& perl /opt/snag/perls/current/bin/snagw.pl --compile --debug \
cd -

#&& mv snagc /opt/snag/bin/  \
#&& tar zvcpf snag.5.12.1.tar.gz  snag/snag.conf  snag/bin/snagc snag/log snag/conf snag/sbin \
#&& mv snag.5.12.1.tar.gz /var/tmp/

