

pkill -f /opt/snag/bin/snagc
ps -ef |grep 'snagc.pl' |grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null

export PP_INCLUDES=/var/tmp/snag/script/includes/pp_includes
export SNAGC_INCLUDES=/var/tmp/snag/script/includes/snagc_includes
export SNAGX_INCLUDES=/var/tmp/snag-x/script/includes/snagx_includes

echo "PP_INCLUDES=$PP_INCLUDES"
echo "SNAGC_INCLUDES=$SNAGC_INCLUDES"
echo "SNAGX_INCLUDES=$SNAGX_INCLUDES"

cd /var/tmp/snag \
&& perl Makefile.PL && make && make test && make install \
&& cd /var/tmp \
&& perl /opt/snag/perls/current/bin/snagc.pl --compile --debug \
&& perl /opt/snag/perls/current/bin/snagw.pl --compile --debug \
&& perl /opt/snag/perls/current/bin/snagp.pl --compile --debug \
&& perl /opt/snag/perls/current/bin/snagx.pl --compile --debug \
cd -

#&& mv snagc /opt/snag/bin/  \
#&& tar zvcpf snag.5.12.1.tar.gz  snag/snag.conf  snag/bin/snagc snag/log snag/conf snag/sbin \
#&& mv snag.5.12.1.tar.gz /var/tmp/

