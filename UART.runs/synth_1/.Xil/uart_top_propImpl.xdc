set_property SRC_FILE_INFO {cfile:D:/GITHUB_PROJECT/UART/UART.srcs/constrs_1/new/arty-z7.xdc rfile:../../../UART.srcs/constrs_1/new/arty-z7.xdc id:1} [current_design]
set_property src_info {type:XDC file:1 line:12 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN H16    IOSTANDARD LVCMOS33 } [get_ports { clk }]; #IO_L13P_T2_MRCC_35 Sch=SYSCLK
set_property src_info {type:XDC file:1 line:18 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN M20    IOSTANDARD LVCMOS33 } [get_ports { rst_n }]; #IO_L7N_T1_AD2N_35 Sch=SW0
set_property src_info {type:XDC file:1 line:24 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { rxd }]; #IO_L5P_T0_34 Sch=CK_IO0 (UART RX from PC)
set_property src_info {type:XDC file:1 line:25 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { txd }]; #IO_L2N_T0_34 Sch=CK_IO1 (UART TX to PC)
set_property src_info {type:XDC file:1 line:34 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN R14    IOSTANDARD LVCMOS33 } [get_ports { tx_fifo_full }]; #IO_L6N_T0_VREF_34 Sch=LED0
set_property src_info {type:XDC file:1 line:35 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN P14    IOSTANDARD LVCMOS33 } [get_ports { rx_fifo_empty }]; #IO_L6P_T0_34 Sch=LED1
set_property src_info {type:XDC file:1 line:36 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN N16    IOSTANDARD LVCMOS33 } [get_ports { frame_error }]; #IO_L21N_T3_DQS_AD14N_35 Sch=LED2
set_property src_info {type:XDC file:1 line:37 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN M14    IOSTANDARD LVCMOS33 } [get_ports { tx_busy }]; #IO_L23P_T3_35 Sch=LED3
