module axi_apb_bridge #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic rst,

    // AXI4-Lite WRITE ADDRESS
    input  logic [ADDR_WIDTH-1:0] awaddr,
    input  logic                  awvalid,
    output logic                  awready,

    // AXI4-Lite WRITE DATA
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [DATA_WIDTH/8-1:0] wstrb,
    input  logic                    wvalid,
    output logic                    wready,

    // AXI4-Lite WRITE RESPONSE
    output logic [1:0] bresp,
    output logic       bvalid,
    input  logic       bready,

    // AXI4-Lite READ ADDRESS
    input  logic [ADDR_WIDTH-1:0] araddr,
    input  logic                  arvalid,
    output logic                  arready,

    // AXI4-Lite READ DATA
    output logic [DATA_WIDTH-1:0] rdata,
    output logic [1:0]            rresp,
    output logic                  rvalid,
    input  logic                  rready,

    // APB4
    output logic [ADDR_WIDTH-1:0]   paddr,
    output logic [DATA_WIDTH-1:0]   pwdata,
    output logic [DATA_WIDTH/8-1:0] pstrb,
    output logic                    pwrite,
    output logic                    psel,
    output logic                    penable,
    input  logic                    pready,
    input  logic [DATA_WIDTH-1:0]   prdata,
    input  logic                    pslverr
);

    typedef enum logic [2:0] {
        ST_IDLE       = 3'd0,
        ST_APB_SETUP  = 3'd1,
        ST_APB_ACCESS = 3'd2,
        ST_BRESP      = 3'd3,
        ST_RDATA      = 3'd4
    } state_t;

    state_t state;

    // Latched AXI write address
    logic [ADDR_WIDTH-1:0] awaddr_reg;
    logic                  awaddr_valid_reg;

    // Latched AXI write data
    logic [DATA_WIDTH-1:0]   wdata_reg;
    logic [DATA_WIDTH/8-1:0] wstrb_reg;
    logic                    wdata_valid_reg;

    // Latched AXI read address
    logic [ADDR_WIDTH-1:0] araddr_reg;
    logic                  araddr_valid_reg;

    // APB direction
    logic apb_write_reg;

    // AXI responses
    logic [1:0]            bresp_reg;
    logic [DATA_WIDTH-1:0] rdata_reg;
    logic [1:0]            rresp_reg;

    logic aw_fire;
    logic w_fire;
    logic ar_fire;
    logic write_start;
    logic read_start;

    // ------------------------------------------------------------
    // Combinational outputs
    // ------------------------------------------------------------
    always_comb begin
        awready = 1'b0;
        wready  = 1'b0;
        arready = 1'b0;

        bvalid  = (state == ST_BRESP);
        rvalid  = (state == ST_RDATA);

        bresp   = bresp_reg;
        rdata   = rdata_reg;
        rresp   = rresp_reg;

        paddr   = apb_write_reg ? awaddr_reg : araddr_reg;
        pwdata  = wdata_reg;
        pstrb   = wstrb_reg;
        pwrite  = apb_write_reg;

        psel    = (state == ST_APB_SETUP) ||
                  (state == ST_APB_ACCESS);
        penable = (state == ST_APB_ACCESS);

        if (state == ST_IDLE) begin
            awready = !awaddr_valid_reg && !araddr_valid_reg;
            wready  = !wdata_valid_reg && !araddr_valid_reg;

            // Write has priority over a simultaneous read request.
            arready = !araddr_valid_reg &&
                      !awaddr_valid_reg &&
                      !wdata_valid_reg &&
                      !awvalid &&
                      !wvalid;
        end
    end

    assign aw_fire = awvalid && awready;
    assign w_fire  = wvalid  && wready;
    assign ar_fire = arvalid && arready;

    // A write starts when both independent AXI write pieces exist.
    assign write_start = (state == ST_IDLE) &&
                         (awaddr_valid_reg || aw_fire) &&
                         (wdata_valid_reg || w_fire);

    assign read_start = (state == ST_IDLE) && ar_fire;

    // ------------------------------------------------------------
    // Sequential control / FSM
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state            <= ST_IDLE;

            awaddr_reg       <= '0;
            awaddr_valid_reg <= 1'b0;

            wdata_reg        <= '0;
            wstrb_reg        <= '0;
            wdata_valid_reg  <= 1'b0;

            araddr_reg       <= '0;
            araddr_valid_reg <= 1'b0;

            apb_write_reg    <= 1'b0;

            bresp_reg        <= 2'b00;
            rdata_reg        <= '0;
            rresp_reg        <= 2'b00;
        end else begin
            case (state)

                // ------------------------------------------------
                // Wait for AXI request
                // ------------------------------------------------
                ST_IDLE: begin
                    if (aw_fire) begin
                        awaddr_reg       <= awaddr;
                        awaddr_valid_reg <= 1'b1;
                    end

                    if (w_fire) begin
                        wdata_reg       <= wdata;
                        wstrb_reg       <= wstrb;
                        wdata_valid_reg <= 1'b1;
                    end

                    if (ar_fire) begin
                        araddr_reg       <= araddr;
                        araddr_valid_reg <= 1'b1;
                    end

                    if (write_start) begin
                        apb_write_reg    <= 1'b1;
                        awaddr_valid_reg <= 1'b0;
                        wdata_valid_reg  <= 1'b0;
                        state            <= ST_APB_SETUP;
                    end else if (read_start) begin
                        apb_write_reg    <= 1'b0;
                        araddr_valid_reg <= 1'b0;
                        state            <= ST_APB_SETUP;
                    end
                end

                // ------------------------------------------------
                // APB setup phase
                // ------------------------------------------------
                ST_APB_SETUP: begin
                    state <= ST_APB_ACCESS;
                end

                // ------------------------------------------------
                // APB access phase
                // ------------------------------------------------
                ST_APB_ACCESS: begin
                    if (pready) begin
                        if (apb_write_reg) begin
                            bresp_reg <= pslverr ? 2'b10 : 2'b00;
                            state     <= ST_BRESP;
                        end else begin
                            rdata_reg <= prdata;
                            rresp_reg <= pslverr ? 2'b10 : 2'b00;
                            state     <= ST_RDATA;
                        end
                    end
                end

                // ------------------------------------------------
                // AXI write response
                // ------------------------------------------------
                ST_BRESP: begin
                    if (bready) begin
                        state <= ST_IDLE;
                    end
                end

                // ------------------------------------------------
                // AXI read response
                // ------------------------------------------------
                ST_RDATA: begin
                    if (rready) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule
