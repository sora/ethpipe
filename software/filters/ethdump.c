#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>

int fd;
void set_signal (int sig);
void sig_handler (int sig);

int main() {
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

	long clock, pktlen;
	int len, pb_len, i, padding;
	unsigned char pb_head[40], pb_tail[4], padding_bit = 0x00;
//	unsigned char pb_hdr[27];

	char *filename = "ethpipe.pcapng";

	fd = open( filename, O_WRONLY | O_CREAT );
	if (fd < 0) {
		fprintf( stderr, "Cannot open file\n" );
		exit(1);
	}
	set_signal(SIGINT);

	// write pcap headers (SHB+IDB)
	memcpy(obuf, SHB, sizeof(SHB));
	offset += sizeof(SHB);
	memcpy(obuf+offset, IDB, sizeof(IDB));
	offset += sizeof(IDB);
	write(fd, obuf, offset);

	// PB
	while ( ( len = read(0, ibuf, 2000) >= 0 ) ) {
		memset(obuf, 0, sizeof(obuf));
		offset = 0;

		clock  = *(long *)&ibuf[2];
		pktlen = *(short *)&ibuf[6];
		
		padding = 4 - pktlen % 4;
		if (padding == 4)
			padding = 0;
		pb_len = 28 + pktlen + padding + 4;
		printf( "%08X %4d %d %d %02X%02X%02X%02X%02X%02X %02X%02X%02X%02X%02X%02X\n",
		        clock, pktlen, padding, pb_len, 
		        ibuf[8], ibuf[9], ibuf[10], ibuf[11], ibuf[12], ibuf[13],
		        ibuf[14], ibuf[15], ibuf[16], ibuf[17], ibuf[18], ibuf[19] );

		// PB header
		sprintf( pb_head, "%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c",
		           0x02, 0x00, 0x00, 0x00,
		           pb_len & 0xFF, (pb_len >> 8) & 0xFF, (pb_len >> 16) & 0xFF, pb_len >> 24,
		           0x00, 0x00, 0x00, 0x00,
//		           sec & 0xFF, (sec >> 8) & 0xFF, (sec >> 16) & 0xFF, sec >> 24,
		           0x00, 0x00, 0x00, 0x00,
		           clock & 0xFF, (clock >> 8) & 0xFF, (clock >> 16) & 0xFF, clock >> 24,
		           pktlen & 0xFF, (pktlen >> 8) & 0xFF, (pktlen >> 16) & 0xFF, pktlen >> 24,
		           pktlen & 0xFF, (pktlen >> 8) & 0xFF, (pktlen >> 16) & 0xFF, pktlen >> 24 );
		memcpy(obuf+offset, pb_head, 28);
		offset += 28;

		// Packet data
		memcpy(obuf+offset, ibuf+8, pktlen);
		offset += pktlen;

		// padding
		for (i=0; i<padding; i++) {
			memcpy(obuf+offset+i, &padding_bit, 1);
		}
		offset += padding;

		// Block Total Length
		sprintf (pb_tail, "%c%c%c%c", pb_len & 0xFF, (pb_len >> 8) & 0xFF, (pb_len >> 16) & 0xFF, pb_len >> 24 );
		memcpy(obuf+offset, pb_tail, 4);

		// write PB
		write(fd, obuf, pb_len);
	}

	close(fd);
	return 0;
}

void set_signal (int sig) {
	if ( signal(sig, sig_handler) == SIG_ERR ) {
		fprintf( stderr, "Cannot set signal\n" );
		exit(1);
	}
}

void sig_handler (int sig) {
	if (sig == SIGINT) {
		printf( "saving pcapng file..\n" );
		close(fd);
		exit(0);
	}
}

