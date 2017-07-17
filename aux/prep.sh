

if [[ -z $SNAG_BUILD_DIR ]]
then
  echo "please . {SNAG_BUILD_DIR}/snagrc prior to execution"
  exit
fi

echo "PP_INCLUDES=$PP_INCLUDES"
echo "SNAGC_INCLUDES=$SNAGC_INCLUDES"
echo "SNAGX_INCLUDES=$SNAGX_INCLUDES"
echo "SNAGW_INCLUDES=$SNAGW_INCLUDES"


pkill -f /opt/snag/bin/snagc
ps -ef |grep 'snagc.pl' |grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null

cd $SNAG_BUILD_DIR/snag.git \
&& perl Makefile.PL && make && make test && make install \
&& cd /var/tmp \
&& perl /opt/snag/perls/current/bin/snagc.pl --compile --debug \
&& perl /opt/snag/perls/current/bin/snagw.pl --compile --debug \
&& perl /opt/snag/perls/current/bin/snagp.pl --compile --debug \
cd -

