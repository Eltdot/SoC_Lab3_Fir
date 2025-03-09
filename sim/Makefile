sim:
	vcs -R +v2k -full64 My_tb.v ./bram32.v ../hdl/fir.v -debug_acc +nospecify +define+VCD
	
gatesim:
	vcs -R +v2k -full64 My_tb.v ./bram32.v ../syn/netlist/fir_syn.v -v /usr/cadtool/ee5216/CBDK_TSMC90GUTM_Arm_f1.0/CIC/Verilog/tsmc090.v +define+SDF +define+VCD -debug_acc +neg_tchk 