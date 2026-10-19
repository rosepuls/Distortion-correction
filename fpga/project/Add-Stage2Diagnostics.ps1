param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage2_ddr3_720p60')
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath $ProjectDirectory).Path
$top = Join-Path $projectRoot 'source\rtl\HDMI_IN_DDR3_HDMI_OUT_top.v'
$frame = Join-Path $projectRoot 'source\rtl\fram_buf.v'
$writer = Join-Path $projectRoot 'source\rtl\wr_buf.v'
$reader = Join-Path $projectRoot 'source\rtl\rd_buf.v'
$fdc = Join-Path $projectRoot 'HDMI_IN_DDR3_HDMI_OUT_top.fdc'
foreach ($file in @($top, $frame, $writer, $reader, $fdc)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing source: $file" }
}

# Patch ASCII RTL tokens without changing the vendor files' non-UTF8 comments.
$encoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
function Replace-Unique {
    param([string]$File, [string]$Pattern, [string]$Replacement)
    $body = $encoding.GetString([System.IO.File]::ReadAllBytes($File))
    $count = [regex]::Matches($body, $Pattern).Count
    if ($count -ne 1) { throw "Expected one match, found $count in $File`: $Pattern" }
    $body = [regex]::Replace($body, $Pattern, $Replacement)
    [System.IO.File]::WriteAllBytes($File, $encoding.GetBytes($body))
}

Replace-Unique $writer '(output\s+frame_wirq)(\s*\n\);)' ('${1},' + "`r`n    output                        debug_write_request_overlap" + '${2}')
Replace-Unique $writer '(assign\s+frame_wirq\s*=\s*wirq_en\s*&&\s*rd_fsync_3d\s*;)' ('${1}' + "`r`n    assign debug_write_request_overlap = rd_trig && !ddr_wrdy;")
Replace-Unique $reader '(input\s+ddr_rdata_en)(\s*\n\);)' ('${1},' + "`r`n    output                        debug_read_request_overlap" + '${2}')
Replace-Unique $reader '(assign\s+ddr_rreq\s*=\s*wr_trig\s*;)' ('${1}' + "`r`n    assign debug_read_request_overlap = wr_trig && !ddr_rrdy;")

Replace-Unique $frame '(output reg\s+init_done=0,)' ('${1}' + "`r`n    output                        debug_write_request_overlap,`r`n    output                        debug_read_request_overlap,")
Replace-Unique $frame '(\.frame_wirq\s*\(\s*frame_wirq\s*\))' (".debug_write_request_overlap (debug_write_request_overlap),`r`n        " + '${1}')
Replace-Unique $frame '(\.ddr_rdata_en\s*\(\s*read_en\s*\))' ('${1},' + "`r`n        .debug_read_request_overlap (debug_read_request_overlap)")

Replace-Unique $top '(output reg\s+heart_beat_led\s*,)' ('${1}' + "`r`n    output [7:4]                     debug_led                 ,")
Replace-Unique $top '(wire\s*\[15:0\]\s+o_rgb565\s*;)' ('${1}' + "`r`n    wire debug_write_request_overlap;`r`n    wire debug_read_request_overlap;")
Replace-Unique $top '(\.init_done\s*\(\s*init_done\s*\),)' ('${1}' + "`r`n        .debug_write_request_overlap (debug_write_request_overlap),`r`n        .debug_read_request_overlap  (debug_read_request_overlap),")

$monitor = @'
// Diagnostic LEDs: 4/5 latch a line request arriving while the DDR command
// sequencer is busy; 6 latches DDR initialization dropping after lock;
// 7 latches an HDMI input frame with an active-pixel count other than 720p.
reg [27:0] debug_arm_count = 28'd0;
reg debug_armed = 1'b0;
reg debug_seen_ddr_init = 1'b0;
reg debug_write_overlap_seen = 1'b0;
reg debug_read_overlap_seen = 1'b0;
reg debug_ddr_drop_seen = 1'b0;

