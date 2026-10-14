# PG2L200H / 200Pro+ reproducible implementation entry point.
# Source paths are derived from this file so the project can be moved without
# retaining machine-specific absolute paths.
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676

set project_root [file normalize [file join [file dirname [info script]] .. .. .. ..]]

foreach source_file {
    rtl/algorithm/distortion/coordinate_gen.sv
    rtl/algorithm/distortion/coordinate_split.sv
    rtl/algorithm/distortion/normalize.sv
    rtl/algorithm/distortion/distortion_core.sv
    rtl/algorithm/distortion/distortion_core_optimized.sv
    rtl/algorithm/distortion/distortion_image_pipeline.sv
    rtl/algorithm/interpolation/bilinear_interp.sv
    rtl/platform/common/control/algorithm_reset_tree.sv
    rtl/platform/common/memory/pixel_fetch_if.sv
    rtl/platform/common/memory/pixel_fetch_engine.sv
    rtl/platform/common/memory/pixel_tile_cache.sv
    rtl/platform/common/memory/tile_cache_bank_ram.sv
    rtl/platform/common/memory/ddr_burst_reader.sv
    rtl/platform/common/memory/cached_pixel_fetch_engine.sv
    rtl/platform/common/memory/coordinate_fifo.sv
    rtl/board/pg2l200h/reset_sync.sv
    rtl/board/pg2l200h/distortion_frame_processor.sv
    rtl/board/pg2l200h/algorithm_frame_writer.sv
    rtl/board/pg2l200h/algorithm_frame_writer_rgbx.sv
    rtl/board/pg2l200h/board_video_control.sv
    rtl/board/pg2l200h/ddr3_frame_reader.sv
    rtl/board/pg2l200h/ddr3_frame_reader_rgbx.sv
    rtl/board/pg2l200h/ddr3_pixel_read_adapter.sv
    rtl/board/pg2l200h/ddr3_rgbx_cache_adapter.sv
    rtl/board/pg2l200h/ddr_two_client_arbiter.sv
    rtl/board/pg2l200h/realtime_frame_scheduler.sv
    rtl/board/pg2l200h/video_mode_720p60.sv
    rtl/board/pg2l200h/pg2l200h_board_top.sv
    rtl/vendor/pg2l200h/hdmi/iic_dri.v
    rtl/vendor/pg2l200h/hdmi/ms7200_ctl.v
    rtl/vendor/pg2l200h/hdmi/ms7210_ctl.v
    rtl/vendor/pg2l200h/hdmi/ms72xx_ctl.v
    rtl/vendor/pg2l200h/ddr/rd_ctrl.v
    rtl/vendor/pg2l200h/ddr/wr_buf.v
    rtl/vendor/pg2l200h/ddr/wr_cmd_trans.v
    rtl/vendor/pg2l200h/ddr/wr_ctrl.v
    rtl/vendor/pg2l200h/ddr/wr_rd_ctrl_top.v
    rtl/vendor/pg2l200h/memory/tile_cache_bank_ip.v
} {
    add_design [file join $project_root $source_file]
}

foreach ip_file {
    rtl/vendor/pg2l200h/ddr/rd_fram_buf/rd_fram_buf.idf
    rtl/vendor/pg2l200h/ddr/wr_fram_buf/wr_fram_buf.idf
    ip/pango/pg2l200h/ddr3/ddr3_test.idf
    ip/pango/pg2l200h/video_pll/pll.idf
    ip/pango/pg2l200h/cfg_pll/cfg_pll.idf
} {
    add_design [file join $project_root $ip_file]
}

add_constraint [file join $project_root boards pg2l200h constraints pg2l200h_board_top.fdc]
compile -top_module pg2l200h_board_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr
report_timing