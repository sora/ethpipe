#!/bin/bash
#
# usage: bridge.sh </dev/ethpipe/0
#
MY_PORT="0"
#MAC_LEARNING="001122334455:0:"
TEMP_DIR="/tmp/"
MAC_LEARNING_FILE=$TEMP_DIR/MAC.txt
MAC_LEARNING=""
if [ -f $MAC_LEARNING_FILE ] ; then
    MAC_LEARNING=`cat $MAC_LEARNING_FILE`
fi
echo $MAC_LEARNING

while true
do
    read FRAME
    if [ $? == 1 ]; then
        exit
    fi
#    echo $FRAME
    DMAC=${FRAME:0:12}
    SMAC=${FRAME:13:12}
#    echo $DMAC $SMAC

    # regist SMAC LEARNING TABLE
    if [[ ! "$MAC_LEARNING" =~ "$SMAC" ]]; then
        # if SMAC is Unicast then regist MAC_LEARNING
        if [ $((0x$SMAC & 0x010000000000)) -eq 0 ] ; then
           MAC_LEARNING=$MAC_LEARNING$SMAC:$MY_PORT:
#           echo "Regist $SMAC (MAC_LEARNING=$MAC_LEARNING)"
           echo -n $MAC_LEARNING >> $MAC_LEARNING_FILE
        fi
    fi

    # Check and load MAC_LEARNING_FILE
    if [ ${MAC_LEARNING_FILE} -nt ${MAC_LEARNING_FILE}.chk ]; then
        MAC_LEARNING=`cat $MAC_LEARNING_FILE`
        touch ${MAC_LEARNING_FILE}.chk
    fi

    # search port number by DMAC
    PORT=${MAC_LEARNING/*$DMAC:}
    if [ "$PORT" != "$MAC_LEARNING" ] ; then
        PORT=${PORT/:*}
        echo $FRAME >/dev/ethpipe/$PORT
    else
        # flooding
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
    fi
#break
done
