module spmv_rtl_basic_dma64(
    clk, rst, //RESET SHOULD BE ACTIVE LOW
    dma_read_chnl_valid, dma_read_chnl_data, dma_read_chnl_ready,
    /* <<--params-list-->> */
    conf_info_spmv_nnz,
    conf_info_spmv_vec_len,
    conf_done, 
    acc_done, 
    debug, 
    dma_read_ctrl_valid, dma_read_ctrl_data_index, dma_read_ctrl_data_length, dma_read_ctrl_data_size, dma_read_ctrl_ready, 
    dma_write_ctrl_valid, dma_write_ctrl_data_index, dma_write_ctrl_data_length, dma_write_ctrl_data_size, dma_write_ctrl_ready, 
    dma_write_chnl_valid, dma_write_chnl_data, dma_write_chnl_ready
);

   input clk;
   input rst;

   /* <<--params-def-->> */
   input reg [31:0]  conf_info_spmv_nnz;
   input reg [31:0]  conf_info_spmv_vec_len;
   input reg         conf_done;

   input reg         dma_read_ctrl_ready;
   output reg        dma_read_ctrl_valid;
   output reg [31:0] dma_read_ctrl_data_index;
   output reg [31:0] dma_read_ctrl_data_length;
   output reg [2:0]  dma_read_ctrl_data_size;

   output reg        dma_read_chnl_ready;
   input reg         dma_read_chnl_valid;
   input reg [63:0]  dma_read_chnl_data;

   input reg         dma_write_ctrl_ready;
   output reg        dma_write_ctrl_valid;
   output reg [31:0] dma_write_ctrl_data_index;
   output reg [31:0] dma_write_ctrl_data_length;
   output reg [2:0]  dma_write_ctrl_data_size;

   input reg         dma_write_chnl_ready;
   output reg        dma_write_chnl_valid;
   output wire [63:0] dma_write_chnl_data;

   output reg        acc_done;
   output reg [31:0] debug;

localparam VEC_VAL_BITS = 8;
localparam MAT_VAL_BITS = 8;
localparam MULT_BITS = (VEC_VAL_BITS + MAT_VAL_BITS);
localparam COL_ID_BITS = 8;
localparam ROW_ID_BITS = 8;
localparam MAT_VAL_ADDR_WIDTH = 12;
localparam COL_ID_ADDR_WIDTH = MAT_VAL_ADDR_WIDTH;
localparam ROW_ID_ADDR_WIDTH = MAT_VAL_ADDR_WIDTH;

localparam NUM_VEC_VALS_PER_ADDR = 1;
localparam BVB_AWIDTH = 8;





   // Internal signals for spmv module
   wire [MULT_BITS-1:0] spmv_dout;
   wire spmv_done;

   typedef enum logic [2:0] {
     S_IDLE = 0,
     S_SETUP_READ_MAT,
     S_READ_MAT,
     S_SETUP_READ_VEC,
     S_READ_VEC,
     S_WAIT_COMPUTE,
     S_SETUP_WRITE,
     S_WRITE_OUT
   } state_t;
   state_t state;
//   state_t next_state;

   wire [MAT_VAL_BITS-1:0] mat_val_din;
   wire [COL_ID_BITS-1:0] col_id_din;
   wire [ROW_ID_BITS-1:0] row_id_din;
   wire mat_val_wren, col_id_wren, row_id_wren;
   wire [MAT_VAL_ADDR_WIDTH-1:0] mat_val_addr_ext;
   wire [COL_ID_ADDR_WIDTH-1:0] col_id_addr_ext;
   wire [ROW_ID_ADDR_WIDTH-1:0] row_id_addr_ext;

   wire [NUM_VEC_VALS_PER_ADDR*VEC_VAL_BITS-1:0] vector_din;
   wire vector_wren;
   wire [BVB_AWIDTH-1:0] vector_addr_ext;
   // FSM control registers
   //reg [7:0] beat_ctr;
   reg [7:0] vec_count;
   reg [ROW_ID_BITS-1:0] res_count;
   reg [MAT_VAL_ADDR_WIDTH-1:0] mat_count;
   reg [31:0] spmv_nnz;
   reg stall_fetcher;
   wire wr_en;
   reg [ROW_ID_BITS-1:0] wr_addr_ext;
   reg dma_write_chnl_ready_write_out;

