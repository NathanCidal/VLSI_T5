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

## comando de compilação. 
vlog    ../rtl/ringbuffer.sv
vlog    ../rtl/uart_tx.sv
vlog    ./uart_tx_tb.sv

## comando de simulação
vsim -voptargs=+acc -wlfdeleteonquit work.tb_top

set StdArithNoWarnings 1
set StdVitalGlitchNoWarnings 1

## adição dos sinais na forma de onda.
add wave sim:/*

## execução da simulação.
run 25ms
