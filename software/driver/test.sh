#!/bin/sh

set -e

pkt='FFFFFFFFFFFF 001C7E6ABAD1 0800 45 00 00 4E 00 00 40 00 40 11 FB 32 0A 00 15 6E 0A 00 15 FF 04 04 00 89 00 3A 38 03 10 FD 01 10 00 01 00 00 00 00 00 00 20 46 45 45 4E 45 42 46 45 46 44 46 46 46 4A 45 42 43 4E 45 49 46 41 43 41 43 41 43 41 43 41 43 41 00 00 20 00 01'
sudo rmmod ethpipe
sudo modprobe ethpipe
sudo chmod 777 /dev/ethpipe/0
#sudo chmod 777 /dev/ethpipe/1

### Test 1
echo "Test 1"
printf "0000000000000000 $pkt\n" >/dev/ethpipe/0

### Test 2
echo "Test 2"
a=`cat /sys/kernel/ethpipe/local_time1`
printf "1100000000000000 $pkt\n" >/dev/ethpipe/0
echo -n "After: local_time1: "
b=`cat /sys/kernel/ethpipe/local_time1`
if [[ $a == $b ]]; then
    echo "Test 2: Failed"
    exit 1
fi

