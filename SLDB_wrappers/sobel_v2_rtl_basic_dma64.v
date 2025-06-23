`timescale 1ns / 1ps

module sobel_v2_rtl_basic_dma64
#(
    parameter integer MAX_PIXELS = 4096
) (
    
    input  wire         clk,
    input  wire         rst,                  // active-low

    
    input  wire [31:0]  conf_info_width,
    input  wire [31:0]  conf_info_height,
    input  wire         conf_done,

    
    output wire         dma_read_ctrl_valid,
    output wire [31:0]  dma_read_ctrl_data_index,
    output wire [31:0]  dma_read_ctrl_data_length,
    output wire [2:0]   dma_read_ctrl_data_size,
    input  wire         dma_read_ctrl_ready,

    output wire         dma_read_chnl_ready,
    input  wire         dma_read_chnl_valid,
    input  wire [63:0]  dma_read_chnl_data,

    output wire         dma_write_ctrl_valid,
    output wire [31:0]  dma_write_ctrl_data_index,
    output wire [31:0]  dma_write_ctrl_data_length,
    output wire [2:0]   dma_write_ctrl_data_size,
    input  wire         dma_write_ctrl_ready,

    input  wire         dma_write_chnl_ready,
    output wire         dma_write_chnl_valid,
    output wire [63:0]  dma_write_chnl_data,

    output reg          acc_done,
    output wire [31:0]  debug
);


    typedef enum logic [2:0] {
        S_IDLE,          // wait for conf_done
        S_RD_CTRL,       // assert read-ctrl.valid
        S_READ,          // receive windows & compute Sobel
        S_WR_CTRL,       // assert write-ctrl.valid
        S_WRITE          // send one beat
    } fsm_t;

    fsm_t state;


    wire [31:0] num_pixels = conf_info_width * conf_info_height;
    always @(*) if (num_pixels > MAX_PIXELS)
        $error("Frame size exceeds MAX_PIXELS=%0d", MAX_PIXELS);

    reg [31:0] pixel_cnt;     // windows already processed / edge pixels produced
    reg [31:0] wr_count;      // edge pixels already written (multiple of 8)


    reg [7:0] lu, cu, ru, lc, rc, lb, cb, rb;
    wire [7:0] sobel_out;

    SobelFilter sobel_filter_i (
        .lu(lu), .cu(cu), .ru(ru),
        .lc(lc), .rc(rc),
        .lb(lb), .cb(cb), .rb(rb),
        .edge_lum(sobel_out)
    );


    reg  [63:0] write_word;
    reg  [2:0]  byte_ptr;                       // 0-7
    wire        word_full = (byte_ptr == 3'd7);


    assign dma_read_ctrl_valid       = (state == S_RD_CTRL);
    assign dma_read_ctrl_data_index  = 32'd0;
    assign dma_read_ctrl_data_length = num_pixels;      // one beat per pixel
    assign dma_read_ctrl_data_size   = 3'd3;            // 8-byte beats
    assign dma_read_chnl_ready       = (state == S_READ);


    assign dma_write_ctrl_valid      = (state == S_WR_CTRL);
    assign dma_write_ctrl_data_index = wr_count[31:3];  // beat address
    assign dma_write_ctrl_data_length= 32'd1;           // always one beat
    assign dma_write_ctrl_data_size  = 3'd3;

    assign dma_write_chnl_valid      = (state == S_WRITE);
    assign dma_write_chnl_data       = write_word;

    // debug port
    assign debug = {29'd0, state};

    integer i;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state      <= S_IDLE;
            pixel_cnt  <= 0;
            wr_count   <= 0;
            byte_ptr   <= 0;
            write_word <= 64'd0;
            acc_done   <= 1'b0;
        end else begin
            case (state)
               
                S_IDLE: begin
                    if (!conf_done) begin
                        pixel_cnt <= 0;
                        wr_count  <= 0;
                        byte_ptr  <= 0;
                        acc_done  <= 1'b0;
                    end else begin
                        state <= S_RD_CTRL;     // start read burst
                    end
                end
                
                S_RD_CTRL: begin
                    if (dma_read_ctrl_ready) begin
                        // ctrl handshake completed
                        state <= S_READ;
                    end
                end
               
                S_READ: begin
                    if (dma_read_chnl_valid) begin
                        // unpack window bytes (MS-byte first)
                        {lu, cu, ru, lc, rc, lb, cb, rb} <= dma_read_chnl_data;

                        // deposit Sobel result into packer
                        write_word[63 - byte_ptr*8 -: 8] <= sobel_out;

                        pixel_cnt <= pixel_cnt + 1;

                        if (word_full || (pixel_cnt + 1 == num_pixels)) begin
                            // zero-pad the last (partial) beat
                            if (!word_full) begin
                                for (i = 0; i < 8; i = i + 1)
                                    if (i > byte_ptr)
                                        write_word[63 - i*8 -: 8] <= 8'd0;
                            end
                            state <= S_WR_CTRL;
                        end else begin
                            byte_ptr <= byte_ptr + 1;
                        end
                    end
                end
                
                S_WR_CTRL: begin
                    if (dma_write_ctrl_ready) begin
                        // ctrl handshake completed
                        state <= S_WRITE;
                    end
                end
                
                S_WRITE: begin
                    if (dma_write_chnl_ready) begin
                        wr_count   <= wr_count + 8;   // book-keeping
                        write_word <= 64'd0;
                        byte_ptr   <= 0;

                        if (pixel_cnt == num_pixels &&
                            wr_count + 8 >= num_pixels) begin
                            acc_done <= 1'b1;
                            state    <= S_IDLE;
                        end else begin
                            state <= S_READ;          // grab next window
                        end
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
