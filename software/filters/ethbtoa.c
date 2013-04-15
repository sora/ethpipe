#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main()
{
	unsigned char ibuf[2000], obuf[6000];
	int len, i;
	long long clock;
	long pktlen;
	int olen;

	while ( 1 ) {
		if ( ( len = read(0, &ibuf[0], 1)) <= 0 )
			break;
		if ( ibuf[0] != 0x55 )
			continue;

		if ( ( len = read(0, &ibuf[1], 1)) <= 0 )
			break;
		if ( ibuf[1] != 0xd5 )
			continue;

		if ( ( len = read(0, &ibuf[2], 2)) <= 0 )
			break;
		pktlen = *(short *)&ibuf[2];
		if ( read(0, ibuf+4, pktlen+12) < 0)
			break;
		clock = *(long long *)&ibuf[0x04];
		sprintf( obuf, "%llX %lX %02X%02X%02X%02X%02X%02X %02X%02X%02X%02X%02X%02X %02X%02X",
			clock, pktlen,
			ibuf[0x10], ibuf[0x11], ibuf[0x12], ibuf[0x13], ibuf[0x14], ibuf[0x15], // dst mac address
			ibuf[0x16], ibuf[0x17], ibuf[0x18], ibuf[0x19], ibuf[0x1a], ibuf[0x1b], // src mac address
			ibuf[0x1c], ibuf[0x1d] );                                               // frame type
		olen = strlen(obuf);
		for ( i=14; i<(pktlen); ++i) {
			sprintf(obuf+olen+(i-14)*3, " %02X", ibuf[i+0x10] );
		}
		strcat(obuf, "\n" );
		write (1, obuf, strlen(obuf));
	}

	return 0;
}
