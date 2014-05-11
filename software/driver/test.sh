#!/bin/bash

set -e

debug=0

pkt='FFFFFFFFFFFF 001C7E6ABAD1 0800 45 00 00 4E 00 00 40 00 40 11 FB 32 0A 00 15 6E 0A 00 15 FF 04 04 00 89 00 3A 38 03 10 FD 01 10 00 01 00 00 00 00 00 00 20 46 45 45 4E 45 42 46 45 46 44 46 46 46 4A 45 42 43 4E 45 49 46 41 43 41 43 41 43 41 43 41 43 41 00 00 20 00 01'

rx="/dev/ethpipe/0"
tx="/dev/ethpipe/0"
dummy="/tmp/dummypipe"
global_time="/sys/kernel/ethpipe/global_time"
lap_time1="/sys/kernel/ethpipe/local_time1"

pid_dummy=''; pid_global=''; pid_lap='';
if [[ $debug == 1 ]]; then
	tx="/dev/stdout"
	rx=$dummy
	global_time="/tmp/global_time"
	lap_time1="/tmp/local_time1"

	# dummypipe
	if [ ! -e $dummy ]; then
		mkfifo $dummy
	fi
	while true; do
		printf "%016d $pkt\n" `date +%s` > $dummy
	done &
	pid_dummy=$!

	# global_time
	if [ ! -e $global_time ]; then
		mkfifo $global_time
	fi
	while true; do
		printf "%016d\n" `date +%s` > $global_time
	done &
	pid_global=$!

	# lap_time1
	if [ ! -e $lap_time1 ]; then
		mkfifo $lap_time1
	fi
	while true; do
		printf "%016d\n" `date +%s` > $lap_time1
	done &
	pid_lap=$!
fi

### Test 1
echo -n "Test 1: TX .. "
printf "0000000000000000 $pkt\n" > $tx
echo "Pass"
sleep 1

### Test 2
echo -n "Test 2: TX2 .. "
a="0000000000000000 $pkt"
printf "$a\n$a\n$a\n$a\n$a\n" > $tx
echo "Pass"
sleep 1

### Test 3
echo -n "Test 3: RX .. "
printf "0000000000000000 $pkt\n" > $tx
read recv < $rx
if [[ "${recv:17}" != "$pkt" ]]; then
	echo "Failed"
	exit 1
fi
echo "Pass"
sleep 1

### Test 4
echo -n "Test 4: global counter .. "
a=`cat $global_time`
if [[ $a == "0" ]]; then
	echo "Failed"
	exit 1
fi
echo "Pass"
sleep 1

### Test 5
echo -n "Test 5: TX timestamp .. "
a=`cat $lap_time1`
printf "1100000000000000 $pkt\n" > $tx
b=`cat $lap_time1`
if [[ $a == $b ]]; then
	echo "Failed"
	exit 1
fi
echo "Pass"
sleep 1

### Test 6
echo -n "Test 6: RX timestamp .. "
printf "0000000000000000 $pkt\n" > $tx
read recv < $rx
if [[ ${recv:0:16} == "0000000000000000" ]]; then
	echo "Failed"
	exit 1
fi
echo "Pass"
sleep 1

### Test 7
#echo "Test 7: Scheduled TX"

### termination
if [[ $debug == 1 ]]; then
	echo "kill process $pid"
	kill $pid_dummy
	kill $pid_global
	kill $pid_lap
	echo "rm dummyfifo"
	rm $dummy $global_time $lap_time1
fi

