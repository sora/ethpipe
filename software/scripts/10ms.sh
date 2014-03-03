#!/bin/bash

delay=$(( 10000000 / 8 ))        # 10ms

while true
do
	read pkt

	if [[ $pkt =~ ^[0-9A-F]{16} ]]; then
		recv_ts=${pkt:0:16}
		frame=${pkt:16}

		printf "%016X$frame\n" $(( 16#$recv_ts + 10#$delay )) > /dev/ethpipe/0
#		echo $recv_ts
#		printf "%016X$frame\n" $(( 16#$recv_ts + 10#$delay ))
	fi
done

