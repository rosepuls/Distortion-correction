Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot

$requiredPaths = @(
    'rtl\algorithm\distortion\coordinate_gen.sv',
    'rtl\algorithm\interpolation\bilinear_interp.sv',
    'rtl\algorithm\preprocess\rgb2gray.sv',
    'rtl\algorithm\detect\sobel_3x3.sv',
    'rtl\platform\common\memory\cached_pixel_fetch_engine.sv',
    'rtl\board\pgl50h\pgl50h_board_top.sv',
    'rtl\vendor\pgl50h\ddr\wr_rd_ctrl_top.v',
    'boards\pgl50h\constraints\pgl50h_board_top.fdc',
    'boards\pgl50h\pds\pgl50h_rtl_synth\pgl50h_rtl_synth.pds'
)

foreach ($relativePath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath))) {
        throw "缺少重构后的必需路径: $relativePath"
    }
}

$legacyRoots = @(
    'rtl\distortion',
    'rtl\interpolation',
    'rtl\preprocess',
    'rtl\detect',
    'rtl\memory',
    'rtl\board\mes50hp',
    'rtl\vendor\mes50hp',
    'constraints\mes50hp',
    'pds\pgl50h_rtl_synth'
)

foreach ($relativePath in $legacyRoots) {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath)) {
        throw "遗留目录尚未迁移: $relativePath"
    }
}

$activeFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'sim') -File -Filter '*.ps1' -Recurse |
        Where-Object { $_.Name -ne 'check_project_layout.ps1' }
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'boards\pgl50h\pds') -File -Filter '*.pds' -Recurse
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'boards\pgl50h\pds') -File -Filter '*.tcl' -Recurse
)

$legacyPattern = 'rtl[\\/](distortion|interpolation|preprocess|detect|memory|board[\\/]mes50hp|vendor[\\/]mes50hp)|constraints[\\/]mes50hp'
foreach ($file in $activeFiles) {
    if (Select-String -LiteralPath $file.FullName -Pattern $legacyPattern -Quiet) {
        throw "活动工程文件仍引用旧目录: $($file.FullName)"
    }
}

$pdsPath = Join-Path $projectRoot 'boards\pgl50h\pds\pgl50h_rtl_synth\pgl50h_rtl_synth.pds'
$pdsRoot = Split-Path -Parent $pdsPath
$pdsText = Get-Content -LiteralPath $pdsPath -Raw
$pdsReferences = [regex]::Matches($pdsText, '\(_(?:file|ip|ip_source_item)\s+"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

foreach ($relativePath in $pdsReferences) {
    if (-not (Test-Path -LiteralPath (Join-Path $pdsRoot $relativePath))) {
        throw "PDS 工程引用不存在的文件: $relativePath"
    }
}

Write-Host 'PASS: project layout follows the algorithm/platform/board/vendor split.'
