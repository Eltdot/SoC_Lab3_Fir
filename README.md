# Lab 3 Fir

[Code](https://github.com/Eltdot/SoC_Lab3_Fir)

## Introduction

[Workbook](https://drive.google.com/file/d/1PSqW4qURLvSZxRDxA4NAYPYXn8ixE6ib/view)


This design primarily implements a simple **convolution**:

$$
y[t] = \sum_{i = 0}^{\text{tap_num}-1} \left( h[i] \times x[t - i] \right)
$$

The main challenge lies in the fact that input and output data need to be transmitted via **AXI-Lite** and **AXI-Stream**, and **shift registers** cannot be used. The implementation must rely on only **32 DW of SRAM**, and the design allows for only one **32-bit adder** and one **32-bit multiplier**.




## Design Spec
- **Data_Width** 32bit (integer)
- **Tap_Num** max 32
  - **# of Tap is a programmable parameter**
  - Maximum storage of Tap and Data RAM is 32 DW
- **Data_Num** *programmable parameter* — Based on the size of the data file
- **Interface**
  - **axilite**: configuration data_in:
  - **axi-stream**: stream ( Xn ), stream ( Yn )

- **Using one Multiplier and one Adder:**
  - **Note**: Multiplication and Addition are run in separate pipeline cycle
  - **Note**: Don’t use DSP, use Xilinx directive `(* use_dsp = "no" *)`

- **Shift registers implemented with SRAM** ( Shift_RAM, size = 32 DW )
- **Tap coefficient implemented with SRAM** ( Tap_RAM = 32 DW ), initialized by axilite write

- **Operation** 
  1. Program `ap_start` to initiate FIR engine
  2. Stream in `Xn`. The rate is varied by testbench. `axi-stream` tvalid/tready for flow control.
  3. Stream out `Yn`, the rate of output transfer is varied by testbench. `axi-stream` tvalid/tready for flow control.
  
  
## AXI Transfer Protocal

### axi-lite write

![image](https://hackmd.io/_uploads/ryeJs3D4hye.png)
![image](https://hackmd.io/_uploads/rktdJdVh1g.png)


In this design, only `awvalid`, `wvalid`, `awready`, and `wready` are used. It is important to note that a **single arrow (`→`)** indicates that these signals are related but does not imply a strict ordering. In contrast, a **double arrow (`⇒`)** denotes a sequential dependency, meaning that the referenced signal must be received before the next signal can be asserted.

### axi-lite read

![image](https://hackmd.io/_uploads/rJTVaDVhye.png)
![image](https://hackmd.io/_uploads/HyBwJOEhyg.png)


Here, it is important to note that `RREADY` might only be asserted **after detecting** `RVALID`. Therefore, during the design process, care must be taken **not to use** `RREADY` as a condition for `RVALID`.

### axi-stream
  
![image](https://hackmd.io/_uploads/HksngON3ye.png)

In this case, `tvalid` and `tready` do not have a strict order of precedence. Therefore, in the design process, `tready` can be asserted **before or after** `tvalid` without any rigid constraints.

# Code Explanation

## FSM

### state_tap

```verilog
  reg [1:0] state;
  reg [1:0] next_state;  
  // localparam for state
  localparam IDLE = 2'b00; // Initial
  localparam TRAN = 2'b01; // Write or Read Tap, data_len, Tap_num
  localparam WAIT = 2'b10; 
  localparam FIR = 2'b11; // do FIR  

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // next_state update
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
```


`state_tap` is primarily responsible for managing **AXI-Lite** operations and consists of four states: **IDLE, TRAN, WAIT, and FIR**.

#### **IDLE**  
The system enters the `IDLE` state whenever it is reset or after completing a full round of FIR computation.  
In this state, the system does nothing, and in the next cycle, it transitions to the `TRAN` state.

#### **TRAN**  
The `TRAN` state is used for inputting various coefficients for `tap_number`.  
In this state, **read and write operations** can be performed.  
After receiving a read or write signal, the system transitions to the `WAIT` state.

#### **WAIT**  
The system enters the `WAIT` state after receiving a read or write signal in the `TRAN` state.  
In this state, the corresponding **ready signal** is asserted.  
If `ap_start` is asserted during this phase, the system transitions to the `FIR` state, where FIR computation begins.

#### **FIR**  
`FIR` is the state where the system performs FIR computation.  
In this state, **writing to any register or reading tap coefficients is not allowed**.  
If such an operation is attempted, it will either be ignored or return `32'hffffffff`.
If the system reads from address `12'h0` in this state, it indicates that a full round of data processing has been completed, and the system transitions back to `IDLE`, preparing for the next round.

> **(Potential Bug Warning)**  
> If the previous round has not yet finished but `12'h0` is read prematurely, the system will transition to `IDLE`, preventing FIR from continuing. This behavior needs further verification.

### state_data

```verilog
  reg [1:0] state;
  reg [1:0] next_state;
  // state for data
  localparam IDLE = 2'b00;
  localparam TRAN = 2'b01;
  localparam FIR = 2'b10;

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
```


`state_data` is primarily responsible for managing the **AXI-Stream** operations.  
It consists of three states: **IDLE, TRAN, and FIR**.

#### **IDLE**  
The system remains in the `IDLE` state when `ap_start` has not yet been received.  
In this state, **signals generated by AXI-Stream cannot be received**.  
Once `ap_start` is asserted, the system transitions to the `TRAN` state.

#### **TRAN**  
The `TRAN` state is active when the system has **not yet received** `ss_tvalid`.  
Once the system receives a valid `ss_tvalid` and `ss_tdata`, it transitions to the `FIR` state.

#### **FIR**  
The `FIR` state is entered after the system receives `ss_tvalid`.  
In this state, the system performs the computation corresponding to the current input data.  
Once the computation is complete and the output has been consumed, the system determines whether this is the **last data entry**:
- If **it is the last entry**, the system transitions to the `IDLE` state to prepare for the next round.
- If **it is not the last entry**, the system returns to the `TRAN` state and waits for the next `ss_tdata` input.




### state_ap

```verilog
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
```

`IDLE_AP` refers to the state where the system resides before `ap_start` is asserted. After every reset, the system also returns to this state.  
If `ap_start` is asserted while in the `IDLE_AP` state, the state machine transitions to the `CAL_AP` state.

`CAL_AP` refers to the state where the system is performing FIR computations.  
If the system receives `sm_tvalid & sm_tready & sstlast_reg`, it indicates that the system has received the final `y` value, and the system will transition to the `DONE_AP` state.

`DONE_AP` refers to the state where the system has completed one full round of data processing and all `y` values have been output.  
At this point, if the system detects `address == 12'h0`, it can transition back to the `IDLE_AP` state, allowing the system to proceed to the next round.

```verilog
 assign ap_done = (state_ap == DONE_AP);
 assign ap_idle = (state_ap != CAL_AP);
```

`ap_done` and `ap_idle` can be directly controlled by `state_ap`.  
`ap_idle` is only **0** when FIR processing is in progress, while `ap_done` is **1** only in the `DONE_AP` state.  

Once `ap_done` is read, `state_ap` will transition to the `IDLE_AP` mode, and `ap_done` should also be set to **0**.

```verilog
assign ap_start = (w_permit & (address_reg == 12'h0)) ? data_reg : ((state == FIR) ? 0 : ap_start_prev); 

 always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      ap_start_prev <= 0;
    end else begin
      ap_start_prev <= ap_start;
    end
  end
```

`ap_start` is written when `address` is **0** and `w_permit` is asserted.  
It is reset to **0** when `state_ap` and `state_tap` transition to FIR computation.  
At all other times, it retains its previous value.

## axi-lite

### address_reg and data_reg

```verilog
  reg [(pADDR_WIDTH-1):0] address_reg_prev;
  reg [(pDATA_WIDTH-1):0] data_reg_prev;
  reg [(pDATA_WIDTH-1):0] data_reg;
  reg [(pADDR_WIDTH-1):0] address_reg;  
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      address_reg_prev <= address_reg;
      data_reg_prev <= data_reg;
    end else begin
      address_reg_prev <= address_reg;
      data_reg_prev <= data_reg;
    end
  end
 
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
```

`address_reg` and `data_reg` are registers that store the addresses or data transmitted via **AXI-Lite**.  
Their signals are determined based on the system state and whether a **write** or **read** operation is being performed.


### data_len_reg and tap_num_reg

```verilog
  reg [(pDATA_WIDTH-1):0] tap_num_reg_prev;
  reg [(pDATA_WIDTH-1):0] data_len_reg_prev;
  wire [(pDATA_WIDTH-1):0] tap_num_reg;
  wire [(pDATA_WIDTH-1):0] data_len_reg;


always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      data_len_reg_prev <= 0;
      tap_num_reg_prev <= 0;
    end else begin
      data_len_reg_prev <= data_len_reg;
      tap_num_reg_prev <= tap_num_reg;
    end
  end  

  assign data_len_reg = (w_permit & (address_reg == 12'h10)) ? data_reg : data_len_reg_prev;
  assign tap_num_reg = (w_permit & (address_reg == 12'h14)) ? data_reg : tap_num_reg_prev;
```

`data_len_reg` and `tap_num_reg` store the data written to input addresses **0x10** and **0x14**, respectively.

### wready awready rvalid arready

```verilog
  assign writing = awvalid & wvalid;
  assign w_permit = writing & (state == TRAN);
  assign r_permit = arvalid & (state != IDLE);
  assign rvalid = (arready ? 1 : (rvaild_down ? 0 : rvalid_reg));
  assign arready = (~(writing) & arvalid) & (state == WAIT | fir_read_d1);
  assign awready = writing & ((state == WAIT) | (state == FIR));
  assign wready = writing & ((state == WAIT) | (state == FIR));
  assign fir_read_ok = (state == FIR) & arvalid;
  
  always @(posedge axis_clk) begin
    fir_read_d1 <= fir_read; 
  end
  
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

```

- `AWREADY` and `WREADY` are asserted (`1`) when both `awvalid` and `wvalid` are high simultaneously.  
  They are designed to be asserted **one cycle after** `awvalid` and `wvalid`.

- `ARREADY` is asserted when `arvalid` is high and the system is **not in a write operation**.  
  It is also designed to be asserted **one cycle after** `arvalid`.

- `RVALID` is asserted **after** `arready` is received.  
  It remains high until `rready` is asserted, at which point it is deasserted (`0`).

### Tap Ram

```verilog
  assign tap_WE = {4{(state == TRAN) & (awaddr[7] & (awaddr[11:8] == 0))}};
  assign tap_EN = (state != IDLE);
  assign tap_A = (state == FIR) ? {4'b0, fir_data_count, 2'b0} : (((w_permit | r_permit) & (address_reg[7] & (address_reg[11:8] == 0))) ? {5'b0, address_reg[6:2], 2'b0} : tap_A_prev);
  assign tap_Di = (w_permit & (address_reg[7] & (address_reg[11:8] == 0))) ? data_reg : tap_Di_prev;

  reg [(pADDR_WIDTH-1):0] tap_A_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      tap_A_prev <= 0;
    end else begin
      tap_A_prev <= tap_A;
    end
  end

  reg [(pDATA_WIDTH-1):0] tap_Di_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      tap_Di_prev <= 0;
    end else begin
      tap_Di_prev <= tap_Di;
    end
  end
```

- `tap_WE` is enabled **only when** `state_tap` is in `TRAN` and `awaddr` is within the range `12'h80 ~ 12'hFF`.

- `tap_EN` is designed to be `1` in all `state_tap` states **except** `IDLE`.

- `tap_A` is divided into two parts to accommodate both **AXI-Lite** operations and **FIR computation**:
  - If `state_tap == FIR`, `tap_A` is controlled by `fir_data_count` to ensure correct FIR operation.
  - If `state_ap != FIR`, `tap_A` changes based on read/write requests. Otherwise, it retains its previous value.

- `tap_Di` is enabled **only when AXI-Lite needs to write data**. If no write operation is required, it retains its previous value.

### rdata

```verilog
  reg [(pDATA_WIDTH-1):0] read_data_reg; 
  assign rdata = read_data_reg;

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

  reg [(pDATA_WIDTH-1):0] read_data_reg_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      read_data_reg_prev <= 0;
    end else begin
      read_data_reg_prev <= read_data_reg;
    end
  end
```

`read_data_reg` is a register used to retrieve the value from the specified address.  

- If the read address is **not used in this design** or if **tap coefficients are read during FIR computation**, it returns `32'hffffffff`.  
- Otherwise, it retains its previous value.

## axi-stream

### ss_tready

```verilog
  assign ss_tready = (state == IDLE) ? 0 : ss_tready_reg;
  wire ss_tready_reg_tmp;
  assign ss_tready_reg_tmp = (state == TRAN) & ss_tvalid;
  always @(posedge axis_clk) begin
    ss_tready_reg <= ss_tready_reg_tmp;
  end
```

`ss_tready` remains **0** when `state_data == IDLE`.  

- It is asserted **one cycle after** receiving `ss_tvalid` when `state_data == TRAN`.  
- It stays high for **only one cycle** before being deasserted.


### ss_tlast_reg

```verilog
  reg sstlast_reg; 
  reg sstlast_reg_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      sstlast_reg_prev <= 0;
    end else begin
      sstlast_reg_prev <= sstlast_reg;
    end
  end

  always @(*) begin
    case (state)
      IDLE: begin
        sstlast_reg = 0;
      end
      TRAN: begin
        if (ss_tvalid & ss_tlast) begin
          sstlast_reg = 1;
        end else begin
          sstlast_reg = 0;
        end
      end
      default: begin
        sstlast_reg = sstlast_reg_prev;
      end
    endcase
  end
```

`ss_tlast_reg` is a register used to store whether the current data is the **last data entry**.  
It serves as a reference when outputting `y` to determine whether the current round should end.

### total_num_data tape_num

```verilog
  wire [5:0] tape_num;
  wire [5:0] total_num_data_tmp;
  assign total_num_data_tmp = (state == IDLE) ? 0 : (total_num_data == tape_num ? total_num_data : (ss_tready) ? (total_num_data + 1) : total_num_data);
  assign tape_num = (tap_num_reg - 1) & 6'b111111;

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      total_num_data <= 0;
    end else begin
      total_num_data <= total_num_data_tmp;
    end
  end
```

- `tap_num` records the **tap_number count**, using **0-based indexing**.  
- `total_num_data` keeps track of the total number of data entries received in the current round.  
  - If `total_num_data` reaches `tap_num`, it remains fixed at `tap_num`.

### this_round_num base_addr next_sstdata_addr

```verilog
 assign this_round_num = ((state == TRAN) & (ss_tvalid)) ? total_num_data : this_round_num_prev;
 assign base_addr = (state == TRAN) ? next_sstdata_addr : base_addr_prev; 

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
```

- `this_round_num` records the **number of data entries used in the current round** during the `TRAN` state.  

- `base_addr` is updated **in the `TRAN` state** to store the **starting address** of data for the current round.  

- `next_sstdata_addr` is updated **in the `FIR` state** to store the **starting address** of data for the next round.


### data_addr_gen fir_data_count

```verilog
  reg [5:0] data_addr_gen;   
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

  reg [5:0] fir_data_count
  wire [5:0] fir_data_count_tmp;
  assign fir_data_count_tmp = (state == FIR) ? fir_data_count + 1 : 0;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      fir_data_count <= 0;
    end else begin
      fir_data_count <= fir_data_count_tmp;
    end
  end
```

- `data_addr_gen` generates the corresponding **address** based on the **starting address** and the **current data index**.  
  - If `count > base_addr`, `tap_num` is added to correctly map to the actual address.

- `fur_data_count` is a register that records the **current data index** when the system transitions to the `FIR` state.  
  - It is used to **control `data_address` and `tap_address`**.  
  - It also determines when to **clear the `y` register**.

### countdown

```verilog
  wire [31:0] countdown_tmp;
  assign countdown_tmp = (state != FIR) ? 32'hffffffff : ((fir_data_count == this_round_num) ? 3 : countdown - 1);
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      countdown <= 32'hffffffff;
    end else begin
      countdown <= countdown_tmp;
    end
  end
```

`countdown` is used to determine when to retrieve the `y` value.  
When `countdown` reaches **0**, `y` should be retrieved and wait for `sm` to read it.


### data Ram

```verilog
  assign data_EN = (state != IDLE);
  assign data_WE = {4{ss_tready}};
  assign data_A = {4'b0, data_addr_gen, 2'b0};
  assign data_Di = ss_tdata;
```

- `data_EN` is asserted **after `ap_start` is received**.  

- Data can only be input when `ss_tready` is high, so `data_WE` is **asserted only when `ss_tready` is active**.  

- `data_A` controls which data is being read or written and is **directly controlled by `data_addr_gen`**.  

- `data_Di` is **directly connected to `ss_tdata`**, as `data_WE` is only asserted when `ss_tready` is high.  

### sm_tvalid sm_tdata sm_tlast

```verilog
  assign sm_tdata = sm_tdata_reg;
  assign sm_tlast = (sm_tvalid) & (sstlast_reg);
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
```

- `sm_tdata` retrieves the value from the `y` register **when `countdown` reaches 0**.  
  - It maintains the same value **until it is read**.  

- `sm_tvalid` behaves the same as `sm_tdata`:  
  - It is asserted **when `countdown` reaches 0** and remains high **until `sm_tready` is received**.  

- `sm_tlast` is asserted **when both `sstlast_reg` and `sm_tvalid` are high**.  
  - Since `sstlast_reg == 1` indicates that the **last data input has been received**, this output is also the **final data entry**.  
  - `sm_tlast` is asserted to notify the system.

## FIR Processing Flow

```verilog
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
```


### **Important Note**  
When `fir_data_count == 2`, `y_tmp` will be **cleared**.  

- This is because, in the next cycle, **the first value of a new round** will enter the `y` register.  
- Therefore, clearing `y_tmp` at this point is necessary to ensure proper data handling.

![image](https://hackmd.io/_uploads/ByyGc9Sh1l.png)

The waveform diagram above represents the case when there is only **one data**.  

- As shown, when `fir_data_count == 2`, `y_tmp_reg` needs to be **cleared**.  
- This is because, on the next **posedge of `axis_clk`**, a new round's `y_tmp` will be stored.  


## Full Code

```verilog=
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
  output  reg                      sstlast_reg,
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

  wire [5:0] total_num_data_tmp;
  assign total_num_data_tmp = (state == IDLE) ? 0 : (total_num_data == tape_num ? total_num_data : (ss_tready) ? (total_num_data + 1) : total_num_data);

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      total_num_data <= 0;
    end else begin
      total_num_data <= total_num_data_tmp;
    end
  end
  

  wire [31:0] countdown_tmp;
  assign countdown_tmp = (state != FIR) ? 32'hffffffff : ((fir_data_count == this_round_num) ? 3 : countdown - 1);
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      countdown <= 32'hffffffff;
    end else begin
      countdown <= countdown_tmp;
    end
  end

  wire [5:0] fir_data_count_tmp;
  assign fir_data_count_tmp = (state == FIR) ? fir_data_count + 1 : 0;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      fir_data_count <= 0;
    end else begin
      fir_data_count <= fir_data_count_tmp;
    end
  end

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  wire ss_tready_reg_tmp;
  assign ss_tready_reg_tmp = (state == TRAN) & ss_tvalid;
  always @(posedge axis_clk) begin
    ss_tready_reg <= ss_tready_reg_tmp;
  end

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

  reg sstlast_reg_prev;
  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      sstlast_reg_prev <= 0;
    end else begin
      sstlast_reg_prev <= sstlast_reg;
    end
  end

  always @(*) begin
    case (state)
      IDLE: begin
        sstlast_reg = 0;
      end
      TRAN: begin
        if (ss_tvalid & ss_tlast) begin
          sstlast_reg = 1;
        end else begin
          sstlast_reg = 0;
        end
      end
      default: begin
        sstlast_reg = sstlast_reg_prev;
      end
    endcase
  end
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
 

  // ap_crtl
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

  always @(posedge axis_clk or negedge axis_rst_n) begin
    if (~axis_rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  always @(posedge axis_clk) begin
    fir_read_d1 <= fir_read; 
  end

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

// next_state update
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

  assign tap_WE = {4{(state == TRAN) & (awaddr[7] & (awaddr[11:8] == 0))}};
  assign tap_EN = (state != IDLE);

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

  assign tap_A = (state == FIR) ? {4'b0, fir_data_count, 2'b0} : (((w_permit | r_permit) & (address_reg[7] & (address_reg[11:8] == 0))) ? {5'b0, address_reg[6:2], 2'b0} : tap_A_prev);

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
```

# Waveform and Area Report

## Axilite
![image](https://hackmd.io/_uploads/HkyeqvB3yg.png)

## Axistream

![image](https://hackmd.io/_uploads/SkszqDH2yl.png)

## Area Report

![image](https://hackmd.io/_uploads/By55cwBnJx.png)
