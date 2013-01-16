#-- Lattice Semiconductor Corporation Ltd.
#-- Synplify OEM project file

#device options
set_option -technology LATTICE-ECP3
set_option -part LFE3_35EA
set_option -package FN484C
set_option -speed_grade -8

#compilation/mapping options
set_option -symbolic_fsm_compiler true
set_option -resource_sharing true

#use verilog 2001 standard option
set_option -vlog_std v2001

#map options
set_option -frequency 200
set_option -fanout_limit 100
set_option -auto_constrain_io true
set_option -disable_io_insertion false
set_option -retiming false; set_option -pipe false
set_option -force_gsr false
set_option -compiler_compatible true
set_option -dup false

add_file -constraint {/home/sora/work/ethout/Implementation/top.sdc}
set_option -default_enum_encoding default

#simulation options


#timing analysis options
set_option -num_critical_paths 3
set_option -num_startend_points 0

#automatic place and route (vendor) options
set_option -write_apr_constraint 0

#synplifyPro options
set_option -fixgatedclocks 3
set_option -fixgeneratedclocks 3
set_option -update_models_cp 0
set_option -resolve_multiple_driver 1

#-- add_file options
set_option -include_path {/home/sora/work/ethout/Implementation}
add_file -verilog {/usr/local/diamond/1.4/cae_library/synthesis/verilog/ecp3.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/sync_logic.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/async_pkt_fifo.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/wb_tlc_cpld_fifo.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/wb_tlc_cpld.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/wb_intf.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/wb_tlc_cr.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/wb_tlc_req_fifo.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/wb_tlc_dec.v}
add_file -verilog {/home/sora/work/ethout/source/wb_tlc/wb_tlc.v}
add_file -verilog {/home/sora/work/ethout/source/ip_tx_arbiter.v}
add_file -verilog {/home/sora/work/ethout/source/ip_crpr_arb.v}
add_file -verilog {/home/sora/work/ethout/source/ip_rx_crpr.v}
add_file -verilog {/home/sora/work/ethout/source/ecp3/pcie_top.v}
add_file -verilog {/home/sora/work/ethout/source/ecp3/pciwb_top.v}
add_file -verilog {/home/sora/work/ethout/source/ipexpress/ecp3/pciex1/pcie_bb.v}
add_file -verilog {/home/sora/work/ethout/source/ipexpress/ecp3/pciex1/pcie_eval/models/ecp3/pcs_pipe_bb.v}
add_file -verilog {/home/sora/work/ethout/Source/pmi_ram_dp.v}
add_file -verilog {/home/sora/work/ethout/Source/ipexpress/ecp3/ram_dp_true/ram_dp_true.v}
add_file -verilog {/home/sora/work/ethout/Implementation/pll.v}

#-- top module name
set_option -top_module top

#-- set result format/file last
project -result_file {/home/sora/work/ethout/Implementation/impl1/top_impl1.edi}

#-- error message log file
project -log_file {top_impl1.srf}

#-- set any command lines input by customer


#-- run Synplify with 'arrange HDL file'
project -run
