#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main()
{
	unsigned char ibuf[2000], obuf[6000];
	int i;
	long long clock;
	long pktlen;
	int olen;

	while ( 1 ) {
		if ( read(0, ibuf, 2) <= 0 )
			break;
		sprintf(obuf, "%02X %02X", ibuf[0], ibuf[1] );
		pktlen = *(short *)&ibuf[0];
		
		if ( read(0, ibuf, pktlen+10 ) <= 0 )
			break;
		for ( i=0; i<pktlen+10; i++) {
			sprintf(obuf+5+i*3, " %02X", ibuf[i] );
		}
		strcat(obuf, "\n" );
		write (1, obuf, strlen(obuf));
	}
	return 0;
}

