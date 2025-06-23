// ============================================================================
//  LSTM ESP wrapper  (Option-A, split WEs, Xi broadcast to 64 addresses)
// ============================================================================
`timescale 1 ns / 1 ps

`define ARRAY_DEPTH  64
`define INPUT_DEPTH  100
`define DATA_WIDTH   16
`define varraysize   1600
`define uarraysize   1024

module lstm_rtl_basic_dma64
(
    input  wire         clk,
    input  wire         rst,   // active-low
    // ESP configuration
    input  wire [31:0]  conf_info_in_dim,
    input  wire [31:0]  conf_info_hidden_dim,
    input  wire [31:0]  conf_info_num_timesteps,
    input  wire         conf_done,
    input  wire         dma_read_ctrl_ready,
    output reg          dma_read_ctrl_valid,
    output reg  [31:0]  dma_read_ctrl_data_index,
    output reg  [31:0]  dma_read_ctrl_data_length,
    output reg  [2:0]   dma_read_ctrl_data_size,
    output wire         dma_read_chnl_ready,
    input  wire         dma_read_chnl_valid,
    input  wire [63:0]  dma_read_chnl_data,
    input  wire         dma_write_ctrl_ready,
    output reg          dma_write_ctrl_valid,
    output reg  [31:0]  dma_write_ctrl_data_index,
    output reg  [31:0]  dma_write_ctrl_data_length,
    output reg  [2:0]   dma_write_ctrl_data_size,
    input  wire         dma_write_chnl_ready,
    output reg          dma_write_chnl_valid,
    output reg  [63:0]  dma_write_chnl_data,
    output reg          acc_done,
    output reg  [31:0]  debug
);

// Constant parameters
localparam BEATS_U     = (`uarraysize >> 6);            // 16
localparam BEATS_V     = (`varraysize >> 6);            // 25
localparam BEATS_B     = 1;
localparam BEATS_ROW   = BEATS_U + BEATS_V + BEATS_B;   // 42
localparam BEATS_ALL   = BEATS_ROW * `ARRAY_DEPTH;      // 2688
localparam BEATS_X     = BEATS_V;                       // 25
localparam TOTAL_BEATS = BEATS_ALL + BEATS_X;           // 2713



wire                       lstm_ht_valid;
wire [`DATA_WIDTH-1:0]     lstm_ht_out;
wire                       lstm_done;

reg                        lstm_start;
reg                        lstm_load_mode;
reg  [6:0]                 lstm_load_addr;

reg                        wren_u, wren_w, wren_b, wren_x;

reg [`uarraysize-1:0]      lstm_wdata_u;
reg [`varraysize-1:0]      lstm_wdata_v;
reg [`DATA_WIDTH-1:0]      lstm_wdata_b;
reg [`varraysize-1:0]      lstm_wdata_x;


