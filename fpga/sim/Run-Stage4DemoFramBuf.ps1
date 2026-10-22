param([string]$VivadoHome=$env:VIVADO_HOME)
$ErrorActionPreference='Stop'; if(-not $VivadoHome){throw 'Set VIVADO_HOME or pass -VivadoHome.'}
$bin=Join-Path $VivadoHome 'bin'; $xvlog=Join-Path $bin 'xvlog.bat'; $xelab=Join-Path $bin 'xelab.bat'; $xsim=Join-Path $bin 'xsim.bat'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\rtl\correction'))
$names=@('demo_radial_mapper.sv','coordinate_fifo.sv','bilinear_sample_planner.sv','procedural_pixel_reader.sv','bilinear_interpolator.sv','stage4_demo_pipeline.sv','stage4_demo_frame_source.sv','stage4_demo_fram_buf.v')
$files=$names|ForEach-Object{Join-Path $root $_}; $tb=Join-Path $PSScriptRoot 'stage4_demo_fram_buf_tb.sv'
$work=Join-Path $PSScriptRoot ('.work\stage4-fram-buf-'+[guid]::NewGuid().ToString('N').Substring(0,8)); New-Item -ItemType Directory $work -Force|Out-Null
Push-Location $work
try{
 & $xvlog --sv --work work --log xvlog.log @files $tb; if($LASTEXITCODE-ne 0){throw 'xvlog failed.'}
 & $xelab work.stage4_demo_fram_buf_tb -s stage4_demo_fram_buf_tb_sim --log xelab.log; if($LASTEXITCODE-ne 0){throw 'xelab failed.'}
 & $xsim stage4_demo_fram_buf_tb_sim -runall --log xsim.log; if($LASTEXITCODE-ne 0){throw 'xsim failed.'}
 if((Select-String xsim.log -Pattern 'FAIL' -Quiet)-or -not(Select-String xsim.log -Pattern 'PASS: stage4 demo fram_buf HDMI wrapper and diagnostics test' -Quiet)){throw 'Stage 4 fram_buf did not report PASS.'}
}finally{Pop-Location}
