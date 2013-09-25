#
# usage: bridge.sh </dev/ethpipe/0
#
while true
do
    read frame
    #echo $a
    smac=`echo $frame|cut -d " " -f 1`
#smac="00FFFFFFFFFF"
    echo $smac
    if [ $((0x$smac & 0x010000000000)) -ne 0 ] ; then
       echo "group bit"
#       echo $frame >/dev/ethpipe/1
#       echo $frame >/dev/ethpipe/2
#       echo $frame >/dev/ethpipe/3
    else
       echo "uniq bit"
    fi
done