lstm u_lstm (
    .clk          (clk),
    .reset        (!rst),

    .start        (lstm_start),
    .start_addr   (7'd0),
    .end_addr     (7'd63),

    .load_mode    (lstm_load_mode),
    .load_addr    (lstm_load_addr),

    .wren_a_u     (wren_u),
    .wren_a_w     (wren_w),
    .wren_a_b     (wren_b),
    .wren_a_x     (wren_x),

    .wdata_u      (lstm_wdata_u),
    .wdata_v      (lstm_wdata_v),
    .wdata_b      (lstm_wdata_b),
    .wdata_x      (lstm_wdata_x),

    .ht_valid     (lstm_ht_valid),
    .ht_out       (lstm_ht_out),
    .cycle_complete(),
    .Done         (lstm_done)
);

// Buffers to store inputs
reg [1023:0] buf_u;
reg [1599:0] buf_v;
reg [1599:0] buf_x;
reg [15:0]   buf_b;

reg  [5:0]   row_idx;
reg  [4:0]   u_cnt;       // 0-15
reg  [4:0]   v_cnt;       // 0-24
reg  [4:0]   x_cnt;       // 0-24
reg  [6:0]   xi_bcast_cnt;

// ============================================================================
//  FSM
// ============================================================================
localparam S_IDLE         = 0,
           S_RD_CTRL      = 1,
           S_LOAD_U       = 2,
           S_LOAD_V       = 3,
           S_LOAD_B       = 4,
           S_LOAD_X       = 5,
           S_LOAD_X_WAIT  = 6,
           S_BCAST_XI     = 7,
           S_START        = 8,
           S_RUN          = 9,
           S_WR_CTRL      = 10,
           S_WR_STREAM    = 11,
           S_DONE         = 12,
           S_WAIT_BEFORE_START = 13;


reg [3:0] state, nxt;

assign dma_read_chnl_ready = 1'b1;

// State transitions
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        state <= S_IDLE;

        dma_read_ctrl_valid  <= 1'b0;
        dma_write_ctrl_valid <= 1'b0;
        dma_write_chnl_valid <= 1'b0;

        lstm_start      <= 1'b0;
        lstm_load_mode  <= 1'b0;
        lstm_load_addr  <= 7'd0;

        wren_u <= 1'b0; wren_w <= 1'b0; wren_b <= 1'b0; wren_x <= 1'b0;

        row_idx <= 0; u_cnt <= 0; v_cnt <= 0; x_cnt <= 0; xi_bcast_cnt <= 0;
        buf_u   <= '0; buf_v <= '0; buf_x <= '0; buf_b <= '0;

        acc_done <= 1'b0;
        debug    <= 32'd0;
    end else begin
        state <= nxt;

        // ---------- defaults each cycle ----------
        dma_read_ctrl_valid  <= 1'b0;
        dma_write_ctrl_valid <= 1'b0;
        dma_write_chnl_valid <= 1'b0;

        wren_u <= 1'b0;
        wren_w <= 1'b0;
        wren_b <= 1'b0;
        wren_x <= 1'b0;

        lstm_load_mode <= 1'b0;
        lstm_load_addr <= 7'd0;

        
        case (state)
        S_IDLE : begin
            acc_done <= 1'b0;
            if (conf_done) begin
                dma_read_ctrl_valid       <= 1'b1;
                dma_read_ctrl_data_index  <= 32'd0;
                dma_read_ctrl_data_length <= TOTAL_BEATS;
                dma_read_ctrl_data_size   <= 3'd3;
                row_idx <= 0; u_cnt <= 0; v_cnt <= 0; x_cnt <= 0;
            end
        end

        S_RD_CTRL : dma_read_ctrl_valid <= 1'b1;

        
        S_LOAD_U : if (dma_read_chnl_valid) begin
            lstm_load_mode <= 1'b1;
            lstm_load_addr <= row_idx;

            buf_u[u_cnt*64 +: 64] <= dma_read_chnl_data;
            if (u_cnt == 5'd15) begin
                lstm_wdata_u <= buf_u;
                wren_u       <= 1'b1;
                u_cnt        <= 5'd0;
            end else
                u_cnt        <= u_cnt + 1'b1;
        end

        
        S_LOAD_V : if (dma_read_chnl_valid) begin
            lstm_load_mode <= 1'b1;
            lstm_load_addr <= row_idx;

            buf_v[v_cnt*64 +: 64] <= dma_read_chnl_data;
            if (v_cnt == 5'd24) begin
                lstm_wdata_v <= buf_v;
                wren_w       <= 1'b1;
                v_cnt        <= 5'd0;
            end else
                v_cnt        <= v_cnt + 1'b1;
        end

       
        S_LOAD_B : if (dma_read_chnl_valid) begin
            lstm_load_mode <= 1'b1;
            lstm_load_addr <= row_idx;

            buf_b        <= dma_read_chnl_data[15:0];
            lstm_wdata_b <= dma_read_chnl_data[15:0];

            wren_b  <= 1'b1;
            row_idx <= row_idx + 1'b1;
        end

        
        S_LOAD_X : if (dma_read_chnl_valid) begin
            lstm_load_mode <= 1'b1;
            lstm_load_addr <= 7'd0;

            buf_x[x_cnt*64 +: 64] <= dma_read_chnl_data;
            if (x_cnt == 5'd24) begin
                lstm_wdata_x <= buf_x;
               //  wren_x       <= 1'b1;
                x_cnt        <= 5'd0;
                xi_bcast_cnt <= 7'd1; 
            end else
                x_cnt        <= x_cnt + 1'b1;
        end

       
        S_LOAD_X_WAIT : begin
         wren_x         <= 1'b1;   
         lstm_load_mode <= 1'b1;
         lstm_load_addr <= 7'd0;
        end
        
        S_BCAST_XI : begin
            lstm_load_mode <= 1'b1;
            lstm_load_addr <= xi_bcast_cnt;
            wren_x         <= 1'b1;

            xi_bcast_cnt   <= xi_bcast_cnt + 1'b1;
        end
        S_WAIT_BEFORE_START : begin
            lstm_load_mode <= 1'b0; // explicitly drop load
            // wait one clean cycle before starting
        end

        // Start LSTM processing
        S_START : lstm_start <= 1'b1;

        // Stop when done
    // --------- inside the big always @(posedge clk …) case(state) ---------

    S_RUN : begin
        // hold VALID until the beat is accepted
        if (dma_write_chnl_valid && !dma_write_chnl_ready)
            dma_write_chnl_valid <= 1'b1;
        else
            dma_write_chnl_valid <= 1'b0;

        // send a beat whenever the core asserts ht_valid
        if (lstm_ht_valid) begin
            dma_write_chnl_valid <= 1'b1;
            dma_write_chnl_data  <= {48'd0, lstm_ht_out};
        end

        // de-assert start when core signals done
        if (lstm_done)
            lstm_start <= 1'b0;
    end


       
        S_WR_CTRL : begin
            dma_write_ctrl_valid       <= 1'b1;
            dma_write_ctrl_data_index  <= 32'd0;
            // dma_write_ctrl_data_length <= `ARRAY_DEPTH; // 64 beats
            dma_write_ctrl_data_length <= 32'd4096; // 64 beats
            dma_write_ctrl_data_size   <= 3'd3;
        end

        
        S_WR_STREAM : if (lstm_ht_valid && dma_write_chnl_ready) begin
            dma_write_chnl_valid <= 1'b1;
            dma_write_chnl_data  <= {48'd0, lstm_ht_out};
        end

        S_DONE : acc_done <= 1'b1;
        endcase

        debug <= {28'd0, state};
    end
end

// ============================================================================
//  next-state logic
// ============================================================================
always @* begin
    nxt = state;
    case (state)
    S_IDLE        : if (conf_done)                                    nxt = S_RD_CTRL;
    S_RD_CTRL     : if (dma_read_ctrl_ready)                          nxt = S_LOAD_U;

    S_LOAD_U      : if (dma_read_chnl_valid && (u_cnt == 5'd15))      nxt = S_LOAD_V;
    S_LOAD_V      : if (dma_read_chnl_valid && (v_cnt == 5'd24))      nxt = S_LOAD_B;
    S_LOAD_B      : if (dma_read_chnl_valid)
                       nxt = (row_idx == (`ARRAY_DEPTH-1)) ? S_LOAD_X : S_LOAD_U;

    S_LOAD_X      : if (dma_read_chnl_valid && (x_cnt == 5'd24))      nxt = S_LOAD_X_WAIT;
    S_LOAD_X_WAIT :                                                     nxt = S_BCAST_XI;

    S_BCAST_XI    : if (xi_bcast_cnt == 7'd63) nxt = S_WAIT_BEFORE_START;
    S_WAIT_BEFORE_START :                     nxt = S_WR_CTRL;      // << CHG ①
    S_WR_CTRL           : if (dma_write_ctrl_ready)
                                                nxt = S_START;     // << CHG ②
    S_START             :                       nxt = S_RUN;
    S_RUN               : if (lstm_done)        nxt = S_DONE;     
    S_WR_STREAM   : if (!lstm_ht_valid && lstm_done)                    nxt = S_DONE;
    S_DONE        :                                                     nxt = S_IDLE;
    default       : nxt = S_IDLE;
    endcase
end

endmodule
