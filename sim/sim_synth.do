if {! [ file exists work ] } { 
        echo "criando biblioteca WORK..."
        vlib work
        echo " "
} else {
        echo "apagando biblioteca WORK..."
        vdel -all
        echo "recriando biblioteca WORK..."
        vlib work
        echo " "
}

## comando de compilação
vlog    /soft64/design-kits/asu/asap7/asap7sc7p5t_28/Verilog/*.v
vlog    ../synthesis/deliverables/uart_tx_netlist.sv
vlog    ./uart_tx_tb.sv

## comando de simulação  
vsim -voptargs=+acc -wlfdeleteonquit work.uart_tx_tb
        
set StdArithNoWarnings 1
set StdVitalGlitchNoWarnings 1 

## adição dos sinais na forma de onda.  
restart -f
add wave sim:/*

## execução da simulação.    
run 3ms
