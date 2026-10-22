param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage3_frame_pool_test')
)

$ErrorActionPreference = 'Stop'
$projectDirectory = [System.IO.Path]::GetFullPath($ProjectDirectory)
$stableDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'stage2_ddr3_720p60_rgbx8888'))
if ($projectDirectory.TrimEnd('\') -ieq $stableDirectory.TrimEnd('\')) {
    throw 'Refusing to patch the accepted Stage 2 project.'
}
$latin1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')

function Read-ExactBytes([string]$path) {
    return $latin1.GetString([System.IO.File]::ReadAllBytes($path))
}
function Write-ExactBytes([string]$path, [string]$content) {
    [System.IO.File]::WriteAllBytes($path, $latin1.GetBytes($content))
}
function Replace-Once([string]$content, [string]$old, [string]$new, [string]$label) {
    $first = $content.IndexOf($old, [System.StringComparison]::Ordinal)
    if ($first -lt 0 -or $content.IndexOf($old, $first + $old.Length, [System.StringComparison]::Ordinal) -ge 0) {
        throw "Expected exactly one $label anchor."
    }
    return $content.Substring(0, $first) + $new + $content.Substring($first + $old.Length)
}

$rtlDir = Join-Path $projectDirectory 'source\rtl'
$wrPath = Join-Path $rtlDir 'wr_buf.v'
$framPath = Join-Path $rtlDir 'fram_buf.v'
$topPath = Join-Path $rtlDir 'HDMI_IN_DDR3_HDMI_OUT_top.v'
$preWr = Read-ExactBytes $wrPath
$preFram = Read-ExactBytes $framPath
$preTop = Read-ExactBytes $topPath
if ($preWr.Contains('write_source_busy') -or
    $preFram.Contains('capture_frame_admission admission') -or
    $preTop.Contains('.axi_wusero_id (  axi_wusero_id')) {
    throw 'Stage 3 capture integration is already applied; refusing duplicate edits.'
}
$wr = Read-ExactBytes $wrPath
$wr = Replace-Once $wr '    output                        write_busy_line' '    output                        write_busy_line,`r`n    output                        write_source_busy' 'wr_buf port'
$wr = $wr.Replace('`r`n', "`r`n")
$wr = Replace-Once $wr '    assign write_busy_line = rd_trig && !ddr_wrdy;' @'
    assign write_busy_line = rd_trig && !ddr_wrdy;
    // DDR-domain pipeline stages which can still launch a line write.
    // Admission waits eight clocks after VS for the earlier CDC stage.
    assign write_source_busy = rd_pulse_2d || rd_pulse_3d || rd_trig ||
                               ddr_wr_req || !ddr_wrdy;
'@ 'wr_buf source busy'
$wr = $wr.Replace("`n", "`r`n").Replace("`r`r`n", "`r`n")
Write-ExactBytes $wrPath $wr

$fram = Read-ExactBytes $framPath
$fram = Replace-Once $fram '    input                         axi_wlast      ,' "    input                         axi_wlast      ,`r`n    input  [3:0]                  axi_wusero_id  ," 'fram_buf completion ID port'
$start = '    wire [1:0] write_slot, display_slot;'
$end = '    wr_buf #('
$startAt = $fram.IndexOf($start, [System.StringComparison]::Ordinal)
$endAt = $fram.IndexOf($end, $startAt, [System.StringComparison]::Ordinal)
if ($startAt -lt 0 -or $endAt -lt 0 -or $fram.IndexOf($start, $startAt + $start.Length, [System.StringComparison]::Ordinal) -ge 0) {
    throw 'Could not locate unique fram_buf ownership block.'
}
$newOwnership = @'
    wire [1:0] write_slot, display_slot;
    wire display_valid;
    wire capture_begin_ready, capture_begin, capture_publish, capture_abort;
    wire capture_ready_valid, allow_capture, capture_write_idle;
    wire gated_wr_en, frame_admitted;
    wire write_source_busy, write_protocol_fault;
    wire [15:0] capture_outstanding, write_protocol_error_count;
    wire [15:0] capture_abort_count, dropped_ready_count, display_empty_count;
    wire [15:0] drain_wait_cycles;
    wire input_frame_end, input_frame_complete;
    wire output_frame_start, output_frame_complete;
    wire write_busy_line, read_busy_line;
    wire [31:0] published_sequence, displayed_sequence;
    reg [15:0] incomplete_output_count, write_busy_count, read_busy_count;
    reg seen_output_vsync;

    ddr_write_drain_tracker write_tracker (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .awvalid(axi_awvalid), .awready(axi_awready), .awid(axi_awid),
        .wready(axi_wready),
        .wusero_last(axi_wlast), .wusero_id(axi_wusero_id),
        .capture_source_busy(write_source_busy), .copy_source_busy(1'b0),
        .capture_write_idle(capture_write_idle), .copy_write_idle(),
        .capture_outstanding(capture_outstanding), .copy_outstanding(),
        .protocol_error_count(write_protocol_error_count),
        .protocol_fault(write_protocol_fault)
    );

    capture_frame_admission admission (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .frame_end(input_frame_end), .frame_complete(input_frame_complete),
        .write_idle(capture_write_idle),
        .capture_begin_ready(capture_begin_ready),
        .capture_begin(capture_begin),
        .capture_publish(capture_publish), .capture_abort(capture_abort),
        .allow_capture(allow_capture),
        .drain_wait_cycles(drain_wait_cycles)
    );

    capture_pixel_gate pixel_gate (
        .pix_clk(vin_clk), .rstn(ddr_rstn),
        .vs_in(wr_fsync), .de_in(wr_en),
        .allow_capture_ddr(allow_capture),
        .wr_en(gated_wr_en), .frame_admitted(frame_admitted)
    );

    frame_pool_manager capture_pool (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .producer_begin(capture_begin),
        .producer_begin_ready(capture_begin_ready),
        .producer_active(), .producer_slot(write_slot),
        .producer_publish(capture_publish), .producer_abort(capture_abort),
        .consumer_take(output_frame_start && capture_ready_valid &&
                       (!display_valid || output_frame_complete)),
        .consumer_active(display_valid), .consumer_slot(display_slot),
        .consumer_sequence(displayed_sequence),
        .consumer_release(1'b0),
        .ready_valid(capture_ready_valid),
        .publish_sequence(published_sequence),
        .producer_abort_count(capture_abort_count),
        .dropped_ready_count(dropped_ready_count),
        .consumer_empty_count(display_empty_count)
    );

    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            seen_output_vsync <= 1'b0;
            incomplete_output_count <= 16'd0;
            write_busy_count <= 16'd0;
            read_busy_count <= 16'd0;
        end else begin
            if (output_frame_start)
                seen_output_vsync <= 1'b1;
            if (output_frame_start && seen_output_vsync && display_valid &&
                !output_frame_complete && incomplete_output_count != 16'hffff)
                incomplete_output_count <= incomplete_output_count + 1'b1;
            if (write_busy_line && write_busy_count != 16'hffff)
                write_busy_count <= write_busy_count + 1'b1;
            if (read_busy_line && read_busy_count != 16'hffff)
                read_busy_count <= read_busy_count + 1'b1;
        end
    end
    assign frame_error_led = {
        write_protocol_fault || (read_busy_count != 16'd0),
        (write_busy_count != 16'd0),
        (incomplete_output_count != 16'd0), (capture_abort_count != 16'd0)
    };

'@
$newOwnership = $newOwnership.Replace("`n", "`r`n")
$fram = $fram.Substring(0, $startAt) + $newOwnership + $fram.Substring($endAt)
$fram = Replace-Once $fram '.wr_en            (  wr_en            )' '.wr_en            (  gated_wr_en     )' 'gated pixel write'
$fram = Replace-Once $fram '.write_busy_line  (  write_busy_line )' ".write_busy_line  (  write_busy_line ),`r`n        .write_source_busy(  write_source_busy )" 'wr_buf busy output'
Write-ExactBytes $framPath $fram

$top = Read-ExactBytes $topPath
$top = Replace-Once $top '.axi_wlast      (  axi_wusero_last      ),' ".axi_wlast      (  axi_wusero_last      ),`r`n        .axi_wusero_id (  axi_wusero_id        )," 'fram_buf ID hookup'
$top = Replace-Once $top '.axi_wusero_id             (                   ),' '.axi_wusero_id             (axi_wusero_id      ),' 'DDR IP ID hookup'
Write-ExactBytes $topPath $top
Write-Host "Stage 3 capture integration applied: $projectDirectory"
