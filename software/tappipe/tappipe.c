#include <stdio.h>  
#include <stdlib.h>  
#include <fcntl.h>
#include <unistd.h>  
#include <string.h>  
#include <sys/ioctl.h>  
#include <sys/socket.h>  
#include <sys/types.h>  
#include <sys/socket.h>  
  
#include <netinet/in.h>  
#include <netinet/ip6.h>  
#include <arpa/inet.h>
#include <netdb.h>
#include <net/route.h>
  
#include <linux/if.h>  
#include <linux/if_tun.h>  
#include <linux/if_ether.h>
  
int tun_alloc(char *dev)  
{  
	struct ifreq ifr;  
	int fd, err;  
  
	if ( (fd = open("/dev/net/tun", O_RDWR)) < 0) {  
		perror("open");  
		return -1;  
	}  
  
	memset(&ifr, 0, sizeof(ifr));  
  
	/* Flag: IFF_TUN   - TUN device ( no ether header ) 
	 *	   IFF_TAP   - TAP device 
	 * 
	 *	   IFF_NO_PI - no packet information 
	 */  
  
	ifr.ifr_flags = IFF_TAP | IFF_NO_PI;  
	if (*dev)  
		strncpy(ifr.ifr_name, dev, IFNAMSIZ);  
	  
	if ((err = ioctl(fd, TUNSETIFF, (void *)&ifr)) < 0) {  
		perror("TUNSETIFF");  
		close(fd);  
		return err;  
	}  
	strcpy(dev, ifr.ifr_name);  
	return fd;  
}  
  
void packetout(const unsigned char *pkt, unsigned length)  
{  
	int i, olen;  
	unsigned char obuf[16000];
	  
	sprintf( obuf, "%02X%02X%02X%02X%02X%02X %02X%02X%02X%02X%02X%02X %02X%02X",
		pkt[0x00], pkt[0x01], pkt[0x02], pkt[0x03], pkt[0x04], pkt[0x05], // dst mac address
		pkt[0x06], pkt[0x07], pkt[0x08], pkt[0x09], pkt[0x0a], pkt[0x0b], // src mac address
		pkt[0x0c], pkt[0x0d] );						// frame type
	olen = strlen(obuf);
	for ( i=14; i<(length); ++i) {
		sprintf(obuf+olen+(i-14)*3, " %02X", pkt[i+0x10] );
	}
	strcat(obuf, "\n" );
	write (1, obuf, strlen(obuf));
}  
  
int main(int argc, char **argv)  
{  
	char dev[IFNAMSIZ];  
	unsigned char buf[32000], tmp_pkt[9100], *ptr, *cr;
	int i, frame_len, pos;
	int fd, fd4;  
	fd_set fdset;  
	struct ifreq ifr;  
	struct in6_rtmsg rt;  
  
	if (argc != 2) {  
		fprintf(stderr,"Usage:%s {devicename}\n",argv[0]);  
		return 1;  
	}  
	strcpy(dev,argv[1]);  
	fd = tun_alloc(dev);  
	if (fd < 0) {  
		return 1;  
	}  
	/* ifup */  
	strncpy(ifr.ifr_name,dev,IFNAMSIZ);  
	fd4 = socket(PF_INET,SOCK_DGRAM,0);  
	if (fd4 < 0) {  
		return 1;  
	}  
	if (ioctl(fd4, SIOCGIFFLAGS, &ifr) != 0) {  
		perror("SIOCGIFFLAGS");  
		return 1;  
	}  
	ifr.ifr_flags |= IFF_UP | IFF_RUNNING;  
	if (ioctl(fd4, SIOCSIFFLAGS, &ifr) != 0) {  
		perror("SIOCSIFFLAGS");  
		return 1;  
	}  
	  
	memset(&rt,0,sizeof(rt));  
	/* get ifindex */  
	memset(&ifr, 0, sizeof(ifr));  
	strncpy(ifr.ifr_name,dev,IFNAMSIZ);  
	if (ioctl(fd4, SIOGIFINDEX, &ifr) <0) {  
		perror("SIOGIFINDEX");  
		return 1;  
	}  
		  
	while (1) {  
		int ret;  
		FD_ZERO(&fdset);  
		FD_SET(STDIN_FILENO, &fdset);  
		FD_SET(fd, &fdset);  
		ret = select(fd + 1, &fdset, NULL, NULL, NULL);  
		if (ret == -1) {  
			perror("select");  
			return 1;  
		}  
		if (FD_ISSET(fd, &fdset)) {  
			ret = read(fd, buf, sizeof(buf));  
//fprintf(stderr, "read from socket=%d\n", ret);
			if (ret == -1)  
				perror("read");  
			packetout(buf, ret);  
		}  
		if (FD_ISSET(STDIN_FILENO, &fdset)) {  
			ret = read(STDIN_FILENO,buf,sizeof(buf));  
//fprintf(stderr, "read from stdin=%d\n", ret);

			for ( i = 0, cr = buf; *cr != '\n' && i < ret; ++cr, ++i );

			frame_len = 0;
			pos = 0;

			for ( ptr = buf; ptr < cr && frame_len < 9000 ; ++ptr ) {
				// skip space
				if (*ptr == ' ')
					   continue;
				// conver to upper char
				if (*ptr >= 'a' && *ptr <= 'z')
					   *ptr -= 0x20;
				// is hexdigit?
				if (*ptr >= '0' && *ptr <= '9') {
					if ( pos == 0 ) {
						tmp_pkt[frame_len] = (*ptr - '0') << 4;
						pos = 1;
					} else {
						tmp_pkt[frame_len] |= (*ptr - '0');
						++frame_len;
						pos = 0;
					}
				} else if (*ptr >= 'A' && *ptr <= 'Z') {
					if ( pos == 0 ) {
						tmp_pkt[frame_len] = (*ptr - 'A' + 10) << 4;
						pos = 1;
					} else {
						tmp_pkt[frame_len] |= (*ptr - 'A' + 10);
						++frame_len;
						pos = 0;
					}
				}
			}
//fprintf(stderr, "write_len=%d\n", frame_len);
			ret = write(fd, tmp_pkt, frame_len);  
		}  
	}  
	close(fd);  
	return 0;  
}
