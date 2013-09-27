#!/bin/bash
#
# usage: bridge.sh </dev/ethpipe/0
#
MY_PORT="0"
TEMP_DIR="/tmp/"

while true
do
    read FRAME
    if [ $? == 1 ]; then
        exit
    fi

    DMAC=${FRAME:0:12}
    SMAC=${FRAME:13:12}

    # regist SMAC LEARNING TABLE
    if [ ! -f $TEMP_DIR$SMAC ]; then
        if [ $((0x$SMAC & 0x010000000000)) -eq 0 ]; then
            echo $MY_PORT  > $TEMP_DIR$SMAC
        fi
    fi

    # search port number by DMAC
    if [ -f $TEMP_DIR$DMAC ]; then
        exec 3< $TEMP_DIR$DMAC
        read PORT 0<&3
#       echo $DMAC $PORT
        exec 3<&-
        echo $FRAME >/dev/ethpipe/$PORT
    else
        # flooding
        if [ ! $MY_PORT == "0" ]; then
            echo $FRAME >/dev/ethpipe/0
        fi
        if [ ! $MY_PORT == "1" ]; then
            echo $FRAME >/dev/ethpipe/1
        fi
        if [ ! $MY_PORT == "2" ]; then
            echo $FRAME >/dev/ethpipe/2
        fi
        if [ ! $MY_PORT == "3" ]; then
            echo $FRAME >/dev/ethpipe/3
        fi
    fi
done

