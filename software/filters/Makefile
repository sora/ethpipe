#obj-m := ethbtoa.o

default: ethbtoa ethdump
	gcc -O -o ethbtoa ethbtoa.c
	gcc -O -o ethdump ethdump.c

clean:
	rm -f *.o ethbtoa ethdump
