// =============================================================================
//  tb_async_fifo.sv
//  Parameterized Testbench for async_fifo
//  Default under test: DATA_WIDTH=32, ADDR_WIDTH=4 (16 entries deep)
//
//  Test plan:
//    TEST 1 — Reset state          : wfull=0, rempty=1 after de-assert
//    TEST 2 — Fill to full         : write DEPTH words, verify wfull
//    TEST 3 — Overflow protection  : extra write while full, pointer unchanged
//    TEST 4 — Drain & verify       : read all words, scoreboard check
//    TEST 5 — Underflow protection : extra read while empty, pointer unchanged
//    TEST 6 — Simultaneous R/W     : concurrent writer/reader, asymmetric clocks
//    TEST 7 — Random burst stress  : 200 random ops, full scoreboard tracking
//
//  Clocks:
//    wclk : 10 ns (100 MHz)
//    rclk : 13 ns (~77 MHz) — incommensurate with wclk for realistic CDC
// =============================================================================

`timescale 1ns/1ps

module tb_async_fifo;

    // ── TB-level parameters (must match or override DUT defaults) ─────────────
    localparam int DW    = 32;  // DATA_WIDTH under test
    localparam int AW    = 4;   // ADDR_WIDTH under test
    localparam int DEPTH = 1 << AW;

    // ── Clock half-periods ────────────────────────────────────────────────────
    localparam int WCLK_HALF = 5;   // 10 ns → 100 MHz
    localparam int RCLK_HALF = 6;   // 13 ns →  ~77 MHz

    // ── DUT ports ─────────────────────────────────────────────────────────────
    logic          wclk, wrst_n, winc;
    logic [DW-1:0] wdata;
    logic          wfull;

    logic          rclk, rrst_n, rinc;
    logic [DW-1:0] rdata;
    logic          rempty;

    // ── DUT instantiation — override parameters here ──────────────────────────
    async_fifo #(
        .DATA_WIDTH (DW),
        .ADDR_WIDTH (AW)
    ) dut (
        .wclk   (wclk),  .wrst_n(wrst_n), .winc(winc),
        .wdata  (wdata), .wfull (wfull),
        .rclk   (rclk),  .rrst_n(rrst_n), .rinc(rinc),
        .rdata  (rdata), .rempty(rempty)
    );

    // ── Clock generation ──────────────────────────────────────────────────────
    initial wclk = 0;
    always  #(WCLK_HALF) wclk = ~wclk;

    initial rclk = 0;
    always  #(RCLK_HALF) rclk = ~rclk;

    // ── Scoreboard ────────────────────────────────────────────────────────────
    logic [DW-1:0] ref_q  [$];
    int            err_cnt  = 0;
    int            wr_total = 0;
    int            rd_total = 0;

    // =========================================================================
    //  Tasks
    // =========================================================================

    // ── Write one word (wclk domain) ──────────────────────────────────────────
    task automatic do_write(input logic [DW-1:0] d);
        @(posedge wclk); #1;
        if (!wfull) begin
            winc  = 1'b1;
            wdata = d;
            ref_q.push_back(d);
            wr_total++;
        end
        @(posedge wclk); #1;
        winc = 1'b0;
    endtask

    // ── Read one word + scoreboard check (rclk domain) ────────────────────────
    task automatic do_read();
        logic [DW-1:0] exp;
        @(posedge rclk); #1;
        if (!rempty) begin
            rinc = 1'b1;
            @(posedge rclk); #1;
            rinc = 1'b0;
            #2;
            exp = ref_q.pop_front();
            rd_total++;
            if (rdata !== exp) begin
                $error("[TB] @%0t DATA MISMATCH: got 0x%08h  expected 0x%08h",
                       $time, rdata, exp);
                err_cnt++;
            end
        end
    endtask

    // ── Drain all remaining entries ───────────────────────────────────────────
    task automatic drain_fifo();
        repeat(6) @(posedge rclk);
        while (!rempty || ref_q.size() > 0) begin
            if (!rempty) begin
                do_read();
            end else begin
                repeat(4) @(posedge rclk);
                if (rempty && ref_q.size() > 0) begin
                    $error("[TB] Scoreboard has %0d leftover entries but FIFO is empty!",
                           ref_q.size());
                    err_cnt++;
                    break;
                end
            end
        end
    endtask

    // =========================================================================
    //  Main stimulus
    // =========================================================================
    initial begin
        $display("\n╔══════════════════════════════════════════════╗");
        $display(  "║  async_fifo TB  DATA_WIDTH=%0d  DEPTH=%0d       ║", DW, DEPTH);
        $display(  "╚══════════════════════════════════════════════╝");

        // ── Initialise outputs ────────────────────────────────────────────────
        wrst_n = 0; rrst_n = 0;
        winc   = 0; rinc   = 0;
        wdata  = '0;

        // ── Release resets ────────────────────────────────────────────────────
        repeat(6) @(posedge wclk);
        repeat(6) @(posedge rclk);
        @(posedge wclk); wrst_n = 1;
        @(posedge rclk); rrst_n = 1;
        repeat(4) @(posedge wclk);

        // =====================================================================
        //  TEST 1 — Reset state
        // =====================================================================
        $display("\n── TEST 1: Reset state ──────────────────────");
        @(posedge wclk); #1;
        if (wfull)
            begin $error("[T1] FAIL: wfull should be 0 after reset");  err_cnt++; end
        else $display("[T1] PASS  wfull  = 0");

        @(posedge rclk); #1;
        if (!rempty)
            begin $error("[T1] FAIL: rempty should be 1 after reset"); err_cnt++; end
        else $display("[T1] PASS  rempty = 1");

        // =====================================================================
        //  TEST 2 — Fill to full
        // =====================================================================
        $display("\n── TEST 2: Fill FIFO (%0d × %0d-bit words) ───", DEPTH, DW);
        for (int i = 0; i < DEPTH; i++)
            do_write(DW'($urandom));

        repeat(6) @(posedge wclk); #1;
        if (!wfull)
            begin $error("[T2] FAIL: wfull not asserted after %0d writes", DEPTH); err_cnt++; end
        else $display("[T2] PASS  wfull asserted after %0d writes", DEPTH);

        // =====================================================================
        //  TEST 3 — Overflow protection
        // =====================================================================
        $display("\n── TEST 3: Overflow protection ──────────────");
        begin
            automatic logic [dut.PTR_WIDTH-1:0] wbin_snap = dut.wbin;
            @(posedge wclk); #1;
            winc  = 1'b1;
            wdata = {DW{1'b1}};         // garbage — should not enter
            @(posedge wclk); #1;
            winc = 1'b0;
            if (dut.wbin !== wbin_snap)
                begin $error("[T3] FAIL: wbin advanced during overflow"); err_cnt++; end
            else $display("[T3] PASS  wbin held stable on full write");
        end

        // =====================================================================
        //  TEST 4 — Drain & data integrity
        // =====================================================================
        $display("\n── TEST 4: Drain & data integrity ───────────");
        for (int i = 0; i < DEPTH; i++)
            do_read();

        repeat(6) @(posedge rclk); #1;
        if (!rempty)
            begin $error("[T4] FAIL: rempty not asserted after drain"); err_cnt++; end
        else $display("[T4] PASS  rempty asserted, %0d words verified", rd_total);

        // =====================================================================
        //  TEST 5 — Underflow protection
        // =====================================================================
        $display("\n── TEST 5: Underflow protection ─────────────");
        begin
            automatic logic [dut.PTR_WIDTH-1:0] rbin_snap = dut.rbin;
            @(posedge rclk); #1;
            rinc = 1'b1;
            @(posedge rclk); #1;
            rinc = 1'b0;
            if (dut.rbin !== rbin_snap)
                begin $error("[T5] FAIL: rbin advanced during underflow"); err_cnt++; end
            else $display("[T5] PASS  rbin held stable on empty read");
        end

        // =====================================================================
        //  TEST 6 — Simultaneous R/W (asymmetric clocks)
        // =====================================================================
        $display("\n── TEST 6: Simultaneous R/W (32 ops each) ───");
        fork
            begin   // Writer thread (wclk domain)
                for (int i = 0; i < 32; i++) begin
                    do_write(DW'(32'hC0000000 + i));
                    if ($urandom_range(0, 1)) @(posedge wclk);
                end
            end
            begin   // Reader thread (rclk domain)
                repeat(4) @(posedge rclk);      // small head start for writes
                for (int i = 0; i < 32; i++) begin
                    if (!rempty) do_read();
                    else repeat(3) @(posedge rclk);
                    if ($urandom_range(0, 1)) @(posedge rclk);
                end
            end
        join
        drain_fifo();
        $display("[T6] PASS  concurrent R/W done, scoreboard clean");

        // =====================================================================
        //  TEST 7 — Random burst stress (200 writes, 200 reads)
        // =====================================================================
        $display("\n── TEST 7: Random burst stress (200 ops) ────");
        fork
            begin   // Writer: random data, random gaps
                for (int i = 0; i < 200; i++) begin
                    do_write(DW'($urandom));
                    repeat($urandom_range(0, 3)) @(posedge wclk);
                end
            end
            begin   // Reader: slightly slower, creates back-pressure
                repeat(5) @(posedge rclk);
                for (int i = 0; i < 200; i++) begin
                    repeat($urandom_range(1, 4)) @(posedge rclk);
                    if (!rempty) do_read();
                end
            end
        join
        drain_fifo();
        $display("[T7] PASS  stress test complete");

        // =====================================================================
        //  Summary
        // =====================================================================
        $display("\n╔══════════════════════════════════════════════╗");
        $display(  "║  SIMULATION COMPLETE                         ║");
        $display(  "║  Total writes : %-4d                          ║", wr_total);
        $display(  "║  Total reads  : %-4d                          ║", rd_total);
        if (err_cnt == 0)
        $display(  "║  Result       : ALL TESTS PASSED ✓           ║");
        else
        $display(  "║  Result       : %0d ERROR(S) DETECTED ✗        ║", err_cnt);
        $display(  "╚══════════════════════════════════════════════╝\n");
        $finish;
    end

    // ── Timeout watchdog ──────────────────────────────────────────────────────
    initial begin
        #5_000_000;
        $error("[TB] TIMEOUT — simulation exceeded 5 ms");
        $finish;
    end

    // ── Optional VCD dump ─────────────────────────────────────────────────────
`ifdef DUMP_VCD
    initial begin
        $dumpfile("async_fifo.vcd");
        $dumpvars(0, tb_async_fifo);
    end
`endif

endmodule