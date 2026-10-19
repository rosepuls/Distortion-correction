param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage2_ddr3_720p60_frame_slots')
)

$ErrorActionPreference = 'Stop'
$projectDir = [System.IO.Path]::GetFullPath($ProjectDirectory)
if (Test-Path -LiteralPath $projectDir) {
    throw "Existing local project will not be overwritten: $projectDir"
}
& (Join-Path $PSScriptRoot 'New-Stage2LastLineProject.ps1') -ProjectDirectory $projectDir

# Only ASCII tokens are modified in the mixed-encoding vendor files.
$encoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
function Replace-One {
    param([string]$File, [string]$Pattern, [string]$Replacement)
    $source = $encoding.GetString([System.IO.File]::ReadAllBytes($File))
    $matches = [regex]::Matches($source, $Pattern)
    if ($matches.Count -ne 1) {
        throw "Expected one match, found $($matches.Count): $Pattern in $File"
    }
    [System.IO.File]::WriteAllBytes($File, $encoding.GetBytes(
        [regex]::Replace($source, $Pattern, $Replacement)))
}

$rtl = Join-Path $projectDir 'source\rtl'
$writer = Join-Path $rtl 'wr_buf.v'
$reader = Join-Path $rtl 'rd_buf.v'
$frame = Join-Path $rtl 'fram_buf.v'
$top = Join-Path $rtl 'HDMI_IN_DDR3_HDMI_OUT_top.v'
$pds = Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT.pds'
$fdc = Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT_top.fdc'

# Writer: the DDR-domain VS closes the prior frame. A frame is complete only
# when all 720 line commands finished and no write request is pending.
Replace-One $writer 'output\s+frame_wirq\s*\r?\n\);' @'
output                        frame_wirq,
    input  [1:0]                 frame_slot,
    output                        frame_end,
    output                        frame_complete,
    output                        write_busy_line
);
'@
Replace-One $writer '(?s)    reg \[FRAME_CNT_WIDTH - 1''b1 :0\] rd_frame_cnt=1;.*?    reg \[LINE_ADDR_WIDTH - 1''b1 :0\] rd_cnt;' "    reg [LINE_ADDR_WIDTH - 1'b1 :0] rd_cnt;"
Replace-One $writer 'assign ddr_waddr = \{rd_frame_cnt\[0\],rd_cnt\} \+ ADDR_OFFSET;' "assign ddr_waddr = {{(ADDR_WIDTH-LINE_ADDR_WIDTH-2){1'b0}},frame_slot,rd_cnt} + ADDR_OFFSET;"
Replace-One $writer 'assign frame_wcnt = rd_frame_cnt;' @'
assign frame_wcnt = frame_slot;
    assign frame_end = ~rd_fsync_3d && rd_fsync_2d;
    assign frame_complete = (rd_cnt == V_NUM*DDR_ADDR_OFFSET) && ddr_wrdy && !ddr_wreq;
    assign write_busy_line = rd_trig && !ddr_wrdy;
'@

# Reader: VS selects the published slot before its first-line prefetch. The
# output side never reads the writer's in-progress slot.
Replace-One $reader 'input\s+init_done,\s*\r?\n' @'
input                         init_done,
    input  [1:0]                 frame_slot,
    input                        display_valid,
    output                       frame_start,
    output                       frame_complete,
    output                       read_busy_line,

'@
Replace-One $reader '(?s)    reg \[FRAME_CNT_WIDTH - 1''b1 :0\] wr_frame_cnt=0;.*?    reg \[LINE_ADDR_WIDTH - 1''b1 :0\] wr_cnt;' "    reg [LINE_ADDR_WIDTH - 1'b1 :0] wr_cnt;"
Replace-One $reader 'assign ddr_rreq = wr_trig;' @'
assign ddr_rreq = wr_trig && display_valid;
    assign frame_start = wr_rst;
    assign frame_complete = (wr_cnt == V_NUM*DDR_ADDR_OFFSET) && ddr_rrdy && !wr_trig;
    assign read_busy_line = wr_trig && display_valid && !ddr_rrdy;
