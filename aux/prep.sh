

pkill -f /opt/snag/bin/snagc
ps -ef |grep '/opt/snag/bin/perl /root/perl5/bin/snagc.pl' |grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null

cd /var/tmp/snag \
&& /opt/snag/bin/perl Makefile.PL && make && make test && make install \
&& cd /var/tmp \
&& /opt/snag/bin/perl /opt/snag/bin/snagc.pl --compile --debug \
&& /opt/snag/bin/perl /opt/snag/bin/snagw.pl --compile --debug \
cd -

#&& mv snagc /opt/snag/bin/  \
#&& tar zvcpf snag.5.12.1.tar.gz  snag/snag.conf  snag/bin/snagc snag/log snag/conf snag/sbin \
#&& mv snag.5.12.1.tar.gz /var/tmp/

