#!/bin/bash
#
# usage: nanosecping.sh </dev/ethpipe/0
#

ping_req=`cat ../packets/ping.pkt`
src_ip=${ping_req:67:12}
dst_ip=${ping_req:79:12}

while true
do

	printf "ping from %s.%s.%s.%s to %s.%s.%s.%s\n" $src_ip $dst_ip > /dev/stderr

	# send PING request
	echo $ping_req

	ping_id=${ping_req:103:5}
	ping_no=${ping_req:109:5}

	while true
	do
		read pkt

		if [[ $pkt =~ "$ping_id $ping_no" ]]; then
			echo "pong" > /dev/stderr
			tx_time=`cat /sys/kernel/ethpipe/local_time1`
			rx_time=${pkt:0:16}
			printf "RTT: %d ns (%d clock)\n" $(( (0x${rx_time} - 0x${tx_time}) * 8 )) \
				                              $(( 0x${rx_time} - 0x${tx_time} )) > /dev/stderr
			break
		fi
	done

	sleep 1

done

