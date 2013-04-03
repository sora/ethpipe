BIT = $(BASE)_$(BASE).bit

$(BIT):
	diamondc cmd/build.tcl

load: $(BIT)
	diamondc cmd/load.tcl
