`timescale 1ns / 1ps
// ============================================================================
// 64-bit-DMA wrapper for the FCDNN accelerator
// ============================================================================

module fcdnn_acc_rtl_basic_dma64 (

    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] conf_info_array_size,   
    input  wire [31:0] conf_info_mux_cfg,
    input  wire [31:0] conf_info_exp_val,
    input  wire [31:0] conf_info_pipe_mode,    
    input  wire [31:0] conf_info_runs,         
    input  wire        conf_done,

    output reg         acc_done,
    output reg [31:0]  debug,

    output reg         dma_read_ctrl_valid,
    output reg [31:0]  dma_read_ctrl_data_index,
    output reg [31:0]  dma_read_ctrl_data_length,
    output reg [2:0]   dma_read_ctrl_data_size,
    input  wire        dma_read_ctrl_ready,

    input  wire        dma_read_chnl_valid,
    input  wire [63:0] dma_read_chnl_data,
    output reg         dma_read_chnl_ready,

    output reg         dma_write_ctrl_valid,
    output reg [31:0]  dma_write_ctrl_data_index,
    output reg [31:0]  dma_write_ctrl_data_length,
    output reg [2:0]   dma_write_ctrl_data_size,
    input  wire        dma_write_ctrl_ready,

    output reg         dma_write_chnl_valid,
    output reg [63:0]  dma_write_chnl_data,
    input  wire        dma_write_chnl_ready
);


typedef enum logic [2:0] {
    STATE_IDLE    = 3'd0,
    STATE_RD_CTRL = 3'd1,
    STATE_RD_DATA = 3'd2,
    STATE_COMPUTE = 3'd3,
    STATE_WR_CTRL = 3'd4,
    STATE_WR_DATA = 3'd5
} state_t;

state_t state;

localparam int NUM_BEATS_RD = 28;   // 28 × 64  = 1792 bits  (inputs)
localparam int NUM_BEATS_WR = 15;   // 15 × 64  =  960 bits  (outputs)
localparam int MAX_BEATS    = 1024;

reg             configured;
reg  [31:0]     beat_ctr;

reg [63:0] input_buf [0:MAX_BEATS-1];


wire [26:0]  core_mul_in_1_single;
wire [431:0] core_mul_in_1_pack, core_mul_in_2_pack;
wire [431:0] core_add_in_1_pack, core_add_in_2_pack;
wire [26:0]  core_add_in_2_single;
wire [7:0]   core_exp;

wire [1:0]   core_mul_in_1_mux_sel_left , core_mul_in_1_mux_sel_right;
wire [1:0]   core_mul_in_2_mux_sel;
wire         core_sigmoid_pipe_mux_sel;
wire [1:0]   core_sigmoid_pipe_extend_controll;
wire         core_add_in_1_mux_sel_left;
wire [1:0]   core_add_in_1_mux_sel_right;
wire [1:0]   core_add_in_2_mux_sel, core_add_in_2_mid_mux_sel;
wire         core_sigmoid_output_mux_sel;

wire [431:0] core_mul_out_pack, core_add_out_pack;
wire [26:0]  core_add_out_single, core_sigmoid;


reg  core_in_valid_r;
wire core_in_valid  = core_in_valid_r;
wire core_out_valid;

Core core_inst (
    .clk_pll                     (clk),

    .in_valid                    (core_in_valid),
    .out_valid                   (core_out_valid),

    
    .mul_in_1_single             (core_mul_in_1_single),
    .mul_in_1_pack               (core_mul_in_1_pack),
    .mul_in_2_pack               (core_mul_in_2_pack),
    .add_in_1_pack               (core_add_in_1_pack),
    .add_in_2_pack               (core_add_in_2_pack),
    .add_in_2_single             (core_add_in_2_single),
    .exp                         (core_exp),

   
    .mul_in_1_mux_sel_left       (core_mul_in_1_mux_sel_left),
    .mul_in_1_mux_sel_right      (core_mul_in_1_mux_sel_right),
    .mul_in_2_mux_sel            (core_mul_in_2_mux_sel),
    .sigmoid_pipe_mux_sel        (core_sigmoid_pipe_mux_sel),
    .sigmoid_pipe_extend_controll(core_sigmoid_pipe_extend_controll),
    .add_in_1_mux_sel_left       (core_add_in_1_mux_sel_left),
    .add_in_1_mux_sel_right      (core_add_in_1_mux_sel_right),
    .add_in_2_mux_sel            (core_add_in_2_mux_sel),
    .add_in_2_mid_mux_sel        (core_add_in_2_mid_mux_sel),
    .sigmoid_output_mux_sel      (core_sigmoid_output_mux_sel),

    
    .mul_out_pack                (core_mul_out_pack),
    .add_out_pack                (core_add_out_pack),
    .add_out_single              (core_add_out_single),
    .sigmoid                     (core_sigmoid)
);


wire [1791:0] raw_input_data = { 
    input_buf[0],  input_buf[1],  input_buf[2],  input_buf[3],
    input_buf[4],  input_buf[5],  input_buf[6],  input_buf[7],
    input_buf[8],  input_buf[9],  input_buf[10], input_buf[11],
    input_buf[12], input_buf[13], input_buf[14], input_buf[15],
    input_buf[16], input_buf[17], input_buf[18], input_buf[19],
    input_buf[20], input_buf[21], input_buf[22], input_buf[23],
    input_buf[24], input_buf[25], input_buf[26], input_buf[27]
};

assign core_mul_in_1_single = raw_input_data[1791:1765];
assign core_mul_in_1_pack   = raw_input_data[1764:1333];
assign core_mul_in_2_pack   = raw_input_data[1332:901 ];
assign core_add_in_1_pack   = raw_input_data[900 :469 ];
assign core_add_in_2_pack   = raw_input_data[468 :37  ];
assign core_add_in_2_single = raw_input_data[36  :10  ];
assign core_exp             = raw_input_data[9   :2   ];


assign core_mul_in_1_mux_sel_left         = conf_info_mux_cfg[1:0];
assign core_mul_in_1_mux_sel_right        = conf_info_mux_cfg[3:2];
assign core_mul_in_2_mux_sel              = conf_info_mux_cfg[5:4];
assign core_sigmoid_pipe_mux_sel          = conf_info_mux_cfg[6];
assign core_sigmoid_pipe_extend_controll  = conf_info_mux_cfg[8:7];
assign core_add_in_1_mux_sel_left         = conf_info_mux_cfg[9];
assign core_add_in_1_mux_sel_right        = conf_info_mux_cfg[11:10];
assign core_add_in_2_mux_sel              = conf_info_mux_cfg[13:12];
assign core_add_in_2_mid_mux_sel          = conf_info_mux_cfg[15:14];
assign core_sigmoid_output_mux_sel        = conf_info_mux_cfg[16];


wire [959:0] raw_output_data = {
    core_mul_out_pack,
    core_add_out_pack,
    core_add_out_single,
    core_sigmoid,
    42'd0                     // padding to 960 bits
};

wire [63:0] output_buf [0:MAX_BEATS-1];

genvar g;
generate
    for (g = 0; g < NUM_BEATS_WR; g = g + 1) begin : PACK_OUT
        assign output_buf[g] = raw_output_data[64*g +: 64];
    end
endgenerate

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        state       <= STATE_IDLE;
        configured  <= 1'b0;
        acc_done    <= 1'b0;
        debug       <= 32'd0;
        beat_ctr    <= 32'd0;

        dma_read_ctrl_valid   <= 1'b0;
        dma_read_ctrl_data_index  <= 32'd0;
        dma_read_ctrl_data_length <= 32'd0;
        dma_read_ctrl_data_size   <= 3'd0;
        dma_read_chnl_ready       <= 1'b0;

        dma_write_ctrl_valid  <= 1'b0;
        dma_write_ctrl_data_index  <= 32'd0;
        dma_write_ctrl_data_length <= 32'd0;
        dma_write_ctrl_data_size   <= 3'd0;
        dma_write_chnl_valid <= 1'b0;
        dma_write_chnl_data  <= 64'd0;

        core_in_valid_r <= 1'b0;
    end
    else begin
        // default strobes
        core_in_valid_r <= 1'b0;

        case (state)
      
        STATE_IDLE: begin
            acc_done <= 1'b0;
            dma_read_ctrl_valid  <= 1'b0;
            dma_read_chnl_ready  <= 1'b0;
            dma_write_ctrl_valid <= 1'b0;
            dma_write_chnl_valid <= 1'b0;
            beat_ctr            <= 32'd0;

            if (conf_done && !configured) begin
                configured <= 1'b1;
                state      <= (NUM_BEATS_RD == 0) ? STATE_COMPUTE
                                                  : STATE_RD_CTRL;
            end
        end
       
        STATE_RD_CTRL: begin
            dma_read_ctrl_valid       <= 1'b1;
            dma_read_ctrl_data_index  <= 32'd0;
            dma_read_ctrl_data_length <= NUM_BEATS_RD;
            dma_read_ctrl_data_size   <= 3'd3;           // 64-bit

            if (dma_read_ctrl_ready) begin
                dma_read_ctrl_valid <= 1'b0;
                beat_ctr            <= 32'd0;
                state               <= STATE_RD_DATA;
            end
        end
        
        STATE_RD_DATA: begin
            dma_read_chnl_ready <= 1'b1;
            if (dma_read_chnl_valid) begin
                input_buf[beat_ctr] <= dma_read_chnl_data;
                beat_ctr            <= beat_ctr + 1;

                if (beat_ctr == NUM_BEATS_RD-1) begin
                    dma_read_chnl_ready <= 1'b0;
                    beat_ctr            <= 32'd0;
                    state               <= STATE_COMPUTE;
                end
            end
        end
        
        STATE_COMPUTE: begin
            acc_done <= 1'b0;

            
            if (beat_ctr == 0) core_in_valid_r <= 1'b1;
            beat_ctr <= beat_ctr + 1;

            if (core_out_valid) begin          // Core finished
                state    <= STATE_WR_CTRL;
                beat_ctr <= 32'd0;
            end
        end
        
        STATE_WR_CTRL: begin
            dma_write_ctrl_valid       <= 1'b1;
            dma_write_ctrl_data_index  <= 32'd0;
            dma_write_ctrl_data_length <= NUM_BEATS_WR;
            dma_write_ctrl_data_size   <= 3'd3;          // 64-bit

            if (dma_write_ctrl_ready) begin
                dma_write_ctrl_valid <= 1'b0;
                beat_ctr            <= 32'd0;
                state               <= STATE_WR_DATA;
            end
        end
        // ────────────────────────────────────────────────────────────────
        STATE_WR_DATA: begin
            dma_write_chnl_valid <= 1'b1;
            dma_write_chnl_data  <= output_buf[beat_ctr];

            if (dma_write_chnl_ready) begin
                if (beat_ctr == NUM_BEATS_WR-1) begin
                    dma_write_chnl_valid <= 1'b0;
                    acc_done            <= 1'b1;
                    state               <= STATE_IDLE;
                    beat_ctr            <= 32'd0;
                end
                else begin
                    beat_ctr <= beat_ctr + 1;
                end
            end
        end
       
        default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
