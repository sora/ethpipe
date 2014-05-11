#!/bin/bash
#
# usage: ./ping.sh 10.0.0.2 < /dev/ethpipe/0 | ./crc.sh > /dev/ethpipe/0
#

set -eu

_dst_ip="$1"
_src_ip="$(cat ./IP_ADDRESS4)"
src_mac="$(cat ./MAC_ADDRESS)"
dst_mac=''

ip4_fmt="$(cat ../format/ipaddr4.fmt)"
mac_fmt="$(cat ../format/macaddr.fmt)"
ethhdr_fmt="$(cat ../format/ts+ethhdr.fmt)"
ip4hdr_fmt="$(cat ../format/ip4hdr.fmt)"
icmphdr_fmt="$(cat ../format/icmphdr.fmt)"
pinghdr_fmt="$(cat ../format/pinghdr.fmt)"
payload_fmt="$(cat ../format/payload.fmt)"
arp_fmt="$(cat ../format/arp.fmt)"

ping=($(cat ../packets/ping.apkt))
arp_req=($(cat ../packets/arp_req.apkt))

# dst IP address
dst_ip=''
if [[ $_dst_ip =~ ^${ip4_fmt}$ ]]; then
	dst_ip="$(printf "%02X %02X %02X %02X" \
		${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]})"
	dst_ip=($dst_ip)
else
	echo "Invalid IPv4 format: dst_ip"
	exit 1
fi

# src IP address
src_ip=''
if [[ $_src_ip =~ ^${ip4_fmt}$ ]]; then
	src_ip="$(printf "%02X %02X %02X %02X" \
		${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]})"
	src_ip=($src_ip)
else
	echo "Invalid IPv4 format: src_ip"
	exit 1
fi

# arp request
if [[ ${arp_req[@]} =~ ${ethhdr_fmt}\ ${arp_fmt}\ ${payload_fmt} ]]; then

    # Sender hardware address (SHA)
    arp_req[12]=${src_mac:0:2}; arp_req[13]=${src_mac:2:2}; arp_req[14]=${src_mac:4:2}
    arp_req[15]=${src_mac:6:2}; arp_req[16]=${src_mac:8:2}; arp_req[17]=${src_mac:10:2}

    # Sender protocol address (SPA)
    arp_req[18]=${src_ip[0]}; arp_req[19]=${src_ip[1]}; arp_req[20]=${src_ip[2]}
    arp_req[21]=${src_ip[3]}

    # Target hardware address (THA)
    arp_req[22]="00"; arp_req[23]="00"; arp_req[24]="00"
    arp_req[25]="00"; arp_req[26]="00"; arp_req[27]="00"

    # Target protocol address (TPA)
    arp_req[28]=${dst_ip[0]}; arp_req[29]=${dst_ip[1]}; arp_req[30]=${dst_ip[2]}
    arp_req[31]=${dst_ip[3]}

    # send a packet
    echo ${arp_req[@]}
fi

# arp reply
pkt=''
while true; do
	read pkt
	if [[ $pkt =~ ^[[:xdigit:]]{16}\ $src_mac\ [[:xdigit:]]{12}\ 0806\ ${arp_fmt} ]]; then
		echo "received arp reply."
		echo "SHA" ${BASH_REMATH[6]}
		echo "SPA" ${BASH_REMATH[7]}
		dst_mac=(${BASH_REMATCH[6]})
		dst_mac=${BASH_REMATCH[@]}
		break
	fi
done

echo "ARP success."
echo "dst_mac:" ${dst_mac}

exit 0

# ping request packet
if [[ ${ping[@]} =~ ^${ethhdr_fmt}\ ${icmphdr_fmt}\ ${pinghdr_fmt}\ ${payload_fmt}$ ]]; then
	ping[1]="FFFFFFFFFFFF"
	ping[2]=$src_mac
	ping[16]=${src_ip[0]}; ping[17]=${src_ip[1]}; ping[18]=${src_ip[2]}; ping[19]=${src_ip[3]}
	ping[20]=${dst_ip[0]}; ping[21]=${dst_ip[1]}; ping[22]=${dst_ip[2]}; ping[23]=${dst_ip[3]}
else
	echo "Invalid packet format: ping"
	exit 1
fi

# send ping request
echo ${ping[@]}

while true
do

	printf "ping from %s to %s\n" _$src_ip _$dst_ip > /dev/stderr

	# send PING request
	echo $pingreq


	while true
	do
		read pkt

		if [[ $pkt =~ "$ping_id $ping_no" ]]; then
			echo "pong" > /dev/stderr
			tx_time="$(cat /sys/kernel/ethpipe/local_time1)"
			rx_time=${pkt:0:16}
			printf "RTT: %d ns (%d clock)\n" $(( (0x${rx_time} - 0x${tx_time}) * 8 )) \
				                              $(( 0x${rx_time} - 0x${tx_time} )) > /dev/stderr
			break
		fi
	done

	sleep 1

done
