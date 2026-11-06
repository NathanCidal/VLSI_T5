#!/bin/sh

# 
# Vivado(TM)
# runme.sh: a Vivado-generated Runs Script for UNIX
# Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
# Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
# 

if [ -z "$PATH" ]; then
  PATH=/soft64/xilinx/ferramentas/Vitis/2024.2/bin:/soft64/xilinx/ferramentas/Vivado/2024.2/ids_lite/ISE/bin/lin64:/soft64/xilinx/ferramentas/Vivado/2024.2/bin
else
  PATH=/soft64/xilinx/ferramentas/Vitis/2024.2/bin:/soft64/xilinx/ferramentas/Vivado/2024.2/ids_lite/ISE/bin/lin64:/soft64/xilinx/ferramentas/Vivado/2024.2/bin:$PATH
fi
export PATH

if [ -z "$LD_LIBRARY_PATH" ]; then
  LD_LIBRARY_PATH=
else
  LD_LIBRARY_PATH=:$LD_LIBRARY_PATH
fi
export LD_LIBRARY_PATH

HD_PWD='/home/nathan.cidal/VLSI_T5/proto/UART_TX_Proto.runs/synth_1'
cd "$HD_PWD"

HD_LOG=runme.log
/bin/touch $HD_LOG

ISEStep="./ISEWrap.sh"
EAStep()
{
     $ISEStep $HD_LOG "$@" >> $HD_LOG 2>&1
     if [ $? -ne 0 ]
     then
         exit
     fi
}

EAStep vivado -log FPGA_UART_Top.vds -m64 -product Vivado -mode batch -messageDb vivado.pb -notrace -source FPGA_UART_Top.tcl
