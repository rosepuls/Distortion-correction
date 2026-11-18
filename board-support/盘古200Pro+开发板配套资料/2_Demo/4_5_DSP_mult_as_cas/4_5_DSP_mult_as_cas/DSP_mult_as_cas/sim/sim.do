 
 quit -sim
 vlib work
 vmap work work
 
 vlog ../src/DSP_mult_addsub_cas.v
 vlog ../src/glbl.v
 vlog ../tb/tb_DSP_mult_addsub_cas.v
 
 vsim -novopt -L unisims_ver -L unimacro_ver -L unifast_ver -lib work work.tb_DSP_mult_addsub_cas glbl
 add wave sim:/tb_DSP_mult_addsub_cas/uut/*
 run 0.01ms