file delete -force work
vlib  work
vmap  work work
vlog -incr +define+IPM_HSST_SPEEDUP_SIM \
D:/pds_2022_6/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_hsstlp/ipm2l_hsstlp_eval/ipm2l_hsstlp/../../../../../arch/vendor/pango/verilog/simulation/GTP_CLKBUFG.v \
D:/pds_2022_6/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_hsstlp/ipm2l_hsstlp_eval/ipm2l_hsstlp/../../../../../arch/vendor/pango/verilog/simulation/modelsim10.2c/hsstlp_lane_source_codes/*.vp\
D:/pds_2022_6/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_hsstlp/ipm2l_hsstlp_eval/ipm2l_hsstlp/../../../../../arch/vendor/pango/verilog/simulation/modelsim10.2c/hsstlp_pll_source_codes/*.vp\
D:/pds_2022_6/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_hsstlp/ipm2l_hsstlp_eval/ipm2l_hsstlp/../../../../../arch/vendor/pango/verilog/simulation/modelsim10.2c/common_lib/*.vp\
D:/pds_2022_6/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_hsstlp/ipm2l_hsstlp_eval/ipm2l_hsstlp/../../../../../arch/vendor/pango/verilog/simulation/GTP_HSSTLP_LANE.v \
D:/pds_2022_6/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_hsstlp/ipm2l_hsstlp_eval/ipm2l_hsstlp/../../../../../arch/vendor/pango/verilog/simulation/GTP_HSSTLP_PLL.v \
D:/pds_2022_6/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_hsstlp/ipm2l_hsstlp_eval/ipm2l_hsstlp/../../../../../arch/vendor/pango/verilog/simulation/GTP_IOBUF.v \
-f ./pango_hsstlp_top_filelist.f -l vlog.log
vsim -novopt +define+IPM_HSST_SPEEDUP_SIM work.hsst_test_top_tb -l vsim.log
do pango_hsstlp_top_wave.do
run -all
