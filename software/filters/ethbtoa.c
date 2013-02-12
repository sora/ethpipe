#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main()
{
	unsigned char ibuf[2000], obuf[6000];
	int len, i;
	long clock, pktlen;
	int olen;

	while ( ( len = read(0, ibuf, 2000) >= 0 ) ) {
		clock = *(long long *)&ibuf[0x02];
		pktlen = *(short *)&ibuf[0x0a];
		sprintf( obuf, "%16X %4d %02X%02X%02X%02X%02X%02X %02X%02X%02X%02X%02X%02X %02X%02X",
			clock, pktlen,
			ibuf[0x0c], ibuf[0x0d], ibuf[0x0e], ibuf[0x0f], ibuf[0x10], ibuf[0x11], // dst mac address
			ibuf[0x12], ibuf[0x13], ibuf[0x14], ibuf[0x15], ibuf[0x16], ibuf[0x17], // src mac address
			ibuf[0x18], ibuf[0x19] );                                               // frame type
		olen = strlen(obuf);
		for ( i=14; i<pktlen; ++i) {
			sprintf(obuf+olen+(i-14)*3, " %02X", ibuf[i+0x0c] );
		}
		strcat(obuf, "\n" );
		write (1, obuf, strlen(obuf));
	}

	return 0;
}
