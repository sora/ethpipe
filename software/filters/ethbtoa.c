#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main()
{
	unsigned char ibuf[2000], obuf[6000];;
	int len, i;
	long clock, pktlen, ftype;
	long long dmac, smac;
	int olen;

	while ( ( len = read(0, ibuf, 2000) >= 0 ) ) {
		clock = *(long *)&ibuf[2];
		pktlen = *(short *)&ibuf[6];
		ftype = *(short *)&ibuf[20];
		sprintf( obuf, "%08X %4d %02X%02X%02X%02X%02X%02X %02X%02X%02X%02X%02X%02X %02X%02X", clock, pktlen, ibuf[8], ibuf[9], ibuf[10], ibuf[11], ibuf[12], ibuf[13], ibuf[14], ibuf[15], ibuf[16], ibuf[17], ibuf[18], ibuf[19], ibuf[20], ibuf[21]);
		olen = strlen(obuf);
		for ( i=14; i<pktlen; ++i) {
			sprintf(obuf+olen+(i-14)*3, " %02X", ibuf[i+8] );
		}
		strcat(obuf, "\n" );
		write (1, obuf, strlen(obuf));
	}

	return 0;
}
