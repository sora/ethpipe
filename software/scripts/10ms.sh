#!/bin/bash
# usage: ./10ms.sh < /dev/ethpipe/0 > /dev/ethpipe0

delay=$(( 10000000 / 8 ))     # 10ms

while true
do
	read pkt       # recv

	if [[ $pkt =~ ^[0-9A-F]{16} ]]; then
		recv_ts=${pkt:0:16}
		frame=${pkt:16}

		echo "received: ts=$recv_ts" > /dev/stderr
		printf "%016X$frame\n" $(( 16#$recv_ts + 10#$delay ))  # send
	fi
done

