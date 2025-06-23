module aesdecipher_v2_rtl_basic_dma64( 
   input clk,
   input rst,

   /* <<--params-def-->> */
   input [31:0]  conf_info_aes_key_3,
   input [31:0]  conf_info_aes_key_2,
   input [31:0]  conf_info_aes_key_1,
   input [31:0]  conf_info_aes_key_0,
   input [31:0]  conf_info_aes_key_7,
   input [31:0]  conf_info_aes_key_6,
   input [31:0]  conf_info_aes_key_5,
   input [31:0]  conf_info_aes_key_4,
   input [31:0]  conf_info_aes_num_blocks,
   input 	 conf_done,

   input 	 dma_read_ctrl_ready,
   output reg 	 dma_read_ctrl_valid,
   output reg [31:0] dma_read_ctrl_data_index,
   output reg [31:0] dma_read_ctrl_data_length,
   output reg [2:0]  dma_read_ctrl_data_size,

   output reg	 dma_read_chnl_ready,
   input 	 dma_read_chnl_valid,
   input [63:0]  dma_read_chnl_data,

   input 	 dma_write_ctrl_ready,
   output reg	 dma_write_ctrl_valid,
   output reg [31:0] dma_write_ctrl_data_index,
   output reg [31:0] dma_write_ctrl_data_length,
   output reg [2:0]  dma_write_ctrl_data_size,

   input 	 dma_write_chnl_ready,
   output reg	 dma_write_chnl_valid,
   output reg [63:0] dma_write_chnl_data,

   output reg	 acc_done,
   output reg [31:0] debug
);
    


   // -----------------------------------------------------------------------
   // 1) Combine 8 words (256 bits) into the AES key
   // -----------------------------------------------------------------------
   wire [255:0] aes_key = {
       conf_info_aes_key_0,
       conf_info_aes_key_1,
       conf_info_aes_key_2,
       conf_info_aes_key_3,
       conf_info_aes_key_4,
       conf_info_aes_key_5,
       conf_info_aes_key_6,
       conf_info_aes_key_7
   };

   // -----------------------------------------------------------------------
   // 2) AES I/O
   // -----------------------------------------------------------------------
   reg  [127:0] aes_block_in;
   wire [127:0] aes_block_out;
   reg  [127:0] aes_out_reg;

   aesdecipher u_decipher (
       .clk      (clk),
       .datain   (aes_block_in),
       .key      (aes_key),
       .dataout  (aes_block_out)
   );

   // -----------------------------------------------------------------------
   // 3) States (Added WAIT_AES after ENCRYPT)
   // -----------------------------------------------------------------------
   localparam STATE_IDLE       = 3'd0;
   localparam STATE_READ_CTRL  = 3'd1;
   localparam STATE_READ_DATA  = 3'd2;
   localparam STATE_ENCRYPT    = 3'd3;
   localparam STATE_WAIT_AES   = 3'd4; // <-- new
   localparam STATE_WRITE_CTRL = 3'd5;
   localparam STATE_WRITE_DATA = 3'd6;

   reg [2:0] state;

   // user says "aes_num_blocks" => # of 128-bit blocks
   wire [31:0] total_blocks = conf_info_aes_num_blocks;

   // Index of current block
   reg [31:0] block_count;

   // reading 2 beats => 128 bits
   reg read_beat;
   reg write_beat;
   reg [63:0] block_beat0;
   reg [63:0] block_beat1;

   // -----------------------------------------------------------------------
   // 4) Main FSM with extra wait state
   // -----------------------------------------------------------------------
   always @(posedge clk or negedge rst) begin
      if (!rst) begin
         state        <= STATE_IDLE;
         dma_read_ctrl_valid  <= 1'b0;
         dma_read_chnl_ready  <= 1'b0;
         dma_write_ctrl_valid <= 1'b0;
         dma_write_chnl_valid <= 1'b0;
         dma_write_chnl_data  <= 64'd0;

         block_count  <= 32'd0;
         read_beat    <= 1'b0;
         write_beat   <= 1'b0;
         block_beat0  <= 64'd0;
         block_beat1  <= 64'd0;

         aes_block_in <= 128'd0;
         aes_out_reg  <= 128'd0;

         acc_done     <= 1'b0;
         debug        <= 32'd0;

      end else begin
         // default each cycle
         dma_read_ctrl_valid  <= 1'b0;
         dma_read_chnl_ready  <= 1'b0;
         dma_write_ctrl_valid <= 1'b0;
         dma_write_chnl_valid <= 1'b0;

         case (state)

           //---------------------------------------------------------------
           // STATE_IDLE
           //---------------------------------------------------------------
           STATE_IDLE: begin
               dma_read_ctrl_data_index   <= 32'd0;
               dma_read_ctrl_data_length  <= 32'd2;  // 2 beats
               dma_read_ctrl_data_size    <= 3'b011; // 64-bit
              if (acc_done) acc_done <= 1'b0;

              if (conf_done && total_blocks != 0) begin
                 block_count                <= 32'd0;
                 // request read of 2 beats => 128 bits

                 dma_read_ctrl_valid        <= 1'b1;

                 if (dma_read_ctrl_ready) begin
                    // handshake now
                    dma_read_ctrl_valid <= 1'b0;
                    read_beat <= 1'b0;
                    state <= STATE_READ_DATA;
                 end else begin
                    // wait for read_ctrl_ready
                    state <= STATE_READ_CTRL;
                 end
              end else if (block_count == total_blocks) begin
                 // done with all blocks
                 acc_done <= 1'b1;
                 state <= STATE_IDLE;
              end else if (conf_done && (total_blocks == 0)) begin
                 acc_done <= 1'b1;
              end
           end

           //---------------------------------------------------------------
           // STATE_READ_CTRL
           //---------------------------------------------------------------
           STATE_READ_CTRL: begin
              dma_read_ctrl_valid <= 1'b1;
              if (dma_read_ctrl_ready) begin
                 dma_read_ctrl_valid <= 1'b0;
                 read_beat <= 1'b0;
                 state <= STATE_READ_DATA;
              end
           end

           //---------------------------------------------------------------
           // STATE_READ_DATA
           //---------------------------------------------------------------
           STATE_READ_DATA: begin
              dma_read_chnl_ready <= 1'b1;
              if (dma_read_chnl_valid) begin
                 if (!read_beat) begin
                    block_beat0 <= dma_read_chnl_data;
                    read_beat   <= 1'b1;
                 end else begin
                    block_beat1 <= dma_read_chnl_data;
                    state <= STATE_ENCRYPT;
                 end
              end
           end

           //---------------------------------------------------------------
           // STATE_ENCRYPT: load aes_block_in
           //---------------------------------------------------------------
           STATE_ENCRYPT: begin
              // feed the AES input block
              aes_block_in <= {block_beat0, block_beat1};
              // Now wait a cycle for aes_block_out to become valid
              state <= STATE_WAIT_AES;
           end

           //---------------------------------------------------------------
           // STATE_WAIT_AES: latch aes_out_reg
           //---------------------------------------------------------------
           STATE_WAIT_AES: begin
              aes_out_reg <= aes_block_out;  // stable now (one cycle later)
              state <= STATE_WRITE_CTRL;
           end

           //---------------------------------------------------------------
           // STATE_WRITE_CTRL: request to write 2 beats
           //---------------------------------------------------------------
           STATE_WRITE_CTRL: begin
              dma_write_ctrl_data_index  <= (block_count << 1);
              dma_write_ctrl_data_length <= 32'd2;
              dma_write_ctrl_data_size   <= 3'b011;
              dma_write_ctrl_valid       <= 1'b1;

              if (dma_write_ctrl_ready) begin
                 dma_write_ctrl_valid <= 1'b0;
                 write_beat <= 1'b0;
                 state <= STATE_WRITE_DATA;
              end
           end

           //---------------------------------------------------------------
           // STATE_WRITE_DATA: send 128 bits => 2×64 beats from aes_out_reg
           //---------------------------------------------------------------
           STATE_WRITE_DATA: begin

              if (dma_write_chnl_ready) begin
                 if (!write_beat) begin
                    // upper 64 bits
                    dma_write_chnl_data <= aes_out_reg[127:64];
                    dma_write_chnl_valid <= 1'b1;
                    write_beat <= 1'b1;
                 end else begin
                    // lower 64 bits => done with this block
                    dma_write_chnl_data <= aes_out_reg[63:0];
                    dma_write_chnl_valid <= 1'b1;
                  //   #5; // wait a cycle
                    block_count <= block_count + 1;
                    dma_read_ctrl_data_index  <= 0;
                    dma_read_ctrl_data_length <= 32'd2;
                    dma_read_ctrl_data_size   <= 3'b011;
                    // if more blocks remain, read next block
                    if (block_count + 1 < total_blocks) begin

                       dma_read_ctrl_valid       <= 1'b1;
                       
                       read_beat <= 1'b0;

                       if (dma_read_ctrl_ready) begin
                          dma_read_ctrl_valid <= 1'b0;
                          state <= STATE_READ_DATA;
                       end else begin
                          state <= STATE_READ_CTRL;
                       end
                    end else begin
                       // finished all blocks
                     //   #1; // wait a cycle
                     //   acc_done <= 1'b1;
                       state <= STATE_IDLE;
                    end
                 end
              end
           end

           default: state <= STATE_IDLE;

         endcase
      end
   end
   
endmodule
