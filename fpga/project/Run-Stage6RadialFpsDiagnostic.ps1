param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage6_radial_fps_debug'),
    [string]$PdsShell = 'D:\Pango\PDS_2022.2-SP6.4\bin\pds_shell.exe'
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Run-Stage5FpsDiagnostic.ps1') `
    -ProjectDirectory $ProjectDirectory -PdsShell $PdsShell
