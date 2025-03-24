module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 32
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n           
);
  wire ap_start;
  wire ap_done;
  wire ap_idle;
  wire r_permit;
  wire [(pADDR_WIDTH-1):0] address_reg;  
  wire sstlast_reg;
  wire [5:0] fir_data_count;
  wire [(pDATA_WIDTH-1):0] tap_num_reg;
  wire [(pDATA_WIDTH-1):0] data_len_reg;

  tap #(
    .pADDR_WIDTH(pADDR_WIDTH),
    .pDATA_WIDTH(pDATA_WIDTH),
    .Tape_Num(Tape_Num)
  ) u_tap (
    .awready(awready),
    .wready(wready),
    .awvalid(awvalid),
    .awaddr(awaddr),
    .wvalid(wvalid),
    .wdata(wdata),
    .arready(arready),
    .rready(rready),
    .arvalid(arvalid),
    .araddr(araddr),
    .rvalid(rvalid),
    .rdata(rdata),
    .tap_WE(tap_WE),
    .tap_EN(tap_EN),
    .tap_Di(tap_Di), 
    .tap_A(tap_A), 
    .tap_Do(tap_Do),
    .axis_clk(axis_clk),
    .axis_rst_n(axis_rst_n),
    .ap_start(ap_start), 
    .ap_done(ap_done),
    .ap_idle(ap_idle),
    .r_permit(r_permit),
    .address_reg(address_reg), 
    .fir_data_count(fir_data_count),
    .tap_num_reg(tap_num_reg),
    .data_len_reg(data_len_reg)
  );

  data #(
    .pADDR_WIDTH(pADDR_WIDTH),
    .pDATA_WIDTH(pDATA_WIDTH),
    .Tape_Num(Tape_Num)
) u_data (
    .ss_tvalid     (ss_tvalid), 
    .ss_tdata      (ss_tdata), 
    .ss_tlast      (ss_tlast), 
    .ss_tready     (ss_tready), 
    .sm_tready     (sm_tready), 
    .sm_tvalid     (sm_tvalid), 
    .sm_tdata      (sm_tdata), 
    .sm_tlast      (sm_tlast),
    .data_WE       (data_WE),
    .data_EN       (data_EN),
    .data_Di       (data_Di),
    .data_A        (data_A),
    .data_Do       (data_Do),
    .axis_clk      (axis_clk),
    .axis_rst_n    (axis_rst_n),
    .ap_start      (ap_start),
    .tap_Do        (tap_Do),
    .sstlast_reg   (sstlast_reg),
    .fir_data_count(fir_data_count),
    .tap_num_reg(tap_num_reg),
    .data_len_reg(data_len_reg)
);

