
module simple_dnn_rtl_basic_dma64 (
    clk, rst,
    // DMA read channel
    dma_read_chnl_valid, dma_read_chnl_data, dma_read_chnl_ready,
    // configuration
    conf_info_num_in, conf_info_num_out, conf_info_num_hidden,
    conf_done, acc_done, debug,
    // DMA read ctrl
    dma_read_ctrl_valid,  dma_read_ctrl_data_index,
    dma_read_ctrl_data_length, dma_read_ctrl_data_size, dma_read_ctrl_ready,
    // DMA write ctrl
    dma_write_ctrl_valid, dma_write_ctrl_data_index,
    dma_write_ctrl_data_length, dma_write_ctrl_data_size, dma_write_ctrl_ready,
    // DMA write channel
    dma_write_chnl_valid, dma_write_chnl_data, dma_write_chnl_ready
);
   
    input  wire        clk;
    input  wire        rst;                     // active-LOW async reset

    input  wire [31:0] conf_info_num_in;
    input  wire [31:0] conf_info_num_out;
    input  wire [31:0] conf_info_num_hidden;
    input  wire        conf_done;

    input  wire        dma_read_ctrl_ready;
    output reg         dma_read_ctrl_valid;
    output reg  [31:0] dma_read_ctrl_data_index;
    output reg  [31:0] dma_read_ctrl_data_length;
    output reg  [2:0]  dma_read_ctrl_data_size;

    
    output reg         dma_read_chnl_ready;
    input  wire        dma_read_chnl_valid;
    input  wire [63:0] dma_read_chnl_data;

    
    input  wire        dma_write_ctrl_ready;
    output reg         dma_write_ctrl_valid;
    output reg  [31:0] dma_write_ctrl_data_index;
    output reg  [31:0] dma_write_ctrl_data_length;
    output reg  [2:0]  dma_write_ctrl_data_size;

   
    input  wire        dma_write_chnl_ready;
    output reg         dma_write_chnl_valid;
    output reg  [63:0] dma_write_chnl_data;

    
    output reg         acc_done;
    output reg  [31:0] debug;

    
    reg [31:0] dnn_in0_reg, dnn_in1_reg, dnn_in2_reg;
    reg        dnn_in_valid_reg;

    
    wire signed [31:0] dnn_data_out;
    wire               dnn_data_out_en;

    
    dnn_soc u_dnn_soc (
        .clk       (clk),
        .rst_n     (rst),             
        .data_in_0 (dnn_in0_reg),
        .data_in_1 (dnn_in1_reg),
        .data_in_2 (dnn_in2_reg),
        .data_out  (dnn_data_out),
        .data_out_en(dnn_data_out_en)
    );

    
    localparam STATE_IDLE    = 3'd0,
               STATE_RD_CTRL = 3'd1,
               STATE_RD_CHNL = 3'd2,
               STATE_RD_DONE = 3'd3,
               STATE_WR_CTRL = 3'd4,
               STATE_WR_DATA = 3'd5;

    reg  [2:0]  state;
    reg  [31:0] dma_beat_count;
    reg         pgm_read;       // main processing phase
    reg         configured;
    reg         half_flag;
    reg  [63:0] stored_dma_data;

    
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            // ---------- asynchronous reset ----------
            state                 <= STATE_IDLE;
            dma_beat_count        <= 0;
            pgm_read              <= 1'b0;
            configured            <= 1'b0;
            acc_done              <= 1'b0;
            half_flag             <= 1'b0;
            stored_dma_data       <= 64'd0;
            dnn_in_valid_reg      <= 1'b0;

            // outputs
            dma_read_ctrl_valid   <= 1'b0;
            dma_write_ctrl_valid  <= 1'b0;
            dma_write_chnl_valid  <= 1'b0;
            dma_read_chnl_ready   <= 1'b0;
            debug                 <= 32'd0;
        end else begin
            // ---------- cycle-level defaults ----------
            dma_read_ctrl_valid   <= 1'b0;
            dma_write_ctrl_valid  <= 1'b0;
            dma_write_chnl_valid  <= 1'b0;
            dma_read_chnl_ready   <= 1'b0;
            dnn_in_valid_reg      <= 1'b0;
            debug                 <= {29'd0, state};

            // ---------- FSM ----------
            case (state)
               
                STATE_IDLE: begin
                    dma_beat_count <= 0;
                    half_flag      <= 1'b0;
                    acc_done       <= 1'b0;
                    if (conf_done && !configured) begin
                        configured <= 1'b1;
                        pgm_read   <= 1'b1;
                        state      <= STATE_RD_CTRL;
                    end
                end

               
                STATE_RD_CTRL: begin
                    dma_read_ctrl_valid      <= 1'b1;
                    dma_read_ctrl_data_index <= 0;
                    dma_read_ctrl_data_length<= (pgm_read) ? (conf_info_num_out << 1)
                                                         :   conf_info_num_in;
                    dma_read_ctrl_data_size  <= 3'd3;     // 64-bit
                    if (dma_read_ctrl_ready) begin
                        state          <= STATE_RD_CHNL;
                        dma_beat_count <= 0;
                    end
                end

                
                STATE_RD_CHNL: begin
                    dma_read_chnl_ready <= 1'b1;
                    if (dma_read_chnl_valid) begin
                        dma_beat_count <= dma_beat_count + 1;
                        if (!half_flag) begin
                            stored_dma_data <= dma_read_chnl_data;
                            half_flag       <= 1'b1;
                        end else begin
                            dnn_in0_reg     <= stored_dma_data[31:0];
                            dnn_in1_reg     <= stored_dma_data[63:32];
                            dnn_in2_reg     <= dma_read_chnl_data[31:0];
                            dnn_in_valid_reg<= 1'b1;
                            half_flag       <= 1'b0;
                        end
                    end

                    if (pgm_read &&
                        dma_beat_count == ((conf_info_num_out << 1) - 1)) begin
                        state          <= STATE_WR_CTRL;
                        dma_beat_count <= 0;
                    end
                    else if (!pgm_read &&
                             dma_beat_count == (conf_info_num_in - 1)) begin
                        state <= STATE_IDLE;
                    end
                end

                
                STATE_RD_DONE: begin
                    dma_read_chnl_ready <= 1'b1;
                    if (dma_read_chnl_valid) begin
                        dma_beat_count <= dma_beat_count + 1;
                        if (!half_flag) begin
                            stored_dma_data <= dma_read_chnl_data;
                            half_flag       <= 1'b1;
                        end else begin
                            dnn_in0_reg      <= stored_dma_data[31:0];
                            dnn_in1_reg      <= stored_dma_data[63:32];
                            dnn_in2_reg      <= dma_read_chnl_data[31:0];
                            dnn_in_valid_reg <= 1'b1;
                            half_flag        <= 1'b0;
                        end
                    end
                    if (dma_beat_count ==
                        (((conf_info_num_out * conf_info_num_hidden) << 1) - 1)) begin
                        state          <= STATE_WR_CTRL;
                        dma_beat_count <= 0;
                    end
                end

                
                STATE_WR_CTRL: begin
                    dma_write_ctrl_valid      <= 1'b1;
                    dma_write_ctrl_data_index <= 0;
                    dma_write_ctrl_data_length<= conf_info_num_out;
                    dma_write_ctrl_data_size  <= 3'd3;   // 64-bit
                    if (dma_write_ctrl_ready) begin
                        state          <= STATE_WR_DATA;
                        dma_beat_count <= 0;
                    end
                end

               
                STATE_WR_DATA: begin
                    dma_write_chnl_valid <= dnn_data_out_en;
                    dma_write_chnl_data  <= {32'd0, dnn_data_out};
                    if (dma_write_chnl_ready && dnn_data_out_en)
                        dma_beat_count <= dma_beat_count + 1;
                    if (dma_beat_count == conf_info_num_out) begin
                        state    <= STATE_IDLE;
                        acc_done <= 1'b1;
                    end
                end
            endcase
        end
    end
endmodule