always @(posedge core_clk) begin
    if (!rst_in) begin
        debug_arm_count <= 28'd0;
        debug_armed <= 1'b0;
        debug_seen_ddr_init <= 1'b0;
        debug_write_overlap_seen <= 1'b0;
        debug_read_overlap_seen <= 1'b0;
        debug_ddr_drop_seen <= 1'b0;
    end else begin
        if (ddr_init_done) begin
            debug_seen_ddr_init <= 1'b1;
            if (!debug_armed) begin
                if (debug_arm_count == 28'd250000000)
                    debug_armed <= 1'b1;
                else
                    debug_arm_count <= debug_arm_count + 28'd1;
            end
        end else begin
            debug_arm_count <= 28'd0;
            debug_armed <= 1'b0;
            if (debug_seen_ddr_init)
                debug_ddr_drop_seen <= 1'b1;
        end
        if (debug_armed && debug_write_request_overlap)
            debug_write_overlap_seen <= 1'b1;
        if (debug_armed && debug_read_request_overlap)
            debug_read_overlap_seen <= 1'b1;
    end
end

reg debug_vs_d = 1'b0;
reg [19:0] debug_active_pixels = 20'd0;
reg [1:0] debug_frames_seen = 2'd0;
reg debug_input_bad_seen = 1'b0;
always @(posedge pixclk_in) begin
    if (!rst_in) begin
        debug_vs_d <= 1'b0;
        debug_active_pixels <= 20'd0;
        debug_frames_seen <= 2'd0;
        debug_input_bad_seen <= 1'b0;
    end else begin
        debug_vs_d <= vs_in;
        if (vs_in && !debug_vs_d) begin
            if (debug_frames_seen == 2'd2 && debug_active_pixels != 20'd921600)
                debug_input_bad_seen <= 1'b1;
            if (debug_frames_seen != 2'd2)
                debug_frames_seen <= debug_frames_seen + 2'd1;
            debug_active_pixels <= 20'd0;
        end else if (de_in && debug_active_pixels != 20'hfffff) begin
            debug_active_pixels <= debug_active_pixels + 20'd1;
        end
    end
end
assign debug_led[4] = debug_write_overlap_seen;
assign debug_led[5] = debug_read_overlap_seen;
assign debug_led[6] = debug_ddr_drop_seen;
assign debug_led[7] = debug_input_bad_seen;

'@
Replace-Unique $top '(?m)^(\s*always@\(posedge core_clk\) begin)' ($monitor + '${1}')

$pins = @{ 4 = 'A17'; 5 = 'A18'; 6 = 'C17'; 7 = 'B17' }
$fdcBody = $encoding.GetString([System.IO.File]::ReadAllBytes($fdc))
if ($fdcBody.Contains('p:debug_led[4]')) { throw 'Diagnostic LED pins are already present.' }
foreach ($index in 4..7) {
    $pin = $pins[$index]
    $fdcBody += "`r`n# LED$index - sticky diagnostic flag`r`n"
    $fdcBody += "define_attribute {p:debug_led[$index]} {PAP_IO_DIRECTION} {OUTPUT}`r`n"
    $fdcBody += "define_attribute {p:debug_led[$index]} {PAP_IO_LOC} {$pin}`r`n"
    $fdcBody += "define_attribute {p:debug_led[$index]} {PAP_IO_VCCIO} {3.3}`r`n"
    $fdcBody += "define_attribute {p:debug_led[$index]} {PAP_IO_STANDARD} {LVCMOS33}`r`n"
    $fdcBody += "define_attribute {p:debug_led[$index]} {PAP_IO_DRIVE} {8}`r`n"
    $fdcBody += "define_attribute {p:debug_led[$index]} {PAP_IO_NONE} {TRUE}`r`n"
    $fdcBody += "define_attribute {p:debug_led[$index]} {PAP_IO_SLEW} {SLOW}`r`n"
}
[System.IO.File]::WriteAllBytes($fdc, $encoding.GetBytes($fdcBody))
Write-Host "Added LED4-7 diagnostics to $projectRoot"