'@
Replace-One $reader 'assign ddr_raddr = \{wr_frame_cnt\[0\],wr_cnt\} \+ ADDR_OFFSET;' "assign ddr_raddr = {{(ADDR_WIDTH-LINE_ADDR_WIDTH-2){1'b0}},frame_slot,wr_cnt} + ADDR_OFFSET;"
Replace-One $reader 'assign vout_data = read_data;' @'
reg display_valid_1d, display_valid_2d;
    always @(posedge vout_clk) begin
        display_valid_1d <= display_valid;
        display_valid_2d <= display_valid_1d;
    end
    assign vout_data = display_valid_2d ? read_data : {PIX_WIDTH{1'b0}};
'@

# The frame buffer owns the single manager and exposes sticky error summaries
# to the board LEDs. Full counters and sequences are kept for later telemetry.
Replace-One $frame 'output reg\s+init_done=0,' @'
output reg                    init_done=0,
    output [3:0]                  frame_error_led,
'@
Replace-One $frame 'wire\s+ddr_wr_bac;' @'
wire                        ddr_wr_bac;
    wire [1:0] write_slot, display_slot;
    wire display_valid;
    wire input_frame_end, input_frame_complete;
    wire output_frame_start, output_frame_complete;
    wire write_busy_line, read_busy_line;
    wire [31:0] published_sequence, displayed_sequence;
    wire [15:0] incomplete_input_count, repeated_output_count;
    wire [15:0] incomplete_output_count, write_busy_count, read_busy_count;

    frame_slot_manager frame_slot_manager (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .input_vsync(input_frame_end), .input_complete(input_frame_complete),
        .output_vsync(output_frame_start), .output_complete(output_frame_complete),
        .write_busy_line(write_busy_line), .read_busy_line(read_busy_line),
        .write_slot(write_slot), .display_slot(display_slot),
        .display_valid(display_valid),
        .published_sequence(published_sequence),
        .displayed_sequence(displayed_sequence),
        .incomplete_input_count(incomplete_input_count),
        .repeated_output_count(repeated_output_count),
        .incomplete_output_count(incomplete_output_count),
        .write_busy_count(write_busy_count), .read_busy_count(read_busy_count)
    );
    assign frame_error_led = {
        (read_busy_count != 16'd0), (write_busy_count != 16'd0),
        (incomplete_output_count != 16'd0), (incomplete_input_count != 16'd0)
    };
'@
Replace-One $frame '\.frame_wirq\s*\(\s*frame_wirq\s*\)' @'
.frame_wirq       (  frame_wirq       ),
        .frame_slot       (  write_slot      ),
        .frame_end        (  input_frame_end ),
        .frame_complete   (  input_frame_complete ),
        .write_busy_line  (  write_busy_line )
'@
Replace-One $frame '\.init_done\s*\(\s*init_done\s*\),//input\s+init_done,' @'
.init_done       (  init_done         ),//input init_done,
        .frame_slot      (  display_slot      ),
        .display_valid   (  display_valid     ),
        .frame_start     (  output_frame_start ),
        .frame_complete  (  output_frame_complete ),
        .read_busy_line  (  read_busy_line    ),
'@

# Visible indicators are sticky error summaries. Existing LED0-3 retain
# their original assignments and pin constraints.
Replace-One $top 'output\s+ddr_init_done\s*,' @'
output                               ddr_init_done             ,
    output [3:0]                       frame_error_led          ,
'@
Replace-One $top '\.init_done\s*\(\s*init_done\s*\),//output reg\s+init_done,' @'
.init_done      (  init_done            ),//output reg init_done,
        .frame_error_led ( frame_error_led ),
'@

$sourceManager = Join-Path $PSScriptRoot '..\rtl\memory\frame_slot_manager.v'
Copy-Item -LiteralPath $sourceManager -Destination (Join-Path $rtl 'frame_slot_manager.v')
# Insert next to the frame buffer source with the required PDS timestamp.
Replace-One $pds '(\(_file "source/rtl/fram_buf\.v"\s*\(_format verilog\)\s*\(_timespec "[^"]+"\)\s*\))' @'
${1}
                (_file "source/rtl/frame_slot_manager.v"
                    (_format verilog)
                    (_timespec "2026-10-19T00:00:00")
                )
'@

$pins = @('A17', 'A18', 'C17', 'B17')
$pinText = ''
for ($i = 0; $i -lt 4; $i++) {
    $pinText += "`r`ndefine_attribute {p:frame_error_led[$i]} {PAP_IO_DIRECTION} {OUTPUT}"
    $pinText += "`r`ndefine_attribute {p:frame_error_led[$i]} {PAP_IO_LOC} {$($pins[$i])}"
    $pinText += "`r`ndefine_attribute {p:frame_error_led[$i]} {PAP_IO_VCCIO} {3.3}"
    $pinText += "`r`ndefine_attribute {p:frame_error_led[$i]} {PAP_IO_STANDARD} {LVCMOS33}"
    $pinText += "`r`ndefine_attribute {p:frame_error_led[$i]} {PAP_IO_DRIVE} {8}"
}
Add-Content -LiteralPath $fdc -Value $pinText

Write-Host "Created RGB565 frame-slot PDS project: $(Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT.pds')"