//   wire dma_write_chnl_data;
   
   //reg dma_read_ctrl_valid;
   //reg dma_write_ctrl_valid_reg;
   
   // For this integration, use lower 8 bits of configuration inputs
   // prog_num_instr_beats = conf_info_spmv_nnz[7:0]
   // beats_per_pass = conf_info_spmv_vec_len[7:0]

   assign debug                = 32'd0;

   assign dma_write_chnl_data = {48'd0, spmv_dout};

   assign mat_val_wren = (state == S_READ_MAT) && dma_read_chnl_valid;
   assign col_id_wren = (state == S_READ_MAT) && dma_read_chnl_valid;
   assign row_id_wren = (state == S_READ_MAT) && dma_read_chnl_valid;
   assign vector_wren = (state == S_READ_VEC) && dma_read_chnl_valid;

   assign mat_val_din = dma_read_chnl_data[7:0];
   assign col_id_din = dma_read_chnl_data[15:8];
   assign row_id_din = dma_read_chnl_data[23:16];
   assign vector_din = dma_read_chnl_data[7:0];

   assign mat_val_addr_ext = mat_count;
   assign col_id_addr_ext = mat_count;
   assign row_id_addr_ext = mat_count;
   assign vector_addr_ext = vec_count;

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      state <= S_IDLE;
      acc_done <= 1'b0;
      dma_read_ctrl_valid <= 1'b0;
      dma_read_ctrl_data_index <= '0;
      dma_read_ctrl_data_length <= '0;
      dma_read_ctrl_data_size <= 3'd3;
      dma_read_chnl_ready <= 1'b0;

      dma_write_ctrl_valid <= 1'b0;
      dma_write_ctrl_data_index <= '0;
      dma_write_ctrl_data_length <= '0;
      dma_write_ctrl_data_size <= 3'd3;
//      dma_write_chnl_data <= '0;
      dma_write_chnl_valid <= 1'b0;

//      mat_val_din <= 0;
//      col_id_din <= 0;
//      row_id_din <= 0;
//      mat_val_wren <= 0;
//      col_id_wren <= 0;
//      row_id_wren <= 0;
//      mat_val_addr_ext <= 0;
//      col_id_addr_ext <= 0;
//      row_id_addr_ext <= 0;
      
//      vector_din <= 0;
//      vector_wren <= 0;
//      vector_addr_ext <= 0;

      mat_count <= '0;
      vec_count <= '0;
      res_count <= '0;

      stall_fetcher <= 1;
      spmv_nnz <= 0;
      wr_addr_ext <= '0;

    end else begin
      dma_read_ctrl_valid <= 1'b0;
      dma_write_ctrl_valid <= 1'b0;
      dma_read_chnl_ready <= 1'b0;
      dma_write_chnl_valid <= 1'b0;
      acc_done <= 1'b0;

      case (state)
        S_IDLE: begin
          mat_count <= '0;
          vec_count <= '0;
          res_count <= '0;
          if (conf_done) begin
            state <= S_SETUP_READ_MAT;
            spmv_nnz <= conf_info_spmv_nnz - 1;
          end
        end
        S_SETUP_READ_MAT: begin
          dma_read_ctrl_valid <= 1'b1;
          dma_read_ctrl_data_index <= '0;
          dma_read_ctrl_data_length <= conf_info_spmv_nnz;
          dma_read_ctrl_data_size <= 3'd3; // 64 bits
          if (dma_read_ctrl_ready) begin
            state <= S_READ_MAT;
            dma_read_ctrl_valid <= 1'b0;
          end
        end
        S_READ_MAT: begin
          dma_read_chnl_ready <= 1'b1;
          if (dma_read_chnl_valid) begin
//            mat_val_din <= dma_read_chnl_data[7:0];
//            col_id_din <= dma_read_chnl_data[15:8];
//            row_id_din <= dma_read_chnl_data[23:16];

//            mat_val_wren <= 1'b1;
//            col_id_wren <= 1'b1;
//            row_id_wren <= 1'b1;

//            mat_val_addr_ext <= mat_count;
//            col_id_addr_ext <= mat_count;
//            row_id_addr_ext <= mat_count;

            if (mat_count == spmv_nnz[11:0]) begin
              mat_count <= '0;
              state <= S_SETUP_READ_VEC;
              dma_read_chnl_ready <= 1'b0;
//              mat_val_wren <= 1'b0;
//              col_id_wren <= 1'b0;
//              row_id_wren <= 1'b0;
            end else begin
              mat_count <= mat_count + 1;
            end
          end
        end
        S_SETUP_READ_VEC: begin
          dma_read_ctrl_valid <= 1'b1;
          dma_read_ctrl_data_index <= conf_info_spmv_nnz; // example start address
          dma_read_ctrl_data_length <= conf_info_spmv_vec_len;
          dma_read_ctrl_data_size <= 3'd3;
          if (dma_read_ctrl_ready) begin
            state <= S_READ_VEC;
            dma_read_ctrl_valid <= 1'b0;
          end
        end
        S_READ_VEC: begin
          dma_read_chnl_ready <= 1'b1;
          if (dma_read_chnl_valid) begin
//            vector_din <= dma_read_chnl_data[7:0];
//            vector_wren <= 1'b1;
//            vector_addr_ext <= vec_count;
            if (vec_count == (conf_info_spmv_vec_len-1)) begin
              vec_count <= '0;
              state <=S_WAIT_COMPUTE;
//              vector_wren <= 1'b0;
              dma_read_chnl_ready <= 1'b0;
              //stall_fetcher <= 1'b0;
            end else begin
              vec_count <= vec_count + 1;
            end
          end
        end
        S_WAIT_COMPUTE: begin
          stall_fetcher <= 1'b0;
          if (spmv_done) begin
            state <= S_SETUP_WRITE;
            stall_fetcher <= 1'b1;
          end
        end
        S_SETUP_WRITE: begin
          dma_write_ctrl_valid <= 1'b1;
          dma_write_ctrl_data_index <= conf_info_spmv_nnz + conf_info_spmv_vec_len;
          dma_write_ctrl_data_length <= conf_info_spmv_vec_len;
          dma_write_ctrl_data_size <= 3'd3;
          if (dma_write_ctrl_ready) begin
            state <= S_WRITE_OUT;
            dma_write_ctrl_valid <= 1'b0;
          end
        end
        S_WRITE_OUT: begin
          dma_write_chnl_valid <= 1'b0;
//          dma_write_chnl_data <= '0;

          if (dma_write_chnl_ready) begin
            dma_write_chnl_valid <= 1'b1;
//            dma_write_chnl_data <= {48'd0, spmv_dout};

            if (res_count == conf_info_spmv_vec_len) begin
              state <= S_IDLE;
              dma_write_chnl_valid <= 1'b0;
              acc_done <= 1'b1;
              res_count <= '0;
            end else begin
              res_count <= res_count + 1;
            end
          end
        end
      endcase
    end
  end
//          if (dma_write_chnl_ready) begin //instead of ~wr_en, need to be when the data is valid...
//            if (!data_stored && wr_en) begin
//              data_stored <= 1'b1;
//            end 
//            if (data_stored) begin
//              
//            dma_write_chnl_valid <= 1'b1;
//            //dma_write_chnl_data <= {48'b0, spmv_dout};
//            if (res_count == (conf_info_spmv_vec_len - 1)) begin
//              res_count <= '0;
//              state <= S_IDLE;
//              dma_write_chnl_valid <= 1'b0;
//              //dma_write_chnl_data <= '0;
//              acc_done <= 1'b1;
//            end else begin
//              res_count <= res_count + 1;
//            end
//          end else begin
//            //dma_write_chnl_data <= '0;
//            dma_write_chnl_valid <= 1'b0;
//          end
//        end
//      endcase
//    end
//  end

//  assign dma_write_chnl_data = {48'b0, spmv_dout};
  assign dma_write_chnl_ready_write_out = (state == S_WRITE_OUT) & dma_write_chnl_ready;
   // Instantiate the spmv top module.
   // Note: The spmv module's internal done signal is unused as FSM controls completion.
   spmv spmv_inst (
       .clk(clk),
       .rst(!rst),
       .dout(spmv_dout),
       .done_reg(spmv_done), 
       .mat_val_din(mat_val_din),
       .col_id_din(col_id_din),
       .row_id_din(row_id_din),
       .mat_val_wren(mat_val_wren),
       .col_id_wren(col_id_wren),
       .row_id_wren(row_id_wren),
       .mat_val_addr_ext(mat_val_addr_ext),
       .col_id_addr_ext(col_id_addr_ext),
       .row_id_addr_ext(row_id_addr_ext),
       .vector_din(vector_din),
       .vector_wren(vector_wren),
       .vector_addr_ext(vector_addr_ext),
       .stall_fetcher(stall_fetcher),
       .spmv_nnz(spmv_nnz),
       .wr_addr_ext(res_count),
       .dma_write_chnl_ready_write_out(dma_write_chnl_ready_write_out),
       .wr_en(wr_en)
   );

endmodule
