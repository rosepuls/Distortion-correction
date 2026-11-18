file delete -force work
vlib  work
vmap  work
vlog D:/pango/PDS_2022.2-SP6.4/ip/module_ip/ipmxe_flex_adc/ipmxe_adc_eval/ipmxe_adc/../../../../../arch/vendor/pango/verilog/simulation/GTP_ADC_E2.v
vlog D:/pango/PDS_2022.2-SP6.4/ip/module_ip/ipmxe_flex_adc/ipmxe_adc_eval/ipmxe_adc/../../../../../arch/vendor/pango/verilog/simulation/modelsim10.2c/adc_e2_source_codes/*.vp
vlog -v +define+FOR_GTP_ADC_E2_SIM -f ./ipmxe_adc_sim_filelist.f -l vlog.log
vsim -novopt +define+FOR_GTP_ADC_E2_SIM work.ipmxe_adc_sim_tb -l sim.log
do ipmxe_adc_sim_wave.do
run -all
