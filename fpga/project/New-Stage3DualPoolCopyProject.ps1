param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage3_frame_pool_gate_fix'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage3_dual_pool_copy')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourceProject -PathType Container)) {
    throw "Accepted Stage 3 source project not found: $SourceProject"
}
if (Test-Path -LiteralPath $ProjectDirectory) {
    throw "Refusing to overwrite existing project directory: $ProjectDirectory"
}

$sourceProjectPath = (Resolve-Path -LiteralPath $SourceProject).Path
$projectsRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$projectPath = [System.IO.Path]::GetFullPath($ProjectDirectory)
$sourcePrefix = $sourceProjectPath.TrimEnd('\') + '\'
if ($projectPath.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The destination must not be inside the source project.'
}
if ((Split-Path -Parent $projectPath) -ne $projectsRoot) {
    throw "The destination must be a direct child of $projectsRoot"
}

$excludedDirectories = @(
    'compile', 'synthesize', 'device_map', 'place_route', 'report_timing',
    'generate_bitstream', 'generate_netlist', 'constraint_check',
    'report_power', 'log', 'logbackup'
)
$excludedFiles = @('*.log', '*.csv', '*.sbit', '*.smsk', '*.bgr', '*.vcd')

New-Item -ItemType Directory -Path $ProjectDirectory | Out-Null
try {
    $sourceFiles = Get-ChildItem -LiteralPath $sourceProjectPath -File -Force -Recurse |
        Where-Object {
            $candidate = $_
            $relative = $candidate.FullName.Substring($sourcePrefix.Length)
            $components = $relative -split '[\\/]'
            $nameExcluded = $false
            foreach ($pattern in $excludedFiles) {
                if ($candidate.Name -like $pattern) {
                    $nameExcluded = $true
                    break
                }
            }
            -not ($components | Where-Object { $excludedDirectories -contains $_ }) -and
            -not $nameExcluded
        }

    foreach ($sourceFile in $sourceFiles) {
        $relativePath = $sourceFile.FullName.Substring($sourcePrefix.Length)
        $destinationPath = Join-Path $projectPath $relativePath
        $destinationParent = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath
    }

    $sharedMemoryModules = @(
        'frame_pool_manager.v',
        'frame_pool_address.v',
        'frame_pipeline_ownership.v',
        'ddr_read_burst_arbiter.v',
        'display_read_adapter.v',
        'ddr_write_burst_arbiter.v',
        'frame_copy_engine.v',
        'capture_frame_admission.v',
        'ddr_write_drain_tracker.v'
    )
    foreach ($module in $sharedMemoryModules) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot (Join-Path 'fpga/rtl/memory' $module)) `
            -Destination (Join-Path $projectPath (Join-Path 'source/rtl' $module)) -Force
    }

    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'fpga/sim/frame_pipeline_smoke_top.v') `
        -Destination (Join-Path $projectPath 'source/rtl/frame_pipeline_smoke_top.v') -Force

    # Add the actual Pango write-data-valid qualifier to the drain tracker.
    $framBufPath = Join-Path $projectPath 'source/rtl/fram_buf.v'
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $framBufText = $latin1.GetString([System.IO.File]::ReadAllBytes($framBufPath))
    $oldTrackerConnection = '.wusero_last(axi_wlast), .wusero_id(axi_wusero_id),'
    $newTrackerConnection = ".wready(axi_wready),`r`n        .wusero_last(axi_wlast), .wusero_id(axi_wusero_id),"
    if (-not $framBufText.Contains($oldTrackerConnection)) {
        throw 'The Stage 3 fram_buf write-tracker connection was not found.'
    }
    $framBufText = $framBufText.Replace($oldTrackerConnection, $newTrackerConnection)

    $framBufText = $framBufText.Replace(
        'wire capture_ready_valid, allow_capture, capture_write_idle;',
        'wire allow_capture, capture_write_idle, display_take_ready;')
    $framBufText = $framBufText.Replace(
        'wire [15:0] capture_abort_count, dropped_ready_count, display_empty_count;',
        'wire [15:0] capture_dropped_count, output_dropped_count;')
    $framBufText = $framBufText.Replace(
        'wire [31:0] published_sequence, displayed_sequence;',
        "wire [31:0] displayed_sequence, copy_input_sequence;`r`n    wire [31:0] copied_count, copy_error_count;`r`n    wire copy_active;")

    $oldPoolStart = $framBufText.IndexOf('    frame_pool_manager capture_pool (')
    $oldPoolEnd = $framBufText.IndexOf(
        '    always @(posedge ddr_clk or negedge ddr_rstn) begin',
        $oldPoolStart)
    if ($oldPoolStart -lt 0 -or $oldPoolEnd -lt 0) {
        throw 'The Stage 3 single capture-pool instance was not found.'
    }
    $ownershipBlock = @'
    frame_pipeline_ownership ownership (
        .clk(ddr_clk), .rstn(ddr_rstn),
        .capture_begin(capture_begin),
        .capture_begin_ready(capture_begin_ready),
        .capture_begin_slot(),
        .capture_active(), .capture_slot(write_slot),
        .capture_publish(capture_publish), .capture_abort(capture_abort),
        .display_take(output_frame_start && display_take_ready &&
                      (!display_valid || output_frame_complete)),
        .display_take_ready(display_take_ready),
        .display_active(display_valid), .display_slot(display_slot),
        .display_sequence(displayed_sequence),
        .display_release(1'b0),
        .copy_start(), .copy_start_ready(1'b0),
        .copy_input_slot(), .copy_output_slot(),
        .copy_input_sequence(copy_input_sequence),
        .copy_done(1'b0), .copy_error(1'b0), .copy_active(copy_active),
        .copied_count(copied_count), .copy_error_count(copy_error_count),
        .capture_dropped_ready_count(capture_dropped_count),
        .output_dropped_ready_count(output_dropped_count)
    );

'@
    $ownershipBlock = $ownershipBlock.Replace("`n", "`r`n")
    $framBufText = $framBufText.Substring(0, $oldPoolStart) +
        $ownershipBlock + $framBufText.Substring($oldPoolEnd)

    function Replace-Required([string]$text, [string]$old, [string]$new) {
        if (-not $text.Contains($old)) { throw "Integration anchor not found: $old" }
        return $text.Replace($old, $new)
    }
    $framBufText = Replace-Required $framBufText 'wire                        read_ready  = 1''b1;' `
        "wire [9:0] display_consumed_gray;`r`n    wire display_client_valid, display_client_reserve, display_client_ready;`r`n    wire display_client_rvalid, display_client_rlast;`r`n    wire [27:0] display_client_addr;`r`n    wire [3:0] display_client_len;`r`n    wire [255:0] display_client_rdata;`r`n    wire display_line_error, display_frame_blocked;`r`n    wire [15:0] display_read_error_count, read_arbiter_error_count;`r`n    wire [9:0] display_received_beats;"
    $framBufText = Replace-Required $framBufText '.read_busy_line  (  read_busy_line    ),' `
        ".read_busy_line  (  read_busy_line    ),`r`n        .consumed_gray  (  display_consumed_gray ),"
    $framBufText = Replace-Required $framBufText '.ADDR_OFFSET      (  32''h0000_0000    ),' `
        '.ADDR_OFFSET      (  32''h00c0_0000    ),'
    $displayBlock = [System.IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot 'templates/stage3-display-read-block.vfrag'),
        [System.Text.Encoding]::ASCII)
    $framBufText = Replace-Required $framBufText '    wr_rd_ctrl_top#(' `
        ($displayBlock + '    wr_rd_ctrl_top#(')
    $readPorts = @{
        '.rd_cmd_en        (  rd_cmd_en        ),' = '.rd_cmd_en        (  1''b0             ),'
        '.rd_cmd_addr      (  rd_cmd_addr      ),' = '.rd_cmd_addr      (  {CTRL_ADDR_WIDTH{1''b0}} ),'
        '.rd_cmd_len       (  rd_cmd_len       ),' = '.rd_cmd_len       (  32''d0            ),'
        '.rd_cmd_ready     (  rd_cmd_ready     ),' = '.rd_cmd_ready     (                   ),'
        '.rd_cmd_done      (  rd_cmd_done      ),' = '.rd_cmd_done      (                   ),'
        '.read_ready       (  read_ready       ),' = '.read_ready       (  1''b0             ),'
        '.read_rdata       (  read_rdata       ),' = '.read_rdata       (                   ),'
        '.read_en          (  read_en          ),' = '.read_en          (                   ),'
        '.axi_araddr       (  axi_araddr       ),' = '.axi_araddr       (                   ),'
        '.axi_arid         (  axi_arid         ),' = '.axi_arid         (                   ),'
        '.axi_arlen        (  axi_arlen        ),' = '.axi_arlen        (                   ),'
        '.axi_arsize       (  axi_arsize       ),' = '.axi_arsize       (                   ),'
        '.axi_arburst      (  axi_arburst      ),' = '.axi_arburst      (                   ),'
        '.axi_arvalid      (  axi_arvalid      ),' = '.axi_arvalid      (                   ),'
        '.axi_arready      (  axi_arready      ),' = '.axi_arready      (  1''b0             ),'
        '.axi_rready       (  axi_rready       ),' = '.axi_rready       (                   ),'
        '.axi_rdata        (  axi_rdata        ),' = '.axi_rdata        (  {MEM_DQ_WIDTH*8{1''b0}} ),'
        '.axi_rvalid       (  axi_rvalid       ),' = '.axi_rvalid       (  1''b0             ),'
        '.axi_rlast        (  axi_rlast        ),' = '.axi_rlast        (  1''b0             ),'
        '.axi_rid          (  axi_rid          ),' = '.axi_rid          (  4''d0             ),'
    }
    foreach ($old in $readPorts.Keys) {
        $framBufText = Replace-Required $framBufText $old $readPorts[$old]
    }

    $copyWires = [System.IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot 'templates/stage3-copy-write-wires.vfrag'),
        [System.Text.Encoding]::ASCII)
    $framBufText = Replace-Required $framBufText `
        '    wire                        ddr_wreq;' `
        ($copyWires + '    wire                        ddr_wreq;')
    $copyBlock = [System.IO.File]::ReadAllText(
        (Join-Path $PSScriptRoot 'templates/stage3-copy-write-block.vfrag'),
        [System.Text.Encoding]::ASCII)
    $framBufText = Replace-Required $framBufText `
        '    ddr_write_drain_tracker write_tracker (' `
        ($copyBlock + '    ddr_write_drain_tracker write_tracker (')
    $framBufText = Replace-Required $framBufText `
        '.capture_write_idle(capture_write_idle), .copy_write_idle(),' `
        '.capture_write_idle(tracked_capture_write_idle), .copy_write_idle(),'
    $framBufText = Replace-Required $framBufText `
        ".capture_source_busy(write_source_busy), .copy_source_busy(1'b0)," `
        '.capture_source_busy(write_source_busy), .copy_source_busy(copy_source_busy),'
    $framBufText = Replace-Required $framBufText `
        '.capture_outstanding(capture_outstanding), .copy_outstanding(),' `
        '.capture_outstanding(capture_outstanding), .copy_outstanding(copy_outstanding),'
    $framBufText = Replace-Required $framBufText `
        ".copy_start(), .copy_start_ready(1'b0)," `
        '.copy_start(copy_start), .copy_start_ready(copy_start_ready),'
    $framBufText = Replace-Required $framBufText `
        '.copy_input_slot(), .copy_output_slot(),' `
        '.copy_input_slot(copy_input_slot), .copy_output_slot(copy_output_slot),'
    $framBufText = Replace-Required $framBufText `
        ".copy_done(1'b0), .copy_error(1'b0), .copy_active(copy_active)," `
        '.copy_done(copy_done), .copy_error(copy_error), .copy_active(copy_active),'
    $framBufText = Replace-Required $framBufText `
        '.display_valid   (  display_valid     ),' `
        '.display_valid   (  display_pipe_ok   ),'
    $framBufText = Replace-Required $framBufText `
        ".c1_valid(1'b0), .c1_addr(28'd0), .c1_len(4'd15),`r`n        .c1_reserve(1'b0), .c1_ready(), .c1_rvalid(),`r`n        .c1_rdata(), .c1_rlast()," `
        ".c1_valid(copy_read_valid), .c1_addr(copy_read_addr),`r`n        .c1_len(copy_read_len), .c1_reserve(copy_read_reserve),`r`n        .c1_ready(copy_read_ready), .c1_rvalid(copy_read_rvalid),`r`n        .c1_rdata(copy_read_rdata), .c1_rlast(copy_read_rlast),"
    $writePorts = @{
        '.axi_awaddr       (  axi_awaddr       ),' = '.axi_awaddr       (  capture_axi_awaddr ),'
        '.axi_awid         (  axi_awid         ),' = '.axi_awid         (  capture_axi_awid   ),'
        '.axi_awlen        (  axi_awlen        ),' = '.axi_awlen        (  capture_axi_awlen  ),'
        '.axi_awsize       (  axi_awsize       ),' = '.axi_awsize       (                   ),'
        '.axi_awburst      (  axi_awburst      ),' = '.axi_awburst      (                   ),'
        '.axi_awready      (  axi_awready      ),' = '.axi_awready      (  capture_axi_awready ),'
        '.axi_awvalid      (  axi_awvalid      ),' = '.axi_awvalid      (  capture_axi_awvalid ),'
        '.axi_wdata        (  axi_wdata        ),' = '.axi_wdata        (  capture_axi_wdata  ),'
        '.axi_wstrb        (  axi_wstrb        ),' = '.axi_wstrb        (  capture_axi_wstrb  ),'
        '.axi_wlast        (  axi_wlast        ),' = '.axi_wlast        (  capture_axi_wlast ),'
        '.axi_wvalid       (  axi_wvalid       ),' = '.axi_wvalid       (  capture_axi_wvalid ),'
        '.axi_wready       (  axi_wready       ),' = '.axi_wready       (  capture_axi_wready ),'
    }
    foreach ($old in $writePorts.Keys) {
        $framBufText = Replace-Required $framBufText $old $writePorts[$old]
    }
    $debugDeclarations = @{
        '    wire [15:0] display_read_error_count, read_arbiter_error_count;' =
            "    wire [15:0] display_read_error_count /* synthesis PAP_MARK_DEBUG=`"1`" */;`r`n    wire [15:0] read_arbiter_error_count /* synthesis PAP_MARK_DEBUG=`"1`" */;"
        '    wire [15:0] capture_outstanding, write_protocol_error_count;' =
            "    wire [15:0] capture_outstanding /* synthesis PAP_MARK_DEBUG=`"1`" */;`r`n    wire [15:0] write_protocol_error_count /* synthesis PAP_MARK_DEBUG=`"1`" */;"
        '    wire [15:0] capture_dropped_count, output_dropped_count;' =
            "    wire [15:0] capture_dropped_count /* synthesis PAP_MARK_DEBUG=`"1`" */;`r`n    wire [15:0] output_dropped_count /* synthesis PAP_MARK_DEBUG=`"1`" */;"
        '    wire [31:0] displayed_sequence, copy_input_sequence;' =
            "    wire [31:0] displayed_sequence /* synthesis PAP_MARK_DEBUG=`"1`" */;`r`n    wire [31:0] copy_input_sequence;"
        '    wire [31:0] copied_count, copy_error_count;' =
            "    wire [31:0] copied_count /* synthesis PAP_MARK_DEBUG=`"1`" */;`r`n    wire [31:0] copy_error_count /* synthesis PAP_MARK_DEBUG=`"1`" */;"
        '    reg [15:0] incomplete_output_count, write_busy_count, read_busy_count;' =
            "    reg [15:0] incomplete_output_count /* synthesis PAP_MARK_DEBUG=`"1`" */;`r`n    reg [15:0] write_busy_count, read_busy_count;"
    }
    foreach ($old in $debugDeclarations.Keys) {
        $framBufText = Replace-Required $framBufText $old $debugDeclarations[$old]
    }
    [System.IO.File]::WriteAllBytes($framBufPath, $latin1.GetBytes($framBufText))

    $rdBufPath = Join-Path $projectPath 'source/rtl/rd_buf.v'
    $rdBufText = $latin1.GetString([System.IO.File]::ReadAllBytes($rdBufPath))
    $rdBufText = Replace-Required $rdBufText '    output                       read_busy_line,' `
        "    output                       read_busy_line,`r`n    output reg [9:0]             consumed_gray,"
    $triggerStart = $rdBufText.IndexOf('    reg      wr_en_1d,wr_en_2d,wr_en_3d;')
    if ($triggerStart -lt 0) {
        throw 'The Stage 3 display line-trigger block was not found.'
    }
    $triggerEnd = $rdBufText.IndexOf('    //==========================================================================', $triggerStart)
    if ($triggerEnd -lt 0) {
        throw 'The Stage 3 display line-trigger terminator was not found.'
    }
    $prefetchState = @'
    always @(posedge ddr_clk)
    begin
        wr_fsync_1d <= rd_fsync;
        wr_fsync_2d <= wr_fsync_1d;
        wr_fsync_3d <= wr_fsync_2d;
    end
    assign wr_rst = ~wr_fsync_3d && wr_fsync_2d;
    reg frame_started;
    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn)
            frame_started <= 1'b0;
        else if (wr_rst)
            frame_started <= 1'b1;
    end

'@
    $rdBufText = $rdBufText.Substring(0, $triggerStart) +
        $prefetchState.Replace("`r`n", "`n").Replace("`n", "`r`n") +
        $rdBufText.Substring($triggerEnd)
    $counterReset = [regex]::Match($rdBufText, 'if\(wr_rst\)\s*\r?\n\s*wr_cnt <= 9''d0;').Value
    if (-not $counterReset) { throw 'The display line-address reset was not found.' }
    $rdBufText = Replace-Required $rdBufText $counterReset `
        $counterReset.Replace('if(wr_rst)', 'if(wr_rst || !ddr_rstn)')
    $rdBufText = Replace-Required $rdBufText '    assign ddr_rreq = wr_trig && display_valid;' @'
    // Prefetch as soon as the adapter can accept the next line. Its credit
    // logic limits the 512-beat RAM occupancy, allowing up to three lines
    // of protection against transient DDR arbitration stalls. The line
    // address advances only after all 160 beats have returned.
    assign ddr_rreq = display_valid && frame_started && !wr_rst && !ddr_rdone &&
                      (wr_cnt < V_NUM*DDR_ADDR_OFFSET);
'@
    $rdBufText = Replace-Required $rdBufText '&& ddr_rrdy && !wr_trig;' `
        '&& ddr_rrdy;'
    $rdBufText = Replace-Required $rdBufText `
        'assign read_busy_line = wr_trig && display_valid && !ddr_rrdy;' `
        'assign read_busy_line = ddr_rreq && !ddr_rrdy;'
    $creditBlock = @'
    // One Gray-coded pointer step means one 256-bit DDR beat (8 x 32-bit
    // pixels). Keep it monotonic across video frames; the DDR adapter rebases
    // its producer counter when the physical RAM pointers restart at VS.
    // Register Gray in the SOURCE clock domain. A combinational binary-to-Gray
    // bus can glitch during a binary carry and falsely trip the DDR credit
    // check even though the display RAM still contains unread data.
    wire read_en;
    reg display_valid_1d, display_valid_2d;
    reg [9:0] consumed_beats;
    wire [9:0] consumed_next = consumed_beats + 10'd1;
    always @(posedge vout_clk) begin
        if (!ddr_rstn_2d) begin
            consumed_beats <= 10'd0;
            consumed_gray <= 10'd0;
        end else if (read_en && rd_addr[2:0] == 3'b111) begin
            consumed_beats <= consumed_beats + 1'b1;
            consumed_gray <= (consumed_next >> 1) ^ consumed_next;
        end
    end

'@
    $rdBufText = Replace-Required $rdBufText '    reg [1:0] rd_cnt;' `
        ($creditBlock.Replace("`n", "`r`n") + "`r`n" + '    reg [1:0] rd_cnt;')
    $rdBufText = [regex]::Replace($rdBufText, '(    reg \[1:0\] rd_cnt;\r?\n)    wire\s+read_en;', '$1', 1)
    $rdBufText = [regex]::Replace($rdBufText, '(    assign vout_de = rd_en_2d;\r?\n)    reg display_valid_1d, display_valid_2d;', '$1', 1)
    $rdBufText = Replace-Required $rdBufText 'assign read_en = rd_en && (rd_cnt != 2''d3);' `
        'assign read_en = rd_en && display_valid_2d && (rd_cnt != 2''d3);'
    $rdBufText = Replace-Required $rdBufText 'assign read_en = rd_en && (rd_cnt[0] != 1''b1);' `
        'assign read_en = rd_en && display_valid_2d && (rd_cnt[0] != 1''b1);'
    $rdBufText = Replace-Required $rdBufText 'assign read_en = rd_en;' `
        'assign read_en = rd_en && display_valid_2d;'
    [System.IO.File]::WriteAllBytes($rdBufPath, $latin1.GetBytes($rdBufText))

    $requiredProjectFiles = @(
        'HDMI_IN_DDR3_HDMI_OUT.pds',
        'HDMI_IN_DDR3_HDMI_OUT_top.fdc',
        'source/rtl/HDMI_IN_DDR3_HDMI_OUT_top.v',
        'source/rtl/fram_buf.v',
        'source/rtl/capture_frame_admission.v',
        'source/rtl/capture_pixel_gate.v',
        'source/rtl/ddr_write_drain_tracker.v',
        'source/rtl/frame_pool_manager.v',
        'source/rtl/frame_pool_address.v',
        'source/rtl/frame_pipeline_ownership.v',
        'source/rtl/ddr_read_burst_arbiter.v'
        'source/rtl/display_read_adapter.v'
        'source/rtl/ddr_write_burst_arbiter.v'
        'source/rtl/frame_copy_engine.v'
    )
    foreach ($relativePath in $requiredProjectFiles) {
        $path = Join-Path $projectPath $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required project input was not copied: $relativePath"
        }
    }

    $pdsPath = Join-Path $projectPath 'HDMI_IN_DDR3_HDMI_OUT.pds'
    $pdsText = Get-Content -LiteralPath $pdsPath -Raw
    $readAdapterEntry = @'
                (_file "source/rtl/display_read_adapter.v"
                    (_format verilog)
                    (_timespec "2026-10-20T17:23:00")
                )
'@
    $readAdapterEntry = $readAdapterEntry.Replace("`n", "`r`n") + "`r`n"
    $pdsText = Replace-Required $pdsText `
        '                (_file "source/rtl/ddr_read_burst_arbiter.v"' `
        ($readAdapterEntry + '                (_file "source/rtl/ddr_read_burst_arbiter.v"')
    foreach ($newSource in @(
        'source/rtl/ddr_write_burst_arbiter.v',
        'source/rtl/frame_copy_engine.v'
    )) {
        $entry = "                (_file `"$newSource`"`r`n                    (_format verilog)`r`n                    (_timespec `"2026-10-20T17:56:00`")`r`n                )`r`n"
        $pdsText = Replace-Required $pdsText `
            '                (_file "source/rtl/ddr_read_burst_arbiter.v"' `
            ($entry + '                (_file "source/rtl/ddr_read_burst_arbiter.v"')
    }
    Set-Content -LiteralPath $pdsPath -Value $pdsText -Encoding utf8
    foreach ($sourceFile in @(
        'source/rtl/frame_pipeline_ownership.v',
        'source/rtl/frame_pool_address.v',
        'source/rtl/ddr_read_burst_arbiter.v',
        'source/rtl/display_read_adapter.v',
        'source/rtl/ddr_write_burst_arbiter.v',
        'source/rtl/frame_copy_engine.v',
        'source/rtl/capture_frame_admission.v',
        'source/rtl/capture_pixel_gate.v',
        'source/rtl/ddr_write_drain_tracker.v'
    )) {
        if (-not $pdsText.Contains(('"' + $sourceFile + '"'))) {
            throw "PDS source list does not include $sourceFile"
        }
    }

    $readme = @'
# Stage 3 dual frame-pool copy project

This project is generated from the board-accepted `stage3_frame_pool_gate_fix`
project. It is an independent checkout for the input-pool to output-pool frame
copy path. The generator refuses to overwrite an existing destination and
omits PDS build outputs, bitstreams, and local logs.

Regenerate with `New-Stage3DualPoolCopyProject.ps1` from `fpga/project/`.
The video top publishes captured frames to the input pool and directs display
reads to the separate output pool. The read and write burst arbiters connect
the raw frame-copy engine to DDR. The display reader prefetches lines up to
the adapter's 512-beat buffer limit, and a recoverable display underrun blocks
only its current frame. Verify simulation, physical timing, and board operation
before treating its bitstream as accepted.
'@
    Set-Content -LiteralPath (Join-Path $projectPath 'README.md') -Value $readme -Encoding utf8

    Write-Host "Created Stage 3 dual-pool copy project: $projectPath"
    Write-Host "Copied $($sourceFiles.Count) project input files from $sourceProjectPath"
} catch {
    Remove-Item -LiteralPath $projectPath -Recurse -Force
    throw
}
