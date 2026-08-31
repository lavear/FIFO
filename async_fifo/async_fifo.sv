// =============================================================================
//  async_fifo.sv
//  Industry-Standard Dual-Clock Asynchronous FIFO (CDC Safe)
//  Fully Parameterized — defaults: DATA_WIDTH=32, ADDR_WIDTH=4 (16 deep)
//
//  Architecture:
//    - Dual-port SRAM (2D reg array) for storage
//    - Binary write/read pointers (one extra bit for full/empty detection)
//    - Gray-code conversion before crossing clock domains
//    - Two-flop synchronizers on each gray-code pointer
//    - Full  detected in WRITE clock domain (wclk)
//    - Empty detected in READ  clock domain (rclk)
//
//  Parameters:
//    DATA_WIDTH  – width of each data word           (default 32)
//    ADDR_WIDTH  – log2(depth); depth = 2^ADDR_WIDTH (default 4 → 16 entries)
//
//  Interface:
//    Write side : wclk, wrst_n, winc, wdata[DATA_WIDTH-1:0], wfull
//    Read  side : rclk, rrst_n, rinc, rdata[DATA_WIDTH-1:0], rempty
//
//  CDC Notes:
//    • Gray-code pointers change only 1 bit per transition — a two-flop
//      synchronizer is safe regardless of data width.
//    • wfull  registered on wclk; rempty registered on rclk.
//    • Both resets asynchronous, active-low.
//    • PTR_WIDTH = ADDR_WIDTH + 1 (extra wrap-bit for full/empty detect).
//
//  References:
//    Cummings, C.E. (2002). "Simulation and Synthesis Techniques for
//    Asynchronous FIFO Design." SNUG San Jose 2002. (Sunburst Design)
// =============================================================================

