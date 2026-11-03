param([string]$PdsShell='D:\FPGA\PDS\PDS_2022.2-SP6.4-win64\PDS_2022\PDS_2022.2-SP6.4\bin\pds_shell.exe')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$start=Get-Date
$log=Join-Path $root 'overlap-build.log'
$manifest=Join-Path $root 'overlap-build.json'
$project=Join-Path $root 'HDMI_IN_DDR3_HDMI_OUT.pds'
$bitstream=Join-Path $root 'generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit'
$timing=Join-Path $root 'report_timing/HDMI_IN_DDR3_HDMI_OUT_top.rtr'
if(!(Test-Path -LiteralPath $PdsShell)){throw "PDS not found: $PdsShell"}
$inputs=@(Get-ChildItem -LiteralPath (Join-Path $root 'source'),(Join-Path $root 'ipcore') -File -Recurse)
$inputs+=Get-Item -LiteralPath (Join-Path $root 'HDMI_IN_DDR3_HDMI_OUT_top.fdc')
$hashes=@{};foreach($f in $inputs){$hashes[$f.FullName]=(Get-FileHash -LiteralPath $f.FullName).Hash}
@{status='incomplete';started=$start.ToString('o');debug_core=$false} | ConvertTo-Json | Set-Content -LiteralPath $manifest
Push-Location $root
try { & $PdsShell -project $project -run gen_bit_stream *> $log; if($LASTEXITCODE -ne 0){throw "PDS failed; see $log"} } finally {Pop-Location}
if(Select-String -LiteralPath $log -Pattern '^E:' -Quiet){throw "PDS error; see $log"}
foreach($f in @($bitstream,$timing)){if(!(Test-Path -LiteralPath $f) -or (Get-Item -LiteralPath $f).LastWriteTime -lt $start){throw "Missing fresh artifact: $f"}}
foreach($f in $hashes.Keys){if((Get-FileHash -LiteralPath $f).Hash -ne $hashes[$f]){throw "Input changed during build: $f"}}
$met=Select-String -LiteralPath $timing -Pattern 'Design Summary : All Constraints Met' -Quiet
$debugInserted=Select-String -LiteralPath $log -Pattern '^Core Insertion Complete' -Quiet
if($debugInserted){throw 'Unexpected debug core insertion: this build was configured without a FIC.'}
@{status=if($met){'complete'}else{'timing_failed'};started=$start.ToString('o');finished=(Get-Date).ToString('o');debug_core=$false;bitstream_sha256=(Get-FileHash -LiteralPath $bitstream).Hash;timing_sha256=(Get-FileHash -LiteralPath $timing).Hash;source_hashes=$hashes} | ConvertTo-Json | Set-Content -LiteralPath $manifest
if(!$met){throw "Bitstream generated but timing failed; see $timing"}
Write-Host "PASS: fresh bitstream, timing met, no debug core: $bitstream"
