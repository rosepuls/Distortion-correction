<#
.SYNOPSIS
Verifies that PDS did not merge the stage-0 calibration pipeline registers
back into their frame-parameter source registers.
#>

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$formalPvf = Join-Path $projectRoot "boards\pgl50h\pds\pgl50h_rtl_synth\synthesize\formal.pvf"
$pnrNetlist = Join-Path $projectRoot "boards\pgl50h\pds\pgl50h_rtl_synth\place_route\pgl50h_board_top_pnr.netlist"
$stage0Registers = @(
    "stage0_fx_q19", "stage0_fy_q19", "stage0_cx_q19", "stage0_cy_q19",
    "stage0_inv_fx_q30", "stage0_inv_fy_q30", "stage0_k1_q28", "stage0_k2_q28",
    "stage0_p1_q28", "stage0_p2_q28"
)

# The radial polynomial has two deliberately registered boundaries.  These
# names must survive implementation: otherwise PDS can legally retime the
# square/radius/Horner chain into one 100 MHz combinational path.
$radialBoundaryRegisters = @(
    "stage2_x2_q18", "stage2_y2_q18", "stage2_xy_q18", "stage2_r2_q18",
    "stage2h_r2_q18", "stage2h_horner_t_q18"
)

foreach ($path in @($formalPvf, $pnrNetlist)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "TEST_FAIL: PDS artifact is missing: $path"
    }
}

$formalText = Get-Content -LiteralPath $formalPvf -Raw
$netlistText = Get-Content -LiteralPath $pnrNetlist -Raw
$errors = 0

foreach ($registerName in $stage0Registers) {
    if ($formalText -match "pvf_reg_merging\s+.*-deleted\s+.*$registerName") {
        Write-Host "TEST_FAIL: PDS merged $registerName instead of preserving the pipeline register"
        $errors++
    }
    if ($netlistText -notmatch [regex]::Escape($registerName + "[")) {
        Write-Host "TEST_FAIL: P&R netlist contains no physical $registerName register"
        $errors++
    }
}

foreach ($registerName in $radialBoundaryRegisters) {
    if ($formalText -match "pvf_reg_merging\\s+.*-deleted\\s+.*$registerName") {
        Write-Host "TEST_FAIL: PDS merged radial pipeline boundary $registerName"
        $errors++
    }
    if ($netlistText -notmatch [regex]::Escape($registerName + "[")) {
        Write-Host "TEST_FAIL: P&R netlist contains no physical radial boundary $registerName"
        $errors++
    }
}

if ($errors -ne 0) {
    throw "TEST_FAIL: stage-0 preservation errors=$errors"
}

Write-Host "TEST_PASS: distortion_core stage-0 and radial pipeline registers preserved"