`timescale 1ns/1ps

module async_fifo #(
    parameter int DATA_WIDTH = 32,   // Data bus width        (override as needed)
    parameter int ADDR_WIDTH = 4     // log2(depth): 4 → 16 entries deep
) (
    // ── Write port ────────────────────────────────────────────────────────────
    input  logic                  wclk,   // Write clock
    input  logic                  wrst_n, // Write reset (async, active-low)
    input  logic                  winc,   // Write enable
    input  logic [DATA_WIDTH-1:0] wdata,  // Write data
    output logic                  wfull,  // FIFO full  (wclk domain)

    // ── Read port ─────────────────────────────────────────────────────────────
    input  logic                  rclk,   // Read clock
    input  logic                  rrst_n, // Read  reset (async, active-low)
    input  logic                  rinc,   // Read  enable
    output logic [DATA_WIDTH-1:0] rdata,  // Read  data
    output logic                  rempty  // FIFO empty (rclk domain)
);

    // ── Derived local parameters ──────────────────────────────────────────────
    localparam int PTR_WIDTH = ADDR_WIDTH + 1;  // extra MSB for full/empty
    localparam int DEPTH     = 1 << ADDR_WIDTH; // number of storage locations

    // ── Dual-port memory ──────────────────────────────────────────────────────
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ── Binary pointers ───────────────────────────────────────────────────────
    logic [PTR_WIDTH-1:0] wbin, wbin_next;
    logic [PTR_WIDTH-1:0] rbin, rbin_next;

    // ── Gray-code pointers ────────────────────────────────────────────────────
    logic [PTR_WIDTH-1:0] wgray, wgray_next;
    logic [PTR_WIDTH-1:0] rgray, rgray_next;

    // ── Two-flop synchronizer registers ──────────────────────────────────────
    logic [PTR_WIDTH-1:0] wgray_sync1, wgray_sync2;  // wgray → rclk
    logic [PTR_WIDTH-1:0] rgray_sync1, rgray_sync2;  // rgray → wclk

    // ── Memory address (lower ADDR_WIDTH bits of binary pointer) ──────────────
    logic [ADDR_WIDTH-1:0] waddr;
    logic [ADDR_WIDTH-1:0] raddr;

    assign waddr = wbin[ADDR_WIDTH-1:0];
    assign raddr = rbin[ADDR_WIDTH-1:0];

    // =========================================================================
    //  WRITE DOMAIN
    // =========================================================================

    // ── Next-state logic (combinational) ──────────────────────────────────────
    assign wbin_next  = wbin + (winc & ~wfull);
    assign wgray_next = wbin_next ^ (wbin_next >> 1);

    // ── Write pointer registers ───────────────────────────────────────────────
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= '0;
            wgray <= '0;
        end else begin
            wbin  <= wbin_next;
            wgray <= wgray_next;
        end
    end

    // ── Memory write ──────────────────────────────────────────────────────────
    always_ff @(posedge wclk) begin
        if (winc && !wfull)
            mem[waddr] <= wdata;
    end

    // ── Full flag ─────────────────────────────────────────────────────────────
    // Full when wgray_next == rgray_sync2 with the two MSBs inverted.
    // The top-2-bit inversion is the standard Cummings wrap-around check and
    // is ALWAYS exactly 2 bits regardless of ADDR_WIDTH.
    logic wfull_val;
    assign wfull_val = (wgray_next == {~rgray_sync2[PTR_WIDTH-1:PTR_WIDTH-2],
                                        rgray_sync2[PTR_WIDTH-3:0]});

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) wfull <= 1'b0;
        else         wfull <= wfull_val;
    end

    // ── Two-flop synchronizer: rgray → wclk ──────────────────────────────────
    (* ASYNC_REG = "TRUE" *)
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            rgray_sync1 <= '0;
            rgray_sync2 <= '0;
        end else begin
            rgray_sync1 <= rgray;
            rgray_sync2 <= rgray_sync1;
        end
    end

    // =========================================================================
    //  READ DOMAIN
    // =========================================================================

    // ── Next-state logic (combinational) ──────────────────────────────────────
    assign rbin_next  = rbin + (rinc & ~rempty);
    assign rgray_next = rbin_next ^ (rbin_next >> 1);

    // ── Read pointer registers ────────────────────────────────────────────────
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin  <= '0;
            rgray <= '0;
        end else begin
            rbin  <= rbin_next;
            rgray <= rgray_next;
        end
    end

    // ── Memory read (asynchronous) ────────────────────────────────────────────
    assign rdata = mem[raddr];

    // ── Empty flag ────────────────────────────────────────────────────────────
    // Empty when rgray_next == wgray_sync2 (pointers are equal).
    logic rempty_val;
    assign rempty_val = (rgray_next == wgray_sync2);

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rempty <= 1'b1;
        else         rempty <= rempty_val;
    end

    // ── Two-flop synchronizer: wgray → rclk ──────────────────────────────────
    (* ASYNC_REG = "TRUE" *)
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            wgray_sync1 <= '0;
            wgray_sync2 <= '0;
        end else begin
            wgray_sync1 <= wgray;
            wgray_sync2 <= wgray_sync1;
        end
    end

    // =========================================================================
    //  Assertions (simulation-only SVA)
    // =========================================================================
`ifdef SIMULATION
    property p_no_overflow;
        @(posedge wclk) disable iff (!wrst_n)
        (winc && wfull) |-> ##1 (wbin == $past(wbin));
    endproperty
    assert property (p_no_overflow)
        else $error("[ASYNC_FIFO] Write attempted while FULL  (DATA_WIDTH=%0d, DEPTH=%0d)",
                    DATA_WIDTH, DEPTH);

    property p_no_underflow;
        @(posedge rclk) disable iff (!rrst_n)
        (rinc && rempty) |-> ##1 (rbin == $past(rbin));
    endproperty
    assert property (p_no_underflow)
        else $error("[ASYNC_FIFO] Read  attempted while EMPTY (DATA_WIDTH=%0d, DEPTH=%0d)",
                    DATA_WIDTH, DEPTH);
`endif

endmodule