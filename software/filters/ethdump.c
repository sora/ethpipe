#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>

void set_signal (int sig);
void sig_handler (int sig);

int caught_signal = 0;

int main() {
	set_signal(SIGINT);

	unsigned char SHB[] = { 0x0a, 0x0d, 0x0d, 0x0a,                           /* Section Header Block */
				0x1c, 0x00, 0x00, 0x00,                           /* Block Total Length */
				0x4d, 0x3c, 0x2b, 0x1a,                           /* Byte-Order Magic */
				0x01, 0x00, 0x00, 0x00,                           /* Major version and Minor Version */
				0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,   /* Section Length */
				0x1c, 0x00, 0x00, 0x00                            /* Block Total Length */
			};

	unsigned char IDB[] = { 0x01, 0x00, 0x00, 0x00,                           /* Block Type */
				0x28, 0x00, 0x00, 0x00,                           /* Block Total Length */
				0x01, 0x00, 0x00, 0x00,                           /* LingType and Reserved */
				0xff, 0xff, 0x00, 0x00,                           /* SnapLen */
				0x0d, 0x00,                                       /* Option Code (if_fcslen) */
				0x01, 0x00,                                       /* Option Length */
				0x04, 0x00, 0x00, 0x00,                           /* Option value */
				0x09, 0x00,                                       /* Option Code (if_tsresol) */
				0x01, 0x00,                                       /* Option Length */
				0x09, 0x00, 0x00, 0x00,                           /* Option value */
				0x00, 0x00, 0x00, 0x00,                           /* Option Code and Option Length */
				0x28, 0x00, 0x00, 0x00                            /* Block Total Length */
			};

	unsigned char ibuf[2000], obuf[4000];
	int offset = 0;

	long long clock_base, clock;
	long pktlen;
	int len, pb_len, i, padding, head_pkt_flg = 0;
	unsigned char pb_head[40], pb_tail[4], padding_bit = 0x00;

	// SHB
	memcpy(obuf, SHB, sizeof(SHB));
	offset += sizeof(SHB);
	// IDB
	memcpy(obuf+offset, IDB, sizeof(IDB));
	offset += sizeof(IDB);

	// PB
	while ( (len = read(0, ibuf, 4)) > 0 ) {
		pktlen = *(short *)&ibuf[0x02];

		if ( ibuf[0] != 0x55 || ibuf[1] != 0xd5 )
			break;
		if ( read(0, ibuf+4, pktlen+12) < 0)
			break;

		clock = *(long long *)&ibuf[0x04];
		if (!head_pkt_flg) {
			clock_base   = clock;
			head_pkt_flg = 1;
		}
		fprintf (stderr, "clock1: %016llX\n", clock);
		clock -= clock_base;
		fprintf (stderr, "clock2: %016llX\t%016llX\n", clock_base, clock);
		
		padding = 4 - pktlen % 4;
		if (padding == 4)
			padding = 0;

		pb_len = 28 + pktlen + padding + 4;

#if 0
		printf( "%llX %lX %d %d %02X%02X%02X%02X%02X%02X %02X%02X%02X%02X%02X%02X %02X%02X\n",
			clock, pktlen, padding, pb_len,
			ibuf[0x10], ibuf[0x11], ibuf[0x12], ibuf[0x13], ibuf[0x14], ibuf[0x15], // dst mac
			ibuf[0x16], ibuf[0x17], ibuf[0x18], ibuf[0x19], ibuf[0x1a], ibuf[0x1b], // src mac
			ibuf[0x1c], ibuf[0x1d] );                                               // frame type
#endif

		// PB header
		sprintf( pb_head, "%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c",
			                0x02,                 0x00,                  0x00,                 0x00,
			       pb_len & 0xFF, (pb_len >> 8) & 0xFF, (pb_len >> 16) & 0xFF,         pb_len >> 24,
			                0x00,                 0x00,                  0x00,                 0x00,
			(clock >> 32) & 0xFF, (clock >> 40) & 0xFF,  (clock >> 48) & 0xFF,          clock >> 56,
			        clock & 0xFF,  (clock >> 8) & 0xFF,  (clock >> 16) & 0xFF, (clock >> 24) & 0xFF,
			       pktlen & 0xFF, (pktlen >> 8) & 0xFF, (pktlen >> 16) & 0xFF,         pktlen >> 24,
			       pktlen & 0xFF, (pktlen >> 8) & 0xFF, (pktlen >> 16) & 0xFF,         pktlen >> 24 );
		memcpy(obuf+offset, pb_head, 28);
		offset += 28;

		// Packet data
		memcpy(obuf+offset, ibuf+0x10, pktlen);
		offset += pktlen;

		// packet data padding
		for (i=0; i<padding; i++)
			memcpy(obuf+offset+i, &padding_bit, 1);
		offset += padding;

		// Block Total Length
		sprintf (pb_tail, "%c%c%c%c", pb_len & 0xFF, (pb_len >> 8) & 0xFF, (pb_len >> 16) & 0xFF, pb_len >> 24 );
		memcpy(obuf+offset, pb_tail, 4);
		offset += 4;

		// save data
		write(1, obuf, offset);

		if (caught_signal)
			exit(0);

		// flush buffer
		offset = 0;
	}
	return 0;
}

void set_signal (int sig) {
	if ( signal(sig, sig_handler) == SIG_ERR ) {
		fprintf( stderr, "Cannot set signal\n" );
		exit(1);
	}
}

void sig_handler (int sig) {
	if (sig == SIGINT)
		caught_signal = 1;
}

