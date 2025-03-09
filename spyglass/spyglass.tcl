#read_file -type verilog ./hdl/bcd.v
read_file -type sourcelist ./hdl.f

current_goal lint/lint_rtl -alltop
## Goal:lint/lint_rtl            ####################
##   current_goal lint/lint_rtl
#read_file -type awl waiver.awl
#set_goal_option addrules { W164a W164b STARC05-1.1.1.5 STARC05-2.10.3.2b_sa}
#set_parameter strict {STARC05-1.1.1.5,STARC05-2.10.3.1,W164a,W122,W116,W398,SignedUnsignedExpr-ML,ConstantInput-ML,W19,W164b,InferLatch,NoGenLabel-ML,STARC05-2.10.3.6}
#set_parameter check_static_value only_const,W164a,yes,W164b
#set_parameter handle_zero_padding no
#set_parameter check_concat_max_width yes
#set_parameter disable_rtl_deadcode yes
#set_parameter check_static_natural_width yes
#set_parameter nocheckoverflow yes
#set_parameter check_unsign_overflow yes
run_goal
capture moresimple_all.rpt {write_report moresimple}

current_goal lint/lint_turbo_rtl -alltop
## Goal:lint/lint_turbo          ####################
#   current_goal lint/lint_turbo_rtl
#      set_parameter strict 				{W342,W343} 
#      set_parameter check_initialization_assignment 	no
#      set_parameter ignore_multi_assign_in_forloop      no
#      set_parameter ignore_bitwiseor_assignment	        no
#      set_parameter ignoreModuleInstance		no
#      set_parameter treat_latch_as_combinational	no
#      set_parameter assume_driver_load		        no
#      set_parameter checkconstassign			no
#      set_parameter checkfullbus			no
#      set_parameter checkfullrecord			no
#      set_parameter nocheckoverflow		 	yes	
#      set_parameter enableE2Q				no
#     set_parameter checkalldimension			no
#      set_parameter reportundrivenout			no
#      set_parameter min_based_width		 	0	
#     set_parameter ignoreforindex			no
#      set_parameter chkTopModule			no
#      set_parameter checkInHierarchy			no
#      set_parameter checkRTLCInst			no
#      set_parameter ignore_chain_cell			no
run_goal
capture -append moresimple_all.rpt {write_report moresimple}

current_goal lint/lint_functional_rtl -alltop
run_goal
capture -append moresimple_all.rpt {write_report moresimple}

current_goal lint/lint_abstract -alltop
run_goal
capture -append moresimple_all.rpt {write_report moresimple}

#current_goal adv_lint/adv_lint_struct -alltop
#run_goal
#capture -append moresimple_all.rpt {write_report moresimple}

#current_goal adv_lint/adv_lint_verify -alltop
#run_goal
#capture -append moresimple_all.rpt {write_report moresimple}