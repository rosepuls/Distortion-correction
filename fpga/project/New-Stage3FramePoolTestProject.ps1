param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage3_frame_pool_test')
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stableRelative = 'fpga/project/stage2_ddr3_720p60_rgbx8888'
$stableDirectory = Join-Path $repoRoot $stableRelative
$projectDirectory = [System.IO.Path]::GetFullPath($ProjectDirectory)

if (-not (Test-Path -LiteralPath $stableDirectory -PathType Container)) {
    throw "Stable RGBX8888 project not found: $stableDirectory"
}
if (Test-Path -LiteralPath $projectDirectory) {
    throw "Existing test project will not be overwritten: $projectDirectory"
}

# Copy only Git-tracked project inputs, so implementation outputs from the
# accepted RGBX8888 build do not become part of the experimental project.
$tracked = @(& git -C $repoRoot ls-files -- $stableRelative)
if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) {
    throw 'Could not enumerate the tracked stable project files.'
}

New-Item -ItemType Directory -Path $projectDirectory | Out-Null
foreach ($relative in $tracked) {
    $insideProject = $relative.Substring($stableRelative.Length).TrimStart('/')
    $destination = Join-Path $projectDirectory ($insideProject -replace '/', '\')
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot ($relative -replace '/', '\')) -Destination $destination
}

$managerSource = Join-Path $repoRoot 'fpga\rtl\memory\frame_pool_manager.v'
$managerDestination = Join-Path $projectDirectory 'source\rtl\frame_pool_manager.v'
Copy-Item -LiteralPath $managerSource -Destination $managerDestination
$addressSource = Join-Path $repoRoot 'fpga\rtl\memory\frame_pool_address.v'
$addressDestination = Join-Path $projectDirectory 'source\rtl\frame_pool_address.v'
Copy-Item -LiteralPath $addressSource -Destination $addressDestination
$schedulerSource = Join-Path $repoRoot 'fpga\rtl\memory\frame_pipeline_ownership.v'
$schedulerDestination = Join-Path $projectDirectory 'source\rtl\frame_pipeline_ownership.v'
Copy-Item -LiteralPath $schedulerSource -Destination $schedulerDestination
$readArbiterSource = Join-Path $repoRoot 'fpga\rtl\memory\ddr_read_burst_arbiter.v'
$readArbiterDestination = Join-Path $projectDirectory 'source\rtl\ddr_read_burst_arbiter.v'
Copy-Item -LiteralPath $readArbiterSource -Destination $readArbiterDestination
$admissionSource = Join-Path $repoRoot 'fpga\rtl\memory\capture_frame_admission.v'
$admissionDestination = Join-Path $projectDirectory 'source\rtl\capture_frame_admission.v'
Copy-Item -LiteralPath $admissionSource -Destination $admissionDestination
$pixelGateSource = Join-Path $repoRoot 'fpga\rtl\memory\capture_pixel_gate.v'
$pixelGateDestination = Join-Path $projectDirectory 'source\rtl\capture_pixel_gate.v'
Copy-Item -LiteralPath $pixelGateSource -Destination $pixelGateDestination
$writeTrackerSource = Join-Path $repoRoot 'fpga\rtl\memory\ddr_write_drain_tracker.v'
$writeTrackerDestination = Join-Path $projectDirectory 'source\rtl\ddr_write_drain_tracker.v'
Copy-Item -LiteralPath $writeTrackerSource -Destination $writeTrackerDestination
$smokeSource = Join-Path $repoRoot 'fpga\sim\frame_pool_pair_smoke_top.v'
$smokeDestination = Join-Path $projectDirectory 'source\rtl\frame_pool_pair_smoke_top.v'
Copy-Item -LiteralPath $smokeSource -Destination $smokeDestination
$pipelineSmokeSource = Join-Path $repoRoot 'fpga\sim\frame_pipeline_smoke_top.v'
$pipelineSmokeDestination = Join-Path $projectDirectory 'source\rtl\frame_pipeline_smoke_top.v'
Copy-Item -LiteralPath $pipelineSmokeSource -Destination $pipelineSmokeDestination
& (Join-Path $PSScriptRoot 'Apply-Stage3CaptureIntegration.ps1') -ProjectDirectory $projectDirectory

$pdsPath = Join-Path $projectDirectory 'HDMI_IN_DDR3_HDMI_OUT.pds'
$pds = [System.IO.File]::ReadAllText($pdsPath)
$anchor = '                (_file "source/rtl/frame_slot_manager.v"'
if ($pds.Split([string[]]@($anchor), [System.StringSplitOptions]::None).Count -ne 2) {
    throw 'Expected one frame_slot_manager source entry in the copied PDS project.'
}
$timestamp = (Get-Item -LiteralPath $managerDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource = "                (_file `"source/rtl/frame_pool_manager.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$timestamp`")`r`n                )`r`n"
$addressTimestamp = (Get-Item -LiteralPath $addressDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource += "                (_file `"source/rtl/frame_pool_address.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$addressTimestamp`")`r`n                )`r`n"
$schedulerTimestamp = (Get-Item -LiteralPath $schedulerDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource += "                (_file `"source/rtl/frame_pipeline_ownership.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$schedulerTimestamp`")`r`n                )`r`n"
$readArbiterTimestamp = (Get-Item -LiteralPath $readArbiterDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource += "                (_file `"source/rtl/ddr_read_burst_arbiter.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$readArbiterTimestamp`")`r`n                )`r`n"
$admissionTimestamp = (Get-Item -LiteralPath $admissionDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource += "                (_file `"source/rtl/capture_frame_admission.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$admissionTimestamp`")`r`n                )`r`n"
$pixelGateTimestamp = (Get-Item -LiteralPath $pixelGateDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource += "                (_file `"source/rtl/capture_pixel_gate.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$pixelGateTimestamp`")`r`n                )`r`n"
$writeTrackerTimestamp = (Get-Item -LiteralPath $writeTrackerDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource += "                (_file `"source/rtl/ddr_write_drain_tracker.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$writeTrackerTimestamp`")`r`n                )`r`n"
$smokeTimestamp = (Get-Item -LiteralPath $smokeDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource += "                (_file `"source/rtl/frame_pool_pair_smoke_top.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$smokeTimestamp`")`r`n                )`r`n"
$pipelineSmokeTimestamp = (Get-Item -LiteralPath $pipelineSmokeDestination).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
$newSource += "                (_file `"source/rtl/frame_pipeline_smoke_top.v`"`r`n                    (_format verilog)`r`n                    (_timespec `"$pipelineSmokeTimestamp`")`r`n                )`r`n"
$pds = $pds.Replace($anchor, $newSource + $anchor)
[System.IO.File]::WriteAllText($pdsPath, $pds)

# A second PDS entry selects the two-pool synthesis top while retaining the
# same target device and source list. It never replaces the video project.
$smokePds = $pds.Replace(
    '(_file "source/rtl/HDMI_IN_DDR3_HDMI_OUT_top.v" + "HDMI_IN_DDR3_HDMI_OUT_top"',
    '(_file "source/rtl/HDMI_IN_DDR3_HDMI_OUT_top.v"')
$smokePds = $smokePds.Replace(
    '(_file "source/rtl/frame_pool_pair_smoke_top.v"',
    '(_file "source/rtl/frame_pool_pair_smoke_top.v" + "frame_pool_pair_smoke_top"')
$smokePds = $smokePds.Replace(
    '(_option top_module (_string "HDMI_IN_DDR3_HDMI_OUT_top"))',
    '(_option top_module (_string "frame_pool_pair_smoke_top"))')
$smokePds = $smokePds.Replace(
    '(_file "HDMI_IN_DDR3_HDMI_OUT_top.fdc"',
    '(_file "frame_pool_smoke.fdc"')
[System.IO.File]::WriteAllText((Join-Path $projectDirectory 'frame_pool_smoke.pds'), $smokePds)
$pipelinePds = $smokePds.Replace(
    '(_file "source/rtl/frame_pool_pair_smoke_top.v" + "frame_pool_pair_smoke_top"',
    '(_file "source/rtl/frame_pool_pair_smoke_top.v"')
$pipelinePds = $pipelinePds.Replace(
    '(_file "source/rtl/frame_pipeline_smoke_top.v"',
    '(_file "source/rtl/frame_pipeline_smoke_top.v" + "frame_pipeline_smoke_top"')
$pipelinePds = $pipelinePds.Replace(
    '(_option top_module (_string "frame_pool_pair_smoke_top"))',
    '(_option top_module (_string "frame_pipeline_smoke_top"))')
$pipelinePds = $pipelinePds.Replace(
    '(_file "frame_pool_smoke.fdc"',
    '(_file "frame_pipeline_smoke.fdc"')
[System.IO.File]::WriteAllText((Join-Path $projectDirectory 'frame_pipeline_smoke.pds'), $pipelinePds)
[System.IO.File]::WriteAllText(
    (Join-Path $projectDirectory 'frame_pool_smoke.fdc'),
    "create_clock -name clk [get_ports clk] -period 10.000 -waveform {0.000 5.000}`r`n")
[System.IO.File]::WriteAllText(
    (Join-Path $projectDirectory 'frame_pipeline_smoke.fdc'),
    "create_clock -name clk [get_ports clk] -period 10.000 -waveform {0.000 5.000}`r`ncreate_clock -name pix_clk [get_ports pix_clk] -period 13.468 -waveform {0.000 6.734}`r`n")

$readme = @'
# Stage 3 frame-pool test project

This project is a tracked-input copy of the accepted Stage 2 RGBX8888 PDS
project. The Stage 2 directory is never modified by the generation script.

The video top keeps the accepted RGBX8888 HDMI and DDR datapath, but now
connects the capture pool to the real write and display slots. It gates pixel
writes by frame, uses the DDR IP write completion ID and pulse to decide when
a captured frame can be published, and displays the newest complete captured
frame. This is a capture-to-display test path. It has no copy engine or
processed-output pool in the live video datapath.
The write source busy signal includes synchronized line triggers, the pending
line request, and the legacy write controller's ready state. The admission
controller waits eight DDR clocks after VS before checking write drain.
The DDR IP has no standard AXI B response, so board readback is needed to
confirm the IP's completion pulse provides the intended visibility guarantee.
The four frame error LEDs now mean, from bit 3 to bit 0: read busy or write
protocol fault; write line busy; incomplete display frame; aborted capture
frame. The counters saturate and clear only on DDR reset.

`frame_pool_smoke.pds` selects `frame_pool_pair_smoke_top` for PDS synthesis
of two actual manager instances. It is a separate synthesis target; its
ports are test controls, not HDMI/DDR pins.

`frame_pipeline_smoke.pds` selects `frame_pipeline_smoke_top`. Its ownership
scheduler acquires one captured frame and one output slot together, then
publishes the output only after a successful copy completion. It is still a
test synthesis target without a DDR copy engine. It also instantiates the
read-burst arbiter with a synthetic return-data port. Capture admission is
connected to the scheduler, and pixel gating is connected to its permission.
The write drain tracker counts accepted Pango AW commands and corresponding
`axi_wusero_last` events by client ID before admitting a frame publish.
The smoke top supplies synthetic write-side signals; the video top connects
capture signals to the real DDR IP.

Run `../Run-FramePoolSmoke.ps1` to synthesize both managers with PDS. The
script checks the PDS log for errors and verifies both instances in the
generated netlist. The same synthesis top also includes the six-slot DDR word
address mapper.
Run `../Run-FramePoolSmoke.ps1 -Target pipeline` to synthesize the ownership
scheduler and address mapper with PDS.
Run `../Run-Stage3CaptureSynthesis.ps1` to synthesize the actual video top and
check that the capture pool, pixel gate, admission controller, and write
tracker are retained in its netlist.

Run `New-Stage3FramePoolTestProject.ps1` from `fpga/project/` to recreate this
directory from tracked Stage 2 inputs. The script refuses to overwrite an
existing directory.

`../../sim/frame_pool_manager_tb.v` exercises slot ownership, latest-frame
eviction, abort, and empty takes. Run it with
`../../sim/Run-FramePoolManager.ps1` in Vivado Simulator. The script uses
`VIVADO_HOME` and keeps simulator outputs under `../../sim/.work/`.
Run `../../sim/Run-FramePoolAddress.ps1` to check all six slot base addresses
and the active-frame word boundary.
Run `../../sim/Run-FramePipelineOwnership.ps1` to check copy-start handshake,
display ownership, latest-frame eviction, and failed-copy abort.
Run `../../sim/Run-DdrReadBurstArbiter.ps1` to check pre-reservation, response
routing, RLAST handling, and unexpected-response diagnostics.
Run `../../sim/Run-CaptureFrameControl.ps1` to check capture publication only
after an eight-cycle VS settling interval and write drain, plus whole-frame
pixel gating.
Run `../../sim/Run-DdrWriteDrainTracker.ps1` to check pending and completed
write bursts, per-client isolation, and fault handling.
'@
[System.IO.File]::WriteAllText((Join-Path $projectDirectory 'README.md'), $readme)
Write-Host "Created independent frame-pool test project: $projectDirectory"