/////////////////////////////////////////////////////////////////////////////////////////
//                                    AP FSM                                           //
/////////////////////////////////////////////////////////////////////////////////////////

  reg [1:0] state_ap;
  reg [1:0] next_state_ap;

  // state_ap
  localparam IDLE_AP = 2'b00;
  localparam CAL_AP = 2'b01;
  localparam DONE_AP = 2'b10; 

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      state_ap <= IDLE_AP;
    end else begin
      state_ap <= next_state_ap;
    end
  end

  always @(*) begin
    case (state_ap)
      IDLE_AP: begin
        if (ap_start) begin
          next_state_ap = CAL_AP;
        end else begin
          next_state_ap = IDLE_AP;
        end
      end
      CAL_AP: begin
        if (sm_tvalid & sm_tready & sstlast_reg) begin 
          next_state_ap = DONE_AP;
        end else begin
          next_state_ap = CAL_AP;
        end
      end
      DONE_AP: begin
        if (r_permit & (address_reg == 12'h0) & arready) begin
          next_state_ap = IDLE_AP;
        end else begin
          next_state_ap = DONE_AP;
        end
      end
      default: begin
        next_state_ap = IDLE_AP;
      end
    endcase
  end
  assign ap_done = (state_ap == DONE_AP);
  assign ap_idle = (state_ap != CAL_AP);
endmodule

module data #(
  parameter pADDR_WIDTH = 12,
  parameter pDATA_WIDTH = 32,
  parameter Tape_Num    = 32
) (
  input   wire                     ss_tvalid, 
  input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
  input   wire                     ss_tlast, 
  output  wire                     ss_tready, 
  input   wire                     sm_tready, 
  output  reg                     sm_tvalid, 
  output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
  output  wire                     sm_tlast,
  output  wire [3:0]               data_WE,
  output  wire                     data_EN,
  output  wire [(pDATA_WIDTH-1):0] data_Di,
  output  wire [(pADDR_WIDTH-1):0] data_A,
  input   wire [(pDATA_WIDTH-1):0] data_Do,
  input   wire                     axis_clk,
  input   wire                     axis_rst_n,
  input   wire                     ap_start,
  input   wire [(pDATA_WIDTH-1):0] tap_Do,
  output  wire                      sstlast_reg,
  output  reg  [5:0]               fir_data_count,
  input   wire [(pDATA_WIDTH-1):0] data_len_reg,
  input   wire [(pDATA_WIDTH-1):0] tap_num_reg          
);
  reg [5:0] total_num_data; 
  reg [5:0] data_addr_gen; 
  
  reg [5:0] next_sstdata_addr;
  reg ss_tready_reg;

  wire [5:0] base_addr;
  wire [5:0] tape_num;
  wire [5:0] this_round_num;

  reg [1:0] state;
  reg [1:0] next_state;
  reg [31:0] countdown;

  reg [(pDATA_WIDTH-1):0] tap_tmp;
  reg [(pDATA_WIDTH-1):0] data_tmp;
  wire [(pDATA_WIDTH-1):0] Multi_tmp;
  reg [(pDATA_WIDTH-1):0] Multi_tmp_reg;
  wire [(pDATA_WIDTH-1):0] y_tmp; 
  reg [(pDATA_WIDTH-1):0] y_tmp_reg;
  reg [(pDATA_WIDTH-1):0] sm_tdata_reg;
  
  // state for data
  localparam IDLE = 2'b00;
  localparam TRAN = 2'b01;
  localparam FIR = 2'b10;

  //////////////////////////////////////////////////////////////////////////
  //                   base address and data counter                      //
  //////////////////////////////////////////////////////////////////////////

  wire [5:0] total_num_data_tmp;
  assign total_num_data_tmp = (state == IDLE) ? 0 : (total_num_data == tape_num ? total_num_data : (ss_tready) ? (total_num_data + 1) : total_num_data);

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      total_num_data <= 0;
    end else begin
      total_num_data <= total_num_data_tmp;
    end
  end
  
  // Countdown is a register used to determine when y_reg should be read out.
  wire [31:0] countdown_tmp;
  assign countdown_tmp = (state != FIR) ? 32'hffffffff : ((fir_data_count == this_round_num) ? 3 : countdown - 1);
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      countdown <= 32'hffffffff;
    end else begin
      countdown <= countdown_tmp;
    end
  end


  // fir_data_count is a register that counts how many data have been processed.
  wire [5:0] fir_data_count_tmp;
  assign fir_data_count_tmp = (state == FIR) ? fir_data_count + 1 : 0;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      fir_data_count <= 0;
    end else begin
      fir_data_count <= fir_data_count_tmp;
    end
  end


  // next_sstdata_addr is a register used to indicate the storage address of the next data
  reg [5:0] next_sstdata_addr_tmp;
  always @(*) begin
    if (state == IDLE) begin
      next_sstdata_addr_tmp = 0;
    end else if ((state == FIR) & ss_tready) begin
      if (next_sstdata_addr == tape_num) begin
        next_sstdata_addr_tmp = 0;
      end else begin
        next_sstdata_addr_tmp = next_sstdata_addr + 1;
      end
    end else begin
      next_sstdata_addr_tmp = next_sstdata_addr;
    end
  end

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      next_sstdata_addr <= 0;
    end else begin
      next_sstdata_addr <= next_sstdata_addr_tmp;
    end
  end

  reg [5:0] base_addr_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      base_addr_prev <= 0;
    end else begin
      base_addr_prev <= base_addr;
    end
  end

  reg [5:0] this_round_num_prev;
  always @(posedge axis_clk) begin
    this_round_num_prev <= this_round_num;
  end

  /////////////////////////////////////////////////////////////////////////
  //                        Main Data Flow                               //
  /////////////////////////////////////////////////////////////////////////
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      data_tmp <= 0;
    end else begin
      data_tmp <= data_Do;
    end
  end

  always @(posedge axis_clk or negedge axis_rst_n) begin
     if (~axis_rst_n) begin
      tap_tmp <= 0;
    end else begin
      tap_tmp <= tap_Do;
    end
  end
 
  assign Multi_tmp = data_tmp * tap_tmp;

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      Multi_tmp_reg <= 0;
    end else begin
      Multi_tmp_reg <= Multi_tmp;
    end
  end

  assign y_tmp = Multi_tmp_reg + y_tmp_reg;

  always @(posedge axis_clk) begin
    if (fir_data_count == 2) begin
      y_tmp_reg <= 0;
    end else begin
      y_tmp_reg <= y_tmp;
    end
  end

  //////////////////////////////////////////////////////////////////////////
  //                          axi-stream                                  //
  //////////////////////////////////////////////////////////////////////////
  reg [(pDATA_WIDTH-1):0] sm_tdata_reg_prev;
  reg sm_tvalid_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      sm_tdata_reg_prev <= 0;
      sm_tvalid_prev <= 0;
    end else begin
      sm_tdata_reg_prev <= sm_tdata_reg;
      sm_tvalid_prev <= sm_tvalid;
    end
  end

  // sm_tvalid is asserted when a complete y value has been calculated
  // sm_tdata also outputs the corresponding y value at that time for sm to read
  always @(*) begin 
    if (state != FIR) begin
      sm_tvalid = 0;
      sm_tdata_reg = 0;
    end else if (countdown == 0) begin
      sm_tvalid = 1;
      sm_tdata_reg = y_tmp_reg;
    end else begin
      sm_tvalid = sm_tvalid_prev;
      sm_tdata_reg = sm_tdata_reg_prev;
    end
  end
  
  // ss_tready is used to check if ss_tvalid is high and the current state is ready to receive new data
  wire ss_tready_reg_tmp;
  assign ss_tready_reg_tmp = (state == TRAN) & ss_tvalid;
  always @(posedge axis_clk) begin
    ss_tready_reg <= ss_tready_reg_tmp;
  end

  assign sm_tdata = sm_tdata_reg;
  assign sm_tlast = (sm_tvalid) & (sstlast_reg);
  assign ss_tready = (state == IDLE) ? 0 : ss_tready_reg;
  assign data_EN = (state != IDLE);
  assign data_WE = {4{ss_tready}};
  assign data_A = {4'b0, data_addr_gen, 2'b0};
  assign data_Di = ss_tdata;
  assign base_addr = (state == TRAN) ? next_sstdata_addr : base_addr_prev; 
  assign tape_num = (tap_num_reg - 1) & 6'b111111;
  assign this_round_num = ((state == TRAN) & (ss_tvalid)) ? total_num_data : this_round_num_prev;

  ////////////////////////////////////////////////////////////////////////////
  //                          Data FSM                                      //
  ////////////////////////////////////////////////////////////////////////////

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end
  
  
  always @(*) begin
    case (state)
      IDLE: begin
        if (ap_start) begin
          next_state = TRAN;
        end else begin
          next_state = IDLE;
        end
      end
      TRAN: begin
        if (ss_tvalid) begin
          next_state = FIR;
        end else begin
          next_state = TRAN;
        end
      end
      FIR: begin
        if (sm_tvalid & sm_tready) begin
          if (sstlast_reg) begin
            next_state = IDLE;
          end else begin
            next_state = TRAN;
          end
        end else begin
          next_state = FIR;
        end
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  ///////////////////////////////////////////////////////////////////////////////
  //                     Data_ram Address Generator                            //
  ///////////////////////////////////////////////////////////////////////////////

  always @(*) begin
    case (state)
      TRAN: begin
        data_addr_gen = base_addr;
      end
      FIR: begin
        data_addr_gen = (base_addr >= fir_data_count) ? (base_addr - fir_data_count) : (tap_num_reg + base_addr - fir_data_count);
      end
      default: begin
        data_addr_gen = 0;
      end
    endcase
  end

  ////////////////////////////////////////////////////////////////////////////////
  //                       Last Data Register                                   //
  ////////////////////////////////////////////////////////////////////////////////

  reg sstlast_reg_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      sstlast_reg_prev <= 0;
    end else begin
      sstlast_reg_prev <= sstlast_reg;
    end
  end

  assign sstlast_reg = (state == TRAN) ? (ss_tvalid & ss_tlast) : ((state == IDLE) ? 0 : sstlast_reg_prev);
endmodule

module tap #(
  parameter pADDR_WIDTH = 12,
  parameter pDATA_WIDTH = 32,
  parameter Tape_Num    = 32
) (
  output  wire                     awready,
  output  wire                     wready,
  input   wire                     awvalid,
  input   wire [(pADDR_WIDTH-1):0] awaddr,
  input   wire                     wvalid,
  input   wire [(pDATA_WIDTH-1):0] wdata,
  output  wire                     arready,
  input   wire                     rready,
  input   wire                     arvalid,
  input   wire [(pADDR_WIDTH-1):0] araddr,
  output  wire                     rvalid,
  output  wire [(pDATA_WIDTH-1):0] rdata,
  output  wire  [3:0]               tap_WE,
  output  wire                      tap_EN,
  output  wire  [(pDATA_WIDTH-1):0] tap_Di,
  output  wire  [(pADDR_WIDTH-1):0] tap_A,
  input   wire [(pDATA_WIDTH-1):0] tap_Do,
  input   wire                     axis_clk,
  input   wire                     axis_rst_n, 
  output  wire                      ap_start,
  input   wire                     ap_done,
  input   wire                     ap_idle,
  output  wire                     r_permit,
  output  reg  [(pADDR_WIDTH-1):0] address_reg,
  input   wire [5:0]               fir_data_count,
  output  wire  [(pDATA_WIDTH-1):0] tap_num_reg,
  output  wire  [(pDATA_WIDTH-1):0] data_len_reg
);

  // localparam for state
  localparam IDLE = 2'b00; // Initial
  localparam TRAN = 2'b01; // Write or Read Tap, data_len, Tap_num
  localparam WAIT = 2'b10; 
  localparam FIR = 2'b11; // do FIR
 
  wire [(pDATA_WIDTH-1):0] ap_crtl; 
  wire w_permit;                
  reg [(pDATA_WIDTH-1):0] data_reg;
  reg [(pDATA_WIDTH-1):0] read_data_reg;
  reg rvalid_reg;
  wire writing;
  wire fir_read;
  reg fir_read_d1;
  reg [1:0] state;
  reg [1:0] next_state;
  reg rvaild_down;
  wire rvalid_tmp;
  wire axis_clk_n;

  assign writing = awvalid & wvalid;
  assign w_permit = writing & (state == TRAN);
  assign r_permit = arvalid & (state != IDLE);
  assign rvalid = (arready ? 1 : (rvaild_down ? 0 : rvalid_reg));
  assign arready = (~(writing) & arvalid) & (state == WAIT | fir_read_d1);
  assign ap_crtl = {29'b0, ap_idle, ap_done, ap_start};
  assign rdata = read_data_reg;
  assign awready = writing & ((state == WAIT) | (state == FIR));
  assign wready = writing & ((state == WAIT) | (state == FIR));
  assign fir_read = (state == FIR) & arvalid; 

  // fir_read indicates whether the current read operation is in the FIR state
  always @(posedge axis_clk) begin
    fir_read_d1 <= fir_read; 
  end

  ///////////////////////////////////////////////////////////////////////////////
  //                                Tap FSM                                    //
  ///////////////////////////////////////////////////////////////////////////////

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

   always @(*) begin
    case (state)
      IDLE: begin
        next_state <= TRAN;        
      end
      TRAN: begin
        if (w_permit | r_permit) begin
          next_state <= WAIT;
        end else begin
          next_state <= TRAN;
        end
      end
      WAIT: begin
        if (ap_start) begin
          next_state <= FIR;
        end else begin
          next_state <= TRAN;
        end
      end
      FIR: begin
        if (ap_done) begin
          next_state <= TRAN;
        end else begin
          next_state <= FIR;
        end
      end
      default: begin
        next_state <= IDLE;
      end 
    endcase
  end

///////////////////////////////////////////////////////////////////////////////////
//                               axi-lite                                        //
///////////////////////////////////////////////////////////////////////////////////
  
  // rvalid_down is used to indicate when rvalid should be deasserted
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      rvaild_down <= 0;  
    end else if (rvalid & rready) begin
      rvaild_down <= 1;
    end else begin
      rvaild_down <= 0;
    end
  end

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      rvalid_reg <= 0;
    end else begin
      rvalid_reg <= rvalid;
    end
  end
  
  reg [(pADDR_WIDTH-1):0] address_reg_prev;
  reg [(pDATA_WIDTH-1):0] data_reg_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      address_reg_prev <= address_reg;
      data_reg_prev <= data_reg;
    end else begin
      address_reg_prev <= address_reg;
      data_reg_prev <= data_reg;
    end
  end
 
  // address_reg is a register used to store the input address from AXI-Lite, and data_reg is also a register used to store the input data from AXI-Lite
  always @(*) begin
    case (state)
      IDLE: begin
        address_reg = 0;
        data_reg = 0;
      end 
      TRAN: begin
        if (awvalid) begin
          address_reg = awaddr;
        end else if (arvalid) begin
          address_reg = araddr;
        end else begin
          address_reg = address_reg_prev;
        end
        if (wvalid) begin
          data_reg = wdata;
        end else begin
          data_reg = data_reg_prev;
        end 
      end
      WAIT: begin
        address_reg = address_reg_prev;
        data_reg = data_reg_prev;
      end
      FIR: begin
        if (arvalid) begin
          address_reg = araddr;
        end else begin
          address_reg = address_reg_prev;
        end
        data_reg = data_reg_prev;
      end
      default: begin
        address_reg = 0;
        data_reg = 0;
      end
    endcase
  end

  reg [(pADDR_WIDTH-1):0] tap_A_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      tap_A_prev <= 0;
    end else begin
      tap_A_prev <= tap_A;
    end
  end
  
  // In the FIR state, tap_A generates the corresponding address based on the number of data items currently being processed. In the AXI-Lite read/write state, it generates the address based on the input address from AXI-Lite
  assign tap_A = (state == FIR) ? {4'b0, fir_data_count, 2'b0} : (((w_permit | r_permit) & (address_reg[7] & (address_reg[11:8] == 0))) ? {5'b0, address_reg[6:2], 2'b0} : tap_A_prev);
  assign tap_WE = {4{(state == TRAN) & (awaddr[7] & (awaddr[11:8] == 0))}};
  assign tap_EN = (state != IDLE);

  reg ap_start_prev;
  reg [(pDATA_WIDTH-1):0] data_len_reg_prev;
  reg [(pDATA_WIDTH-1):0] tap_Di_prev;
  reg [(pDATA_WIDTH-1):0] tap_num_reg_prev;

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      ap_start_prev <= 0;
      data_len_reg_prev <= 0;
      tap_num_reg_prev <= 0;
      tap_Di_prev <= 0;
    end else begin
      ap_start_prev <= ap_start;
      data_len_reg_prev <= data_len_reg;
      tap_num_reg_prev <= tap_num_reg;
      tap_Di_prev <= tap_Di;
    end
  end
  // The following four registers perform a write operation when the address matches their corresponding address
  assign ap_start = (w_permit & (address_reg == 12'h0)) ? data_reg : ((state == FIR) ? 0 : ap_start_prev); 
  assign data_len_reg = (w_permit & (address_reg == 12'h10)) ? data_reg : data_len_reg_prev;
  assign tap_num_reg = (w_permit & (address_reg == 12'h14)) ? data_reg : tap_num_reg_prev;
  assign tap_Di = (w_permit & (address_reg[7] & (address_reg[11:8] == 0))) ? data_reg : tap_Di_prev;

  reg [(pDATA_WIDTH-1):0] read_data_reg_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      read_data_reg_prev <= 0;
    end else begin
      read_data_reg_prev <= read_data_reg;
    end
  end

  // read_data_reg is a register used to temporarily store the data to be read via AXI-Lite
  always @(*) begin
    if (r_permit) begin
      if (address_reg == 12'h0) begin
        read_data_reg = ap_crtl;
      end else if (address_reg == 12'h10) begin
        read_data_reg = data_len_reg;
      end else if (address_reg == 12'h14) begin
        read_data_reg = tap_num_reg;
      end else if ((address_reg[7] & (address_reg[11:8] == 0)) & state != FIR) begin
        read_data_reg = tap_Do;
      end else begin
        read_data_reg = 32'hffffffff;
      end
    end else begin
      read_data_reg = read_data_reg_prev;
    end
  end
endmodule