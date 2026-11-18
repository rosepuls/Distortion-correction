@echo off
set bin_path=D:/modelsim/win64pe
cd E:/project/mes100_676/demo_prj/textbook_demo/hdmi_in_sfp_hdmi_out/sim/behav
call "%bin_path%/modelsim"   -do "do {run_behav_compile.tcl};do {run_behav_simulate.tcl}" -l run_behav_simulate.log
if "%errorlevel%"=="1" goto END
if "%errorlevel%"=="0" goto SUCCESS
:END
exit 1
:SUCCESS
exit 0
