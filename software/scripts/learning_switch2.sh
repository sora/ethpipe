#!/bin/bash
#
# usage: bridge.sh </dev/ethpipe/0
#
MY_PORT="0"
MAC_LEARNING=""
#MAC_LEARNING="001122334455"
TEMP_DIR="/tmp/"
MAC_LEARNING_FILE=$TEMP_DIR/MAC$MY_PORT.txt
MAC0_LEARNING_FILE=$TEMP_DIR/MAC0.txt;
MAC1_LEARNING_FILE=$TEMP_DIR/MAC1.txt;
MAC2_LEARNING_FILE=$TEMP_DIR/MAC2.txt;
MAC3_LEARNING_FILE=$TEMP_DIR/MAC3.txt;

touch ${MAC0_LEARNING_FILE} ${MAC0_LEARNING_FILE}.chk
touch ${MAC1_LEARNING_FILE} ${MAC1_LEARNING_FILE}.chk
touch ${MAC2_LEARNING_FILE} ${MAC2_LEARNING_FILE}.chk
touch ${MAC3_LEARNING_FILE} ${MAC3_LEARNING_FILE}.chk

while true
do
    read FRAME
    #echo $FRAME
    DMAC=${FRAME:0:12}
    SMAC=${FRAME:13:12}
#    DMAC=`echo $FRAME|cut -d " " -f 1`
#    SMAC=`echo $FRAME|cut -d " " -f 2`
#DMAC="00FFFFFFFFFF"
#SMAC="003776000001"
    echo $DMAC $SMAC
    # regist SMAC LEARNING TABLE
    if [[ ! "$MAC_LEARNING" =~ "$SMAC" ]]; then
        MAC_LEARNING=$MAC_LEARNING":"$SMAC
        echo "Regist $SMAC (MAC_LEARNING=$MAC_LEARNING)"
        echo $MAC_LEARNING > $MAC_LEARNING_FILE
    fi
    if [ $((0x$DMAC & 0x010000000000)) -ne 0 ] ; then
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
       # search port number by DMAC

       if [ ${MAC0_LEARNING_FILE} -nt ${MAC0_LEARNING_FILE}.chk ]; then
           MAC0_LEARNING=`cat $MAC0_LEARNING_FILE`
           touch ${MAC0_LEARNING_FILE}.chk
       fi
       if [[ "$MAC0_LEARNING" =~ "$DMAC" ]]; then
           echo $FRAME >/dev/ethpipe/0
       fi

       if [ ${MAC1_LEARNING_FILE} -nt ${MAC1_LEARNING_FILE}.chk ]; then
           MAC1_LEARNING=`cat $MAC1_LEARNING_FILE`
           touch ${MAC1_LEARNING_FILE}.chk
       fi
       if [[ "$MAC1_LEARNING" =~ "$DMAC" ]]; then
           echo $FRAME >/dev/ethpipe/1
       fi

       if [ ${MAC2_LEARNING_FILE} -nt ${MAC2_LEARNING_FILE}.chk ]; then
           MAC2_LEARNING=`cat $MAC2_LEARNING_FILE`
           touch ${MAC2_LEARNING_FILE}.chk
       fi
       if [[ "$MAC2_LEARNING" =~ "$DMAC" ]]; then
           echo $FRAME >/dev/ethpipe/2
       fi

       if [ ${MAC3_LEARNING_FILE} -nt ${MAC3_LEARNING_FILE}.chk ]; then
           MAC3_LEARNING=`cat $MAC3_LEARNING_FILE`
           touch ${MAC3_LEARNING_FILE}.chk
       fi
       if [[ "$MAC3_LEARNING" =~ "$DMAC" ]]; then
           echo $FRAME >/dev/ethpipe/3
       fi
    fi
#break
done
