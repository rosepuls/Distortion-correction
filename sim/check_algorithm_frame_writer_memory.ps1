$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content (Join-Path $projectRoot 'rtl\board\mes50hp\algorithm_frame_writer.sv') -Raw

if ($source -match 'reg\s*\[31:0\]\s+line_bank[01]\s*\[') {
    throw 'FAIL: algorithm_frame_writer still infers 32-bit distributed line-bank RAM.'
}

if ($source -notmatch 'wr_fram_buf\s+line_bank0_ram') {
    throw 'FAIL: algorithm_frame_writer does not instantiate the official line_bank0 block RAM.'
}

if ($source -notmatch 'wr_fram_buf\s+line_bank1_ram') {
    throw 'FAIL: algorithm_frame_writer does not instantiate the official line_bank1 block RAM.'
}

if ($source -notmatch 'reg\s*\[31:0\]\s+bank_write_data') {
    throw 'FAIL: wr_fram_buf must receive its native 32-bit write word, not a 256-bit beat.'
}

Write-Output 'PASS: algorithm_frame_writer uses the official block-RAM line buffers.'
