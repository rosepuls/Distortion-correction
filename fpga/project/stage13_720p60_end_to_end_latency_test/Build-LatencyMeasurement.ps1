param([string]$PdsShell='D:\Pango\PDS_2022.2-SP6.4\bin\pds_shell.exe')
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
$project=Join-Path $projectRoot 'HDMI_IN_DDR3_HDMI_OUT.pds'
$log=Join-Path $projectRoot 'stage13-latency-build.log'
$ficTemplate=Join-Path $projectRoot 'debug_core.fic'
$sourceFic=Join-Path $projectRoot 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.fic'
$outputFic=Join-Path $projectRoot 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.fic'
$bitstream=Join-Path $projectRoot 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.sbit'
$timing=Join-Path $projectRoot 'report_timing\HDMI_IN_DDR3_HDMI_OUT_top.rtr'
if(-not(Test-Path -LiteralPath $PdsShell -PathType Leaf)){throw "PDS shell missing: $PdsShell"}
Copy-Item -LiteralPath $ficTemplate -Destination $sourceFic -Force
$adf=(Join-Path $projectRoot 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.adf') -replace '\\','/'
$ficText=Get-Content -LiteralPath $sourceFic -Raw
$ficText=[regex]::Replace($ficText,'(?m)^Project\.device\.designInputFile=.*$',"Project.device.designInputFile=$adf")
Set-Content -LiteralPath $sourceFic -Value $ficText -NoNewline
Push-Location $projectRoot
try { & $PdsShell -project $project -run gen_bit_stream *> $log; if($LASTEXITCODE -ne 0){throw "PDS failed; inspect $log"} } finally { Pop-Location }
foreach($required in @($log,$sourceFic,$bitstream,$timing)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "Missing build artifact: $required"}}
if(Select-String -LiteralPath $log -Pattern '^E:' -Quiet){throw "PDS reported an error; inspect $log"}
if(-not(Select-String -LiteralPath $log -Pattern 'Action from compile to gen_bit_stream:' -Quiet)){throw "Bitstream flow completion not confirmed; inspect $log"}
if(-not(Select-String -LiteralPath $timing -Pattern 'Design Summary : All Constraints Met' -Quiet)){throw "Timing constraints failed; inspect $timing"}
$ficLines=Get-Content -LiteralPath $sourceFic
$channels=@($ficLines|Where-Object{$_ -match '^Project\.unit<0>\.triggerChannel<0><\d+>='})
if($channels.Count -ne 256){throw "Expected 256 FIC channels, found $($channels.Count)"}
foreach($signal in @('latency_cycles','latency_sample_count')){if(-not($ficLines|Where-Object{$_ -like "*=$signal*"})){throw "Missing latency FIC signal: $signal"}}
Copy-Item -LiteralPath $sourceFic -Destination $outputFic -Force
(Get-Item -LiteralPath $outputFic).LastWriteTime=(Get-Item -LiteralPath $bitstream).LastWriteTime
Write-Host 'PASS: Stage13 latency bitstream generated and timing met.'
Write-Host "BITSTREAM: $bitstream"
Write-Host "BITSTREAM_SHA256: $((Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash)"
Write-Host "FIC: $outputFic"
Write-Host "FIC_SHA256: $((Get-FileHash -LiteralPath $outputFic -Algorithm SHA256).Hash)"
