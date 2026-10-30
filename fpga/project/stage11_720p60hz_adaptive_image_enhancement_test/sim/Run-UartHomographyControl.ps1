param([string]$VivadoHome = 'D:\Xilinx\Vivado\2020.2')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$work = Join-Path $PSScriptRoot '.work\uart-homography-control'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    $sources = @(
        (Join-Path $projectRoot 'source\rtl\uart\uart_rx_8n1.sv'),
        (Join-Path $projectRoot 'source\rtl\uart\uart_tx_8n1.sv'),
        (Join-Path $projectRoot 'source\rtl\uart\stage8_pose_packet.sv'),
        (Join-Path $projectRoot 'source\rtl\uart\stage8_pose_response_tx.sv'),
        (Join-Path $projectRoot 'source\rtl\uart\stage8_uart_homography_control.sv'),
        (Join-Path $projectRoot 'source\rtl\correction\homography_parameter_bank.sv'),
        (Join-Path $PSScriptRoot 'uart_homography_control_tb.sv')
    )
    & (Join-Path $VivadoHome 'bin\xvlog.bat') --sv --work work --log xvlog.log $sources
    if ($LASTEXITCODE -ne 0) { throw 'UART homography control xvlog failed.' }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.uart_homography_control_tb `
        -s uart_homography_control_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'UART homography control xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') uart_homography_control_sim `
        -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath xsim.log `
        -Pattern 'PASS: UART homography ACK/NACK, active coefficients, and frame-boundary update' -Quiet)) {
        throw 'UART homography control simulation failed.'
    }
} finally { Pop-Location }
