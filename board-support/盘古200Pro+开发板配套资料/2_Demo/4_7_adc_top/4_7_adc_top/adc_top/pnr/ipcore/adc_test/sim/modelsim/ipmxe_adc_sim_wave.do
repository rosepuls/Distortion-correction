onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/adc_a_flag
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/adc_b_flag
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/logic_done_a
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/logic_done_b
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/i_rst_n
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/i_apb_clk
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/i_apb_paddr
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/i_apb_psel
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/i_apb_enable
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/i_apb_pwrite
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/o_apb_prdata
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/o_apb_pready
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/o_over_temp
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/o_user_temp_alarm
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/o_vcc_alarm
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/o_vcca_alarm
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/o_vcc_cram_alarm
add wave -noupdate -radix hexadecimal /ipmxe_adc_sim_tb/u_adc/o_vcc_drm_alarm
configure wave -namecolwidth 178
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {69292865855 fs} {69714801100 fs}
