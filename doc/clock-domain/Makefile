BASE=clock

all: svg

svg: $(BASE).dot
	dot -T svg $(BASE).dot -o $(BASE).svg
pdf: $(BASE).dot
	dot -T pdf $(BASE).dot -o $(BASE).pdf
png: $(BASE).dot
	dot -T png $(BASE).dot -o $(BASE).png
clean:
	rm -f $(BASE).png $(BASE).pdf $(BASE).svg

.PHONY: clean pdf png svg
