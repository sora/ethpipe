#!/bin/bash
#
# usage: nanosecping.sh </dev/ethpipe/0
#
TEMP_DIR="/tmp/"

MY_PORT="0"
SRC_MAC_ADDR="000000000011"
DST_MAC_ADDR="A0369F1850E5"
SRC_IP_ADDR="0A 00 00 6E"
DST_IP_ADDR="0A 00 00 02"
PING_TYPE="08 00"
PING_CRC="C0 88"
PING_ID="37 76"
PING_NO=1
PING_TS="00 00 00 00 00 00 00 00"
PING_DATA="00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"


while true
do

#	PING_NO=$(( ${PING_NO} + 1 ))
	PING_NO_TMP=`printf "%04d\n" ${PING_NO}`

	PING_REQ="9000000000000000 00000000 ${DST_MAC_ADDR} ${SRC_MAC_ADDR} 0800 45 00 00 54 6B 11 40 00 40 01 BB 28 ${SRC_IP_ADDR} ${DST_IP_ADDR} ${PING_TYPE} ${PING_CRC} ${PING_ID} ${PING_NO_TMP:0:2} ${PING_NO_TMP:2:4} ${PING_TS} ${PING_DATA}"

	# send PING request
	printf "ping from %s.%s.%s.%s to %s.%s.%s.%s\n" ${SRC_IP_ADDR} ${DST_IP_ADDR}
	echo $PING_REQ > /dev/ethpipe/${MY_PORT}

	while true
	do
		read FRAME

		if [[ $FRAME =~ "${PING_ID} ${PING_NO_TMP:0:2} ${PING_NO_TMP:2:4}" ]]; then
			echo "pong"
			TX_TIME=`cat /sys/kernel/ethpipe/local_time1`
			RX_TIME=${FRAME:0:16}
			printf "RTT: %d ns\n" $(( (0x${RX_TIME} - 0x${TX_TIME}) * 8 ))
			break
		fi
	done

	sleep 1

done

