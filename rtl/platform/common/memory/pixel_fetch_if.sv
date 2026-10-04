// Vendor-neutral logical pixel request/response port declaration.
// req_addr is a logical pixel number, not a DDR byte address.
module pixel_fetch_if #(
    parameter integer ADDR_WIDTH  = 32,
    parameter integer PIXEL_WIDTH = 24
) (
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire [ADDR_WIDTH-1:0] req_addr,
    output wire                  rsp_valid,
    input  wire                  rsp_ready,
    output wire [PIXEL_WIDTH-1:0] rsp_data
);
endmodule
