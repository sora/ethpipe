#!/bin/bash

pkt1='A0369F1850e5 001C7E6ABAD1 0800 45 00 00 4E 00 00 40 00 40 11 FB 32 0A 00 00 6E 0A 00 00 02 04 04 00 89 00 3A 38 03 10 FD 01 10 00 01 00 00 00 00 00 00 20 46 45 45 4E 45 42 46 45 46 44 46 46 46 4A 45 42 43 4E 45 49 46 41 43 41 43 41 43 41 43 41 43 41 00 00 20 00 01'
pkt2='A0369F1850e5 001C7E6ABAD1 0800 45 00 00 4E 00 00 40 00 40 11 FB 32 0A 00 00 6E 0A 00 00 02 04 04 00 89 00 3A 38 03 10 FD 01 10 00 01 00 00 00 00 00 00 20 46 45 45 4E 45 42 46 45 46 44 46 46 46 4A 45 42 43 4E 45 49 46 41 43 41 43 41 43 41 43 41 43 41 00 00 20 00 02'
pkt3='A0369F1850e5 001C7E6ABAD1 0800 45 00 00 4E 00 00 40 00 40 11 FB 32 0A 00 00 6E 0A 00 00 02 04 04 00 89 00 3A 38 03 10 FD 01 10 00 01 00 00 00 00 00 00 20 46 45 45 4E 45 42 46 45 46 44 46 46 46 4A 45 42 43 4E 45 49 46 41 43 41 43 41 43 41 43 41 43 41 00 00 20 00 03'
pkt4='A0369F1850e5 001C7E6ABAD1 0800 45 00 00 4E 00 00 40 00 40 11 FB 32 0A 00 00 6E 0A 00 00 02 04 04 00 89 00 3A 38 03 10 FD 01 10 00 01 00 00 00 00 00 00 20 46 45 45 4E 45 42 46 45 46 44 46 46 46 4A 45 42 43 4E 45 49 46 41 43 41 43 41 43 41 43 41 43 41 00 00 20 00 04'
pkt5='A0369F1850e5 001C7E6ABAD1 0800 45 00 00 4E 00 00 40 00 40 11 FB 32 0A 00 00 6E 0A 00 00 02 04 04 00 89 00 3A 38 03 10 FD 01 10 00 01 00 00 00 00 00 00 20 46 45 45 4E 45 42 46 45 46 44 46 46 46 4A 45 42 43 4E 45 49 46 41 43 41 43 41 43 41 43 41 43 41 00 00 20 00 05'

now=$(( 16#`cat /sys/kernel/ethpipe/global_time` ))
ts=$(( $now + 0xEE6B280 ))

delay="0xEE6B280"            # 1 sec

printf "%016X $pkt1\n" $ts
ts=$(( $ts + $delay ))
printf "%016X $pkt2\n" $ts
ts=$(( $ts + $delay ))
printf "%016X $pkt3\n" $ts
ts=$(( $ts + $delay ))
printf "%016X $pkt4\n" $ts
ts=$(( $ts + $delay ))
printf "%016X $pkt5\n" $ts

