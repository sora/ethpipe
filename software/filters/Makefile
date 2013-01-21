#obj-m := ethbtoa.o

default: ethbtoa ethdump
	gcc -O -o ethbtoa.o ethbtoa.c
	gcc -O -o ethdump.o ethdump.c

clean:
	rm -f *.o ethbtoa ethdump
