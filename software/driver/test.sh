#!/bin/bash

set -e

pkt='FFFFFFFFFFFF 001C7E6ABAD1 0800 45 00 00 4E 00 00 40 00 40 11 FB 32 0A 00 15 6E 0A 00 15 FF 04 04 00 89 00 3A 38 03 10 FD 01 10 00 01 00 00 00 00 00 00 20 46 45 45 4E 45 42 46 45 46 44 46 46 46 4A 45 42 43 4E 45 49 46 41 43 41 43 41 43 41 43 41 43 41 00 00 20 00 01'
#sudo rmmod ethpipe
#sudo modprobe ethpipe
#sudo chmod 777 /dev/ethpipe/0

### Test 1
echo -n "Test 1: TX .. "
printf "0000000000000000 $pkt\n" >/dev/ethpipe/0
echo "Pass"
sleep 1

### Test 2
echo -n "Test 2: TX2 .. "
a="0000000000000000 $pkt"
printf "$a\n$a\n$a\n$a\n$a\n" > /dev/ethpipe/0
echo "Pass"
sleep 1

### Test 3
echo -n "Test 3: RX .. "
printf "0000000000000000 $pkt\n" >/dev/ethpipe/0
read recv < /dev/ethpipe/0
if [[ "${recv:17}" != "$pkt" ]]; then
    echo "Test 3: Failed"
    exit 1
fi
echo "Pass"
sleep 1

### Test 4
echo -n "Test 4: global counter .. "
a=`cat /sys/kernel/ethpipe/global_time`
if [[ $a == "0" ]]; then
    echo "Test 4: Failed"
    exit 1
fi
echo "Pass"
sleep 1

### Test 5
echo -n "Test 5: TX timestamp .. "
a=`cat /sys/kernel/ethpipe/local_time1`
printf "1100000000000000 $pkt\n" >/dev/ethpipe/0
b=`cat /sys/kernel/ethpipe/local_time1`
if [[ $a == $b ]]; then
    echo "Test 5: Failed"
    exit 1
fi
echo "Pass"
sleep 1

### Test 6
echo -n "Test 6: RX timestamp .. "
printf "0000000000000000 $pkt\n" >/dev/ethpipe/0
read recv < /dev/ethpipe/0
if [[ ${recv:0:16} == "0000000000000000" ]]; then
    echo "Test 6: Failed"
    exit 1
fi
echo "Pass"
sleep 1

### Test 7
echo "Test 7: Scheduled TX"

