#!/bin/bash

set -eu

eth_fmt="^[[:xdigit:]]{16}\ [[:xdigit:]]{12}\ [[:xdigit:]]{12}\ ([[:xdigit:]]{4})"
#eth_fmt="^[[:xdigit:]]{12}\ [[:xdigit:]]{12}\ ([[:xdigit:]]{4})"
ip4_fmt="^([[:xdigit:]])([[:xdigit:]])\ (.{23})\ ([[:xdigit:]]{2})\ ([[:xdigit:]]{2}\ [[:xdigit:]]{2})\ (.{23})"

ip4crc_fmt="^(.{29})\ 00\ 00\ (.+)$"
icmp_fmt="^(.{5})\ ([[:xdigit:]]{2}\ [[:xdigit:]]{2})\ (.+)$"
udp_fmt="^(.{17})\ ([[:xdigit:]]{2}\ [[:xdigit:]]{2})\ (.+)$"

i=0
ret=''

eth_hdr=''
eth_type=''
ip4_hdr=''
#ip4_crc=''
ip4_hdrlen=0
ip4_proto=0

pkt_before=''
pkt_after=''

calc_checksum () {
  data="$1"
  offset=0; sum=0; crc=0
  num=''; crcw=''

  # sum all
  while read -s -n 1 c; do
    if [[ "$c" ]]; then     # skip whitespace

      if [[ "$offset" == 3 ]]; then  # full bit
        num=$num$c
        if [[ "$num" =~ ^[0-9A-F]{4}$ ]]; then
          sum=$(( $sum + 0x$num ))
        fi
        num=''
        offset=0    # count reset
      else
        num=$num$c
        offset=$(( $offset + 1 ))
      fi
    fi
  done <<< $data

  # padding 0
  if [[ "$offset" != 0 ]]; then
    while [[ "$offset" < 4 ]]; do
      num=$num"0"
      offset=$(( $offset + 1 ))
    done
    sum=$(( $sum + 0x$num ))
  fi

  # calc
  crc=$(( ~(($sum & 0xFFFF) + ($sum >> 16)) & 0xFFFF ))
  wcrc=`printf "%04X" $crc`
  printf "%s %s" ${wcrc:0:2} ${wcrc:2:2}
}

# main
while read -s pkt; do
  ip4_proto=0

  # check ethernet format
  if [[ ! $pkt =~ $eth_fmt ]]; then
    echo "crc.sh: Can't perse the ethernet header"
    exit 1
  fi
  pkt=${pkt/${BASH_REMATCH[0]}\ /}
  eth_hdr=${BASH_REMATCH[0]}
  eth_type=${BASH_REMATCH[1]}

  # IPv4 heaer
  if [[ $eth_type == "0800" ]]; then
    # IPv4 header
    if [[ $pkt =~ $ip4_fmt ]]; then
      pkt=${pkt/${BASH_REMATCH[0]}\ /}
      pkt_before="${BASH_REMATCH[1]}${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
      pkt_after="${BASH_REMATCH[6]}"
      ip4_hdrlen=$(( 16#${BASH_REMATCH[2]} ))
      ip4_proto=$(( 16#${BASH_REMATCH[4]} ))
#      ip4_crc=${BASH_REMATCH[5]}

      # clear IPv4 checksum field
      ip4_hdr="${pkt_before} 00 00 ${pkt_after}"

      # calc IPv4 checksum
      ret=`calc_checksum "$ip4_hdr"`
      ip4_hdr="${pkt_before} ${ret} ${pkt_after}"

      # IPv4 options
      if [[ $ip4_hdrlen != 5 ]]; then
        i=5
        while [[ $i < $ip4_hdrlen ]]; do
          if [[ $pkt =~ ^(.{11}) ]]; then
            pkt=${pkt/${BASH_REMATCH[1]}\ /}
            ip4_hdr="${ip4_hdr} ${BASH_REMATCH[1]}"
          fi
          i=$(( $i + 1 ))
        done
      fi
    else
      echo "crc.sh: Can't perse the IPv4 header"
      exit 1
    fi
  else
    echo $eth_hdr $pkt
    continue
  fi

  # ICMP packet
  if [[ $ip4_proto == 1 ]]; then
    # clear ICMP checksum field
    if [[ $pkt =~ $icmp_fmt ]]; then
      pkt_before=${BASH_REMATCH[1]}
      pkt_after=${BASH_REMATCH[3]}
      pkt="${pkt_before} 00 00 ${pkt_after}"
      ret=`calc_checksum "$pkt"`
      echo $eth_hdr $ip4_hdr $pkt_before $ret $pkt_after
    else
      echo "crc.sh: Can't perse the ICMP packet"
      exit 1
    fi
  # UDP packet (only zero padding)
  elif [[ $ip4_proto == 17 ]]; then
    # clear UDP checksum field
    if [[ $pkt =~ $udp_fmt ]]; then
      pkt_before=${BASH_REMATCH[1]}
      pkt_after=${BASH_REMATCH[3]}
      pkt="${pkt_before} 00 00 ${pkt_after}"
#      ret=`calc_checksum "$pkt"`
#      echo $eth_hdr $ip4_hdr $pkt_before $ret $pkt_after
      echo $eth_hdr $ip4_hdr $pkt
    else
      echo "crc.sh: Can't perse the UDP packet"
      exit 1
    fi
  else
    echo $eth_hdr $ip4_hdr $pkt
  fi

done

exit 0
