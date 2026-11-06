//
// Vivado(TM)
// rundef.js: a Vivado-generated Runs Script for WSH 5.1/5.6
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
//

echo "This script was generated under a different operating system."
echo "Please update the PATH variable below, before executing this script"
exit

var WshShell = new ActiveXObject( "WScript.Shell" );
var ProcEnv = WshShell.Environment( "Process" );
var PathVal = ProcEnv("PATH");
if ( PathVal.length == 0 ) {
  PathVal = "/soft64/xilinx/ferramentas/Vitis/2024.2/bin:/soft64/xilinx/ferramentas/Vivado/2024.2/ids_lite/ISE/bin/lin64;/soft64/xilinx/ferramentas/Vivado/2024.2/bin;";
} else {
  PathVal = "/soft64/xilinx/ferramentas/Vitis/2024.2/bin:/soft64/xilinx/ferramentas/Vivado/2024.2/ids_lite/ISE/bin/lin64;/soft64/xilinx/ferramentas/Vivado/2024.2/bin;" + PathVal;
}

ProcEnv("PATH") = PathVal;

var RDScrFP = WScript.ScriptFullName;
var RDScrN = WScript.ScriptName;
var RDScrDir = RDScrFP.substr( 0, RDScrFP.length - RDScrN.length - 1 );
var ISEJScriptLib = RDScrDir + "/ISEWrap.js";
eval( EAInclude(ISEJScriptLib) );


// pre-commands:
ISETouchFile( "init_design", "begin" );
ISEStep( "vivado",
         "-log FPGA_UART_Top.vdi -applog -m64 -product Vivado -messageDb vivado.pb -mode batch -source FPGA_UART_Top.tcl -notrace" );





function EAInclude( EAInclFilename ) {
  var EAFso = new ActiveXObject( "Scripting.FileSystemObject" );
  var EAInclFile = EAFso.OpenTextFile( EAInclFilename );
  var EAIFContents = EAInclFile.ReadAll();
  EAInclFile.Close();
  return EAIFContents;
}
