`timescale 1ns/1ps

module axi_apb_bridge_tb;

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;

    logic clk;
    logic rst;

    // AXI WRITE
    logic [ADDR_WIDTH-1:0] awaddr;
    logic                  awvalid;
    logic                  awready;

    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wvalid;
    logic                    wready;

    logic [1:0] bresp;
    logic       bvalid;
    logic       bready;

    // AXI READ
    logic [ADDR_WIDTH-1:0] araddr;
    logic                  arvalid;
    logic                  arready;

    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rvalid;
    logic                  rready;

    // APB
    logic [ADDR_WIDTH-1:0]   paddr;
    logic [DATA_WIDTH-1:0]   pwdata;
    logic [DATA_WIDTH/8-1:0] pstrb;
    logic                    pwrite;
    logic                    psel;
    logic                    penable;
    logic                    pready;
    logic [DATA_WIDTH-1:0]   prdata;
    logic                    pslverr;

    logic [DATA_WIDTH-1:0] apb_read_data;
    logic                  apb_error;
    integer                apb_wait_cycles;
    integer                apb_access_count;
    integer                last_apb_access_cycles;

    axi_apb_bridge #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk      (clk),
        .rst      (rst),

        .awaddr   (awaddr),
        .awvalid  (awvalid),
        .awready  (awready),

        .wdata    (wdata),
        .wstrb    (wstrb),
        .wvalid   (wvalid),
        .wready   (wready),

        .bresp    (bresp),
        .bvalid   (bvalid),
        .bready   (bready),

        .araddr   (araddr),
        .arvalid  (arvalid),
        .arready  (arready),

        .rdata    (rdata),
        .rresp    (rresp),
        .rvalid   (rvalid),
        .rready   (rready),

        .paddr    (paddr),
        .pwdata   (pwdata),
        .pstrb    (pstrb),
        .pwrite   (pwrite),
        .psel     (psel),
        .penable  (penable),

        .pready   (pready),
        .prdata   (prdata),
        .pslverr  (pslverr)
    );

    // Clock
    always #5 clk = ~clk;

    // Simple APB slave model
    always_comb begin
        pready  = 1'b0;
        prdata  = apb_read_data;
        pslverr = apb_error;

        if (psel && penable &&
            (apb_access_count >= apb_wait_cycles))
            pready = 1'b1;
    end

    always @(posedge clk) begin
        if (rst) begin
            apb_access_count      <= 0;
            last_apb_access_cycles <= 0;
        end else if (psel && !penable) begin
            // New APB transaction: start counting access cycles.
            apb_access_count <= 0;
        end else if (psel && penable) begin
            apb_access_count <= apb_access_count + 1;

            if (pready) begin
                last_apb_access_cycles <= apb_access_count + 1;

                $display("[%0t] APB ACCESS: %s ADDR=%h WDATA=%h STRB=%h ERROR=%b",
                         $time,
                         pwrite ? "WRITE" : "READ",
                         paddr,
                         pwdata,
                         pstrb,
                         apb_error);
            end
        end else begin
            apb_access_count <= 0;
        end
    end

    task automatic axi_write(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [DATA_WIDTH/8-1:0] strb,
        input logic expected_error
    );
        begin
            @(negedge clk);
            awaddr  = addr;
            awvalid = 1'b1;
            wdata   = data;
            wstrb   = strb;
            wvalid  = 1'b1;
            bready  = 1'b0;

            wait (awready && wready);
            @(negedge clk);
            awvalid = 1'b0;
            wvalid  = 1'b0;

            wait (bvalid);

            if (expected_error) begin
                if (bresp !== 2'b10) begin
                    $display("[FAIL] Write expected SLVERR, got %b", bresp);
                    $fatal;
                end
            end else begin
                if (bresp !== 2'b00) begin
                    $display("[FAIL] Write expected OKAY, got %b", bresp);
                    $fatal;
                end
            end

            $display("[PASS] AXI WRITE addr=%h data=%h", addr, data);

            @(negedge clk);
            bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_write_split(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [DATA_WIDTH/8-1:0] strb
    );
        begin
            // Send AW first.
            @(negedge clk);
            awaddr  = addr;
            awvalid = 1'b1;

            wait (awready);

            @(negedge clk);
            awvalid = 1'b0;

            // Send W one cycle later.
            @(negedge clk);
            wdata   = data;
            wstrb   = strb;
            wvalid  = 1'b1;

            wait (wready);

            @(negedge clk);
            wvalid  = 1'b0;

            wait (bvalid);

            if (bresp !== 2'b00) begin
                $display("[FAIL] Split AW/W write expected OKAY, got %b", bresp);
                $fatal;
            end

            $display("[PASS] SPLIT AXI WRITE addr=%h data=%h", addr, data);

            @(negedge clk);
            bready = 1'b1;

            @(posedge clk);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] expected_data,
        input logic expected_error
    );
        begin
            @(negedge clk);
            araddr  = addr;
            arvalid = 1'b1;
            rready  = 1'b0;

            wait (arready);
            @(negedge clk);
            arvalid = 1'b0;

            wait (rvalid);

            if (rdata !== expected_data) begin
                $display("[FAIL] Read data expected=%h got=%h",
                         expected_data, rdata);
                $fatal;
            end

            if (expected_error) begin
                if (rresp !== 2'b10) begin
                    $display("[FAIL] Read expected SLVERR, got %b", rresp);
                    $fatal;
                end
            end else begin
                if (rresp !== 2'b00) begin
                    $display("[FAIL] Read expected OKAY, got %b", rresp);
                    $fatal;
                end
            end

            $display("[PASS] AXI READ addr=%h data=%h", addr, rdata);

            @(negedge clk);
            rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;

        awaddr  = '0;
        awvalid = 1'b0;
        wdata   = '0;
        wstrb   = '0;
        wvalid  = 1'b0;
        bready  = 1'b0;

        araddr  = '0;
        arvalid = 1'b0;
        rready  = 1'b0;

        apb_read_data          = 32'hA5A5_1234;
        apb_error              = 1'b0;
        apb_wait_cycles        = 0;
        apb_access_count       = 0;
        last_apb_access_cycles = 0;

        $dumpfile("sim/axi_apb_bridge_wave.vcd");
        $dumpvars(0, axi_apb_bridge_tb);

        repeat (2) @(posedge clk);
        rst = 1'b0;

        // Normal write
        axi_write(
            32'h0000_1000,
            32'hDEAD_BEEF,
            4'b1111,
            1'b0
        );

        // Normal read
        apb_read_data = 32'h1234_5678;
        axi_read(
            32'h0000_2000,
            32'h1234_5678,
            1'b0
        );

        // AXI AW and W arrive in separate cycles
        apb_wait_cycles = 0;
        axi_write_split(
            32'h0000_2500,
            32'h1122_3344,
            4'b1111
        );

        // APB wait-state test
        apb_wait_cycles = 2;
        apb_read_data = 32'h8765_4321;
        axi_read(
            32'h0000_2600,
            32'h8765_4321,
            1'b0
        );

        if (last_apb_access_cycles < 3) begin
            $display("[FAIL] APB wait-state test did not hold PREADY low long enough");
            $fatal;
        end

        $display("[PASS] APB WAIT-STATE test: %0d APB ACCESS cycles",
                 last_apb_access_cycles);

        apb_wait_cycles = 0;

        // Write with APB error
        apb_error = 1'b1;
        axi_write(
            32'h0000_3000,
            32'hCAFE_BABE,
            4'b1111,
            1'b1
        );

        // Read with APB error
        apb_read_data = 32'hFACE_CAFE;
        axi_read(
            32'h0000_4000,
            32'hFACE_CAFE,
            1'b1
        );

        apb_error = 1'b0;

        $display("");
        $display("========================================");
        $display("  ALL AXI-APB BRIDGE TESTS PASSED");
        $display("========================================");

        #20;
        $finish;
    end

endmodule
