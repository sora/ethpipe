BIT = $(BASE)_$(BASE).bit

$(BIT):
	diamondc cmd/build.tcl

load: $(BIT)
	diamondc cmd/load.tcl

clean:
	rm -f impl1/.build_status impl1/.recordref_modgen
	ls impl1| grep -v -e 'pcs_pipe_8b_x1.txt' | (cd impl1;xargs rm -r)

.PHONY: load clean
