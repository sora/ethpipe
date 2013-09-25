#
# usage: bridge.sh </dev/ethpipe/0
#
MY_PORT="0"
MAC_LEARNING="001122334455"
TEMP_DIR="/tmp/"
MAC_LEARNING_FILE=$TEMP_DIR/MAC$MY_PORT.txt
while true
do
    read FRAME
    #echo $FRAME
    DMAC=`echo $FRAME|cut -d " " -f 1`
    SMAC=`echo $FRAME|cut -d " " -f 2`
#DMAC="00FFFFFFFFFF"
#SMAC="003776000001"
    echo $DMAC $SMAC
    if [ $((0x$SMAC & 0x010000000000)) -ne 0 ] ; then
       echo "Multicast or Broadcast message"
       # transmit to any other port
       if [ ! $MY_PORT == "0" ] ; then
           echo $FRAME >/dev/ethpipe/0
       fi
       if [ ! $MY_PORT == "1" ] ; then
           echo $FRAME >/dev/ethpipe/1
       fi
       if [ ! $MY_PORT == "2" ] ; then
           echo $FRAME >/dev/ethpipe/2
       fi
       if [ ! $MY_PORT == "3" ] ; then
           echo $FRAME >/dev/ethpipe/3
       fi
    else
       echo "Unicast message"
       # regist SMAC LEARNING TABLE
       if [[ ! "$MAC_LEARNING" =~ "$SMAC" ]]; then
           MAC_LEARNING=$MAC_LEARNING":"$SMAC
           echo "Regist $SMAC (MAC_LEARNING=$MAC_LEARNING)"
           echo $MAC_LEARNING > $MAC_LEARNING_FILE
       fi
       # search port number by DMAC
    fi
done
