//////////////////////////////////////////////////////////////////////////////////
// fft_64_rtl_basic_dma64.v
// Wrapper for integrating the fft_64 accelerator with DMA control FSM.
// The FSM follows the control flow transitions as specified in the reference diagram.
//////////////////////////////////////////////////////////////////////////////////
module fft_64_rtl_basic_dma64(
    clk, rst, 
    dma_read_chnl_valid, dma_read_chnl_data, dma_read_chnl_ready,
    conf_info_fft_points, conf_done, acc_done,
    debug, 
    dma_read_ctrl_valid, dma_read_ctrl_data_index,
    dma_read_ctrl_data_length, dma_read_ctrl_data_size, dma_read_ctrl_ready,
    dma_write_ctrl_valid, dma_write_ctrl_data_index,
    dma_write_ctrl_data_length, dma_write_ctrl_data_size, dma_write_ctrl_ready,
    dma_write_chnl_valid, dma_write_chnl_data, dma_write_chnl_ready
);

    input              clk;
    input              rst;
    
    input [31:0]       conf_info_fft_points;
    input              conf_done;
    
    input              dma_read_ctrl_ready;
    output reg         dma_read_ctrl_valid;
    output reg [31:0]  dma_read_ctrl_data_index;
    output reg [31:0]  dma_read_ctrl_data_length;
    output reg [2:0]   dma_read_ctrl_data_size;
    
    output reg         dma_read_chnl_ready;
    input              dma_read_chnl_valid;
    input [63:0]       dma_read_chnl_data;
    
    input              dma_write_ctrl_ready;
    output reg         dma_write_ctrl_valid;
    output reg [31:0]  dma_write_ctrl_data_index;
    output reg [31:0]  dma_write_ctrl_data_length;
    output reg [2:0]   dma_write_ctrl_data_size;
    
    input              dma_write_chnl_ready;
    output reg         dma_write_chnl_valid;
    output reg [63:0]  dma_write_chnl_data;
    
    output reg         acc_done;
    output reg [31:0]  debug;
    
    // DMA States
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_READ_CTRL  = 3'd1;
    localparam STATE_READ_DATA  = 3'd2;
    localparam STATE_WAIT_FFT   = 3'd3;
    localparam STATE_WRITE_CTRL = 3'd4;
    localparam STATE_WRITE_DATA = 3'd5;
    
    // Parameter values
    localparam PROG_NUM_INSTR_BEATS = 16;  
    localparam BEATS_PER_PASS       = 64;
    localparam VALS_PER_BEAT        = 1;
    
    reg [2:0] state;
    reg [31:0] beat_ctr;
    reg pgm_read;       // Indicates if program read is enabled
    reg configured;     // Becomes true when conf_done is asserted
    
    // Arrays for FFT input data; each sample is 12 bits.
    reg [11:0] fft_data_real [0:63];
    reg [11:0] fft_data_imag [0:63];
    
    // Wires to capture FFT output.
    wire [11:0] fft_data_out_real [0:63];
    wire [11:0] fft_data_out_imag [0:63];
    
    integer i;
    
    //-------------------------------------------------------------------------
    // Instantiate the fft_64 accelerator top module
    //-------------------------------------------------------------------------
    fft_64 fft_instance (
        .i0(  fft_data_real[0]),  .i1(  fft_data_real[1]),  .i2(  fft_data_real[2]),  .i3(  fft_data_real[3]),
        .i4(  fft_data_real[4]),  .i5(  fft_data_real[5]),  .i6(  fft_data_real[6]),  .i7(  fft_data_real[7]),
        .i8(  fft_data_real[8]),  .i9(  fft_data_real[9]),  .i10( fft_data_real[10]), .i11( fft_data_real[11]),
        .i12( fft_data_real[12]), .i13( fft_data_real[13]), .i14( fft_data_real[14]), .i15( fft_data_real[15]),
        .i16( fft_data_real[16]), .i17( fft_data_real[17]), .i18( fft_data_real[18]), .i19( fft_data_real[19]),
        .i20( fft_data_real[20]), .i21( fft_data_real[21]), .i22( fft_data_real[22]), .i23( fft_data_real[23]),
        .i24( fft_data_real[24]), .i25( fft_data_real[25]), .i26( fft_data_real[26]), .i27( fft_data_real[27]),
        .i28( fft_data_real[28]), .i29( fft_data_real[29]), .i30( fft_data_real[30]), .i31( fft_data_real[31]),
        .i32( fft_data_real[32]), .i33( fft_data_real[33]), .i34( fft_data_real[34]), .i35( fft_data_real[35]),
        .i36( fft_data_real[36]), .i37( fft_data_real[37]), .i38( fft_data_real[38]), .i39( fft_data_real[39]),
        .i40( fft_data_real[40]), .i41( fft_data_real[41]), .i42( fft_data_real[42]), .i43( fft_data_real[43]),
        .i44( fft_data_real[44]), .i45( fft_data_real[45]), .i46( fft_data_real[46]), .i47( fft_data_real[47]),
        .i48( fft_data_real[48]), .i49( fft_data_real[49]), .i50( fft_data_real[50]), .i51( fft_data_real[51]),
        .i52( fft_data_real[52]), .i53( fft_data_real[53]), .i54( fft_data_real[54]), .i55( fft_data_real[55]),
        .i56( fft_data_real[56]), .i57( fft_data_real[57]), .i58( fft_data_real[58]), .i59( fft_data_real[59]),
        .i60( fft_data_real[60]), .i61( fft_data_real[61]), .i62( fft_data_real[62]), .i63( fft_data_real[63]),
        
        .r0(  fft_data_imag[0]),  .r1(  fft_data_imag[1]),  .r2(  fft_data_imag[2]),  .r3(  fft_data_imag[3]),
        .r4(  fft_data_imag[4]),  .r5(  fft_data_imag[5]),  .r6(  fft_data_imag[6]),  .r7(  fft_data_imag[7]),
        .r8(  fft_data_imag[8]),  .r9(  fft_data_imag[9]),  .r10( fft_data_imag[10]), .r11( fft_data_imag[11]),
        .r12( fft_data_imag[12]), .r13( fft_data_imag[13]), .r14( fft_data_imag[14]), .r15( fft_data_imag[15]),
        .r16( fft_data_imag[16]), .r17( fft_data_imag[17]), .r18( fft_data_imag[18]), .r19( fft_data_imag[19]),
        .r20( fft_data_imag[20]), .r21( fft_data_imag[21]), .r22( fft_data_imag[22]), .r23( fft_data_imag[23]),
        .r24( fft_data_imag[24]), .r25( fft_data_imag[25]), .r26( fft_data_imag[26]), .r27( fft_data_imag[27]),
        .r28( fft_data_imag[28]), .r29( fft_data_imag[29]), .r30( fft_data_imag[30]), .r31( fft_data_imag[31]),
        .r32( fft_data_imag[32]), .r33( fft_data_imag[33]), .r34( fft_data_imag[34]), .r35( fft_data_imag[35]),
        .r36( fft_data_imag[36]), .r37( fft_data_imag[37]), .r38( fft_data_imag[38]), .r39( fft_data_imag[39]),
        .r40( fft_data_imag[40]), .r41( fft_data_imag[41]), .r42( fft_data_imag[42]), .r43( fft_data_imag[43]),
        .r44( fft_data_imag[44]), .r45( fft_data_imag[45]), .r46( fft_data_imag[46]), .r47( fft_data_imag[47]),
        .r48( fft_data_imag[48]), .r49( fft_data_imag[49]), .r50( fft_data_imag[50]), .r51( fft_data_imag[51]),
        .r52( fft_data_imag[52]), .r53( fft_data_imag[53]), .r54( fft_data_imag[54]), .r55( fft_data_imag[55]),
        .r56( fft_data_imag[56]), .r57( fft_data_imag[57]), .r58( fft_data_imag[58]), .r59( fft_data_imag[59]),
        .r60( fft_data_imag[60]), .r61( fft_data_imag[61]), .r62( fft_data_imag[62]), .r63( fft_data_imag[63]),
        
        .i_s_0( fft_data_out_real[0]), .i_s_1( fft_data_out_real[1]), .i_s_2( fft_data_out_real[2]),
        .i_s_3( fft_data_out_real[3]), .i_s_4( fft_data_out_real[4]), .i_s_5( fft_data_out_real[5]),
        .i_s_6( fft_data_out_real[6]), .i_s_7( fft_data_out_real[7]), .i_s_8( fft_data_out_real[8]),
        .i_s_9( fft_data_out_real[9]), .i_s_10(fft_data_out_real[10]),.i_s_11(fft_data_out_real[11]),
        .i_s_12(fft_data_out_real[12]),.i_s_13(fft_data_out_real[13]),.i_s_14(fft_data_out_real[14]),
        .i_s_15(fft_data_out_real[15]),.i_s_16(fft_data_out_real[16]),.i_s_17(fft_data_out_real[17]),
        .i_s_18(fft_data_out_real[18]),.i_s_19(fft_data_out_real[19]),.i_s_20(fft_data_out_real[20]),
        .i_s_21(fft_data_out_real[21]),.i_s_22(fft_data_out_real[22]),.i_s_23(fft_data_out_real[23]),
        .i_s_24(fft_data_out_real[24]),.i_s_25(fft_data_out_real[25]),.i_s_26(fft_data_out_real[26]),
        .i_s_27(fft_data_out_real[27]),.i_s_28(fft_data_out_real[28]),.i_s_29(fft_data_out_real[29]),
        .i_s_30(fft_data_out_real[30]),.i_s_31(fft_data_out_real[31]),.i_s_32(fft_data_out_real[32]),
        .i_s_33(fft_data_out_real[33]),.i_s_34(fft_data_out_real[34]),.i_s_35(fft_data_out_real[35]),
        .i_s_36(fft_data_out_real[36]),.i_s_37(fft_data_out_real[37]),.i_s_38(fft_data_out_real[38]),
        .i_s_39(fft_data_out_real[39]),.i_s_40(fft_data_out_real[40]),.i_s_41(fft_data_out_real[41]),
        .i_s_42(fft_data_out_real[42]),.i_s_43(fft_data_out_real[43]),.i_s_44(fft_data_out_real[44]),
        .i_s_45(fft_data_out_real[45]),.i_s_46(fft_data_out_real[46]),.i_s_47(fft_data_out_real[47]),
        .i_s_48(fft_data_out_real[48]),.i_s_49(fft_data_out_real[49]),.i_s_50(fft_data_out_real[50]),
        .i_s_51(fft_data_out_real[51]),.i_s_52(fft_data_out_real[52]),.i_s_53(fft_data_out_real[53]),
        .i_s_54(fft_data_out_real[54]),.i_s_55(fft_data_out_real[55]),.i_s_56(fft_data_out_real[56]),
        .i_s_57(fft_data_out_real[57]),.i_s_58(fft_data_out_real[58]),.i_s_59(fft_data_out_real[59]),
        .i_s_60(fft_data_out_real[60]),.i_s_61(fft_data_out_real[61]),.i_s_62(fft_data_out_real[62]),
        .i_s_63(fft_data_out_real[63]),
        
        .r_s_0( fft_data_out_imag[0]), .r_s_1( fft_data_out_imag[1]), .r_s_2( fft_data_out_imag[2]),
        .r_s_3( fft_data_out_imag[3]), .r_s_4( fft_data_out_imag[4]), .r_s_5( fft_data_out_imag[5]),
        .r_s_6( fft_data_out_imag[6]), .r_s_7( fft_data_out_imag[7]), .r_s_8( fft_data_out_imag[8]),
        .r_s_9( fft_data_out_imag[9]), .r_s_10(fft_data_out_imag[10]),.r_s_11(fft_data_out_imag[11]),
        .r_s_12(fft_data_out_imag[12]),.r_s_13(fft_data_out_imag[13]),.r_s_14(fft_data_out_imag[14]),
        .r_s_15(fft_data_out_imag[15]),.r_s_16(fft_data_out_imag[16]),.r_s_17(fft_data_out_imag[17]),
        .r_s_18(fft_data_out_imag[18]),.r_s_19(fft_data_out_imag[19]),.r_s_20(fft_data_out_imag[20]),
        .r_s_21(fft_data_out_imag[21]),.r_s_22(fft_data_out_imag[22]),.r_s_23(fft_data_out_imag[23]),
        .r_s_24(fft_data_out_imag[24]),.r_s_25(fft_data_out_imag[25]),.r_s_26(fft_data_out_imag[26]),
        .r_s_27(fft_data_out_imag[27]),.r_s_28(fft_data_out_imag[28]),.r_s_29(fft_data_out_imag[29]),
        .r_s_30(fft_data_out_imag[30]),.r_s_31(fft_data_out_imag[31]),.r_s_32(fft_data_out_imag[32]),
        .r_s_33(fft_data_out_imag[33]),.r_s_34(fft_data_out_imag[34]),.r_s_35(fft_data_out_imag[35]),
        .r_s_36(fft_data_out_imag[36]),.r_s_37(fft_data_out_imag[37]),.r_s_38(fft_data_out_imag[38]),
        .r_s_39(fft_data_out_imag[39]),.r_s_40(fft_data_out_imag[40]),.r_s_41(fft_data_out_imag[41]),
        .r_s_42(fft_data_out_imag[42]),.r_s_43(fft_data_out_imag[43]),.r_s_44(fft_data_out_imag[44]),
        .r_s_45(fft_data_out_imag[45]),.r_s_46(fft_data_out_imag[46]),.r_s_47(fft_data_out_imag[47]),
        .r_s_48(fft_data_out_imag[48]),.r_s_49(fft_data_out_imag[49]),.r_s_50(fft_data_out_imag[50]),
        .r_s_51(fft_data_out_imag[51]),.r_s_52(fft_data_out_imag[52]),.r_s_53(fft_data_out_imag[53]),
        .r_s_54(fft_data_out_imag[54]),.r_s_55(fft_data_out_imag[55]),.r_s_56(fft_data_out_imag[56]),
        .r_s_57(fft_data_out_imag[57]),.r_s_58(fft_data_out_imag[58]),.r_s_59(fft_data_out_imag[59]),
        .r_s_60(fft_data_out_imag[60]),.r_s_61(fft_data_out_imag[61]),.r_s_62(fft_data_out_imag[62]),
        .r_s_63(fft_data_out_imag[63])
    );
    
    //-------------------------------------------------------------------------
    // FSM for controlling DMA read, FFT processing, and DMA write.
    // The FSM transitions follow the provided control flow diagram.
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
      if (!rst) begin
         state                  <= STATE_IDLE;
         beat_ctr             <= 0;
         pgm_read             <= 1;   // Assume program read is active for FFT input.
         configured           <= 0;
         dma_read_ctrl_valid  <= 0;
         dma_write_ctrl_valid <= 0;
         dma_read_chnl_ready  <= 0;
         dma_write_chnl_valid <= 0;
         acc_done             <= 0;
         // Initialize FFT input arrays
         for(i = 0; i < 64; i = i + 1) begin
             fft_data_real[i] <= 0;
             fft_data_imag[i] <= 0;
         end
      end else begin
         case (state)
           STATE_IDLE: begin
              configured <= conf_done;
              if (configured && pgm_read) begin
                 dma_read_ctrl_valid <= 1; // Initiate DMA read control request.
                 dma_read_ctrl_data_index  <= 32'd0;
                 dma_read_ctrl_data_length <= 32'd64;
                 dma_read_ctrl_data_size   <= 3'd2;
                 beat_ctr <= 0;
                 state <= STATE_READ_CTRL;
              end
           end
           STATE_READ_CTRL: begin
              if (dma_read_ctrl_ready) begin
                 dma_read_ctrl_valid <= 0;
                 beat_ctr <= 0;
                 state <= STATE_READ_DATA;
              end
           end
           STATE_READ_DATA: begin
              dma_read_chnl_ready <= 1;
              if (dma_read_chnl_valid) begin
                 // Capture FFT input sample from DMA: real in bits[11:0], imag in bits[27:16]
                 fft_data_real[beat_ctr] <= dma_read_chnl_data[11:0];
                 fft_data_imag[beat_ctr] <= dma_read_chnl_data[27:16];
                 beat_ctr <= beat_ctr + 1;
              end
              if (beat_ctr == BEATS_PER_PASS) begin
                 dma_read_chnl_ready <= 0;
                 beat_ctr <= 0;
                 state <= STATE_WAIT_FFT;
              end
           end
           STATE_WAIT_FFT: begin
              // Assume FFT processing completes within one cycle.
              state <= STATE_WRITE_CTRL;
           end
           STATE_WRITE_CTRL: begin
              dma_write_ctrl_valid <= 1;
              dma_write_ctrl_data_index  <= 32'd0;
              dma_write_ctrl_data_length <= 32'd64;
              dma_write_ctrl_data_size   <= 3'd2;
              if (dma_write_ctrl_ready) begin
                 dma_write_ctrl_valid <= 0;
                 beat_ctr <= 0;
                 state <= STATE_WRITE_DATA;
              end
           end
           STATE_WRITE_DATA: begin
              
              // Pack FFT output: real in lower 12 bits, imag in bits[27:16]
              //add check for ready in handshake
              if (dma_write_chnl_ready) begin
               beat_ctr <= beat_ctr + 1;
               dma_write_chnl_data <= {44'd0, fft_data_out_imag[beat_ctr], fft_data_out_real[beat_ctr]};
                  
               if (beat_ctr == 0) begin
                  dma_write_chnl_valid <= 1;
               end
              end
              if (beat_ctr == BEATS_PER_PASS + 1) begin
                     dma_write_chnl_valid <= 0;
                     acc_done <= 1;
                        // state <= STATE_IDLE;
                  end
              // fix termination
           end
           default: state <= STATE_IDLE;
         endcase
      end
    end
    
    //-------------------------------------------------------------------------
    // Debug signal: output current FSM state in lower 3 bits.
    //-------------------------------------------------------------------------
    always @(*) begin
       debug = {29'd0, state};
    end

endmodule
