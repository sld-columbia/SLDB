
`timescale 1ns/1ps

module sha256_rtl_basic_dma64
#(
    parameter FIFO_DEPTH = 8
)
(
    
    input  wire         clk,
    input  wire         rst,

    
    input  wire [31:0]  conf_info_sha_msg_size,   // # beats to read
    input  wire [31:0]  conf_info_sha_mode,
    input  wire         conf_done,

    input  wire         dma_read_ctrl_ready,
    output wire         dma_read_ctrl_valid,
    output wire [31:0]  dma_read_ctrl_data_index,
    output wire [31:0]  dma_read_ctrl_data_length,
    output wire [2:0]   dma_read_ctrl_data_size,

    output wire         dma_read_chnl_ready,
    input  wire         dma_read_chnl_valid,
    input  wire [63:0]  dma_read_chnl_data,

    input  wire         dma_write_ctrl_ready,
    output reg          dma_write_ctrl_valid,
    output wire [31:0]  dma_write_ctrl_data_index,
    output wire [31:0]  dma_write_ctrl_data_length,
    output wire [2:0]   dma_write_ctrl_data_size,

    input  wire         dma_write_chnl_ready,
    output wire         dma_write_chnl_valid,
    output wire [63:0]  dma_write_chnl_data,

    output reg          acc_done,
    output wire [31:0]  debug
);


    localparam S_IDLE       = 3'd0;
    localparam S_READ_CMD   = 3'd1;
    localparam S_READ_DATA  = 3'd2;
    localparam S_PROCESS    = 3'd3;
    localparam S_WRITE_CMD  = 3'd4;
    localparam S_WRITE_DATA = 3'd5;

    reg  [2:0]  state, next_state;

    reg  [2:0]  read_beat_ctr;
    reg  [1:0]  write_beat_ctr;         // 0-3

    reg         first_block;
    reg         reg_dma_read_ctrl_valid;

    // control pulses to sha256_top
    reg         reg_init, reg_next;

    // 512-bit message block buffer
    reg [511:0] data_block;

    
    wire [255:0] digest;
    wire         digest_valid;
    wire         ready;

    sha256_top sha256_inst (
        .clk      (clk),
        .reset_n  (rst),
        .init     (reg_init),
        .next     (reg_next),
        .mode     (conf_info_sha_mode[0]),
        .block    (data_block),
        .ready    (ready),
        .digest   (digest),
        .digest_valid(digest_valid)
    );

    
    assign dma_read_ctrl_valid       = reg_dma_read_ctrl_valid;
    assign dma_read_ctrl_data_index  = 32'd0;
    assign dma_read_ctrl_data_length = conf_info_sha_msg_size;
    assign dma_read_ctrl_data_size   = 3'b011;      // 64-bit beats

 
    assign dma_write_ctrl_data_index  = 32'd0;
    assign dma_write_ctrl_data_length = 32'd4;      // 4 beats
    assign dma_write_ctrl_data_size   = 3'b011;

 
    assign dma_read_chnl_ready = (state == S_READ_DATA);

    
    assign dma_write_chnl_valid = (state == S_WRITE_DATA);

    assign dma_write_chnl_data  =
           (state != S_WRITE_DATA)                ? 64'h0               :
           (write_beat_ctr == 2'd0)               ? digest[ 63:  0]     :
           (write_beat_ctr == 2'd1)               ? digest[127: 64]     :
           (write_beat_ctr == 2'd2)               ? digest[191:128]     :
                                                    digest[255:192];    // beat 3

    
    assign debug = 32'd0;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state                   <= S_IDLE;
            reg_dma_read_ctrl_valid <= 1'b0;
            dma_write_ctrl_valid    <= 1'b0;
            read_beat_ctr           <= 3'd0;
            write_beat_ctr          <= 2'd0;
            first_block             <= 1'b1;
            reg_init                <= 1'b0;
            reg_next                <= 1'b0;
            acc_done                <= 1'b0;
            data_block              <= 512'd0;
        end
        else begin
            // default pulse-type signals
            reg_init  <= 1'b0;
            reg_next  <= 1'b0;
            acc_done  <= 1'b0;

            case (state)

                
                S_IDLE: begin
                    dma_write_ctrl_valid <= 1'b0;
                    reg_dma_read_ctrl_valid <= 1'b0;

                    if (conf_done)
                        state <= S_READ_CMD;
                end

               
                S_READ_CMD: begin
                    reg_dma_read_ctrl_valid <= 1'b1;
                    if (dma_read_ctrl_ready) begin
                        reg_dma_read_ctrl_valid <= 1'b0;
                        read_beat_ctr <= 3'd0;
                        data_block    <= 512'd0;
                        state         <= S_READ_DATA;
                    end
                end

                
                S_READ_DATA: begin
                    if (dma_read_chnl_valid) begin
                        // store 64-bit beat into block buffer
                        case (read_beat_ctr)
                            3'd0: data_block[ 63:  0] <= dma_read_chnl_data;
                            3'd1: data_block[127: 64] <= dma_read_chnl_data;
                            3'd2: data_block[191:128] <= dma_read_chnl_data;
                            3'd3: data_block[255:192] <= dma_read_chnl_data;
                            3'd4: data_block[319:256] <= dma_read_chnl_data;
                            3'd5: data_block[383:320] <= dma_read_chnl_data;
                            3'd6: data_block[447:384] <= dma_read_chnl_data;
                            3'd7: data_block[511:448] <= dma_read_chnl_data;
                        endcase

                        if (read_beat_ctr == 3'd7)
                            state <= S_PROCESS;
                        else
                            read_beat_ctr <= read_beat_ctr + 1'b1;
                    end
                end

                
                S_PROCESS: begin
                    if (first_block) begin
                        reg_init    <= 1'b1;    // first block → init
                        first_block <= 1'b0;
                    end
                    else begin
                        reg_next <= 1'b1;       // subsequent block → next
                    end

                    if (digest_valid) begin
                        dma_write_ctrl_valid <= 1'b1;  // issue WRITE cmd
                        state                <= S_WRITE_CMD;
                    end
                end

                
                S_WRITE_CMD: begin
                    if (dma_write_ctrl_ready) begin
                        dma_write_ctrl_valid <= 1'b0;
                        write_beat_ctr <= 2'd0;
                        state          <= S_WRITE_DATA;
                    end
                end

                
                S_WRITE_DATA: begin
                    // counter advances only on handshake
                    if (dma_write_chnl_valid && dma_write_chnl_ready) begin
                        if (write_beat_ctr == 2'd3) begin
                            // last word accepted
                            acc_done       <= 1'b1;  // pulse
                            state          <= S_IDLE;
                        end
                        write_beat_ctr <= write_beat_ctr + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
