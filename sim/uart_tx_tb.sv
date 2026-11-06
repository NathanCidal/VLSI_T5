`timescale 1ns/1ns
module uart_tx_tb();

logic clock_100mhz = 1;
logic reset;

logic [1:0] baud_select;
logic [7:0] data_in;
logic       data_in_en;

logic       buffer_full;
logic       data_o;

// Geração de clock de 100 MHz (período de 10ns)
always begin
    #5ns clock_100mhz <= 1'b0;
    #5ns clock_100mhz <= 1'b1;
end

initial begin
    reset = 1'b1;
    #1000ns;
    reset = 1'b0;
end

// Instanciação do DUT
uart_tx dut_uart_tx (
    .clock_in         (clock_100mhz),
    .reset_in         (reset),
    .data_p_in        (data_in),
    .data_p_en_in     (data_in_en),
    .uart_rate_tx_sel (baud_select),
    .buffer_full      (buffer_full),
    .uart_data_tx     (data_o)
);

// Task para enviar dados injetando em rajada
task send_data(input logic [7:0] data, input logic [1:0] baud);
    while (buffer_full) begin
        @(posedge clock_100mhz);
    end

    @(posedge clock_100mhz);
    data_in     <= data;
    baud_select <= baud; 
    data_in_en  <= 1'b1; 
    
    @(posedge clock_100mhz);
    data_in_en  <= 1'b0;
endtask

// Task monitor/decodificador sincronizada com a retenção de baud do RTL
task monitor_uart();
    real bit_period_ns;
    logic [7:0] rx_byte;
    int baud_rate;
    logic [1:0] locked_baud;

    forever begin
        // 1. Aguarda a linha cair indicando o Start Bit
        @(negedge data_o);
        
        // 2. Como o hardware congela a taxa baseada no que está configurado no IDLE,
        // pegamos o baud_select atual que reflete o estado travado da FSM.
        locked_baud = baud_select;

        case (locked_baud)
            2'b00: begin baud_rate = 9600;  bit_period_ns = 1000000000.0 / 9600.0;  end
            2'b01: begin baud_rate = 19200; bit_period_ns = 1000000000.0 / 19200.0; end
            2'b10: begin baud_rate = 28800; bit_period_ns = 1000000000.0 / 28800.0; end
            2'b11: begin baud_rate = 57600; bit_period_ns = 1000000000.0 / 57600.0; end
        endcase

        // 3. Aguarda o meio do Start Bit para sincronizar a amostragem
        #(bit_period_ns / 2.0);
        
        if (data_o == 1'b0) begin
            // 4. Amostra os 8 bits de dados (LSB primeiro)
            for (int i = 0; i < 8; i++) begin
                #(bit_period_ns);
                rx_byte[i] = data_o;
            end
            
            // 5. Aguarda o bit de Stop completo
            #(bit_period_ns);
            
            // Exibe o resultado decodificado no terminal
            if (baud_rate > 0) begin
                $display("[%0t ns] [UART RX DECODER] Baud Efetivo: %0d bps | Dado Hex: 0x%0h | Dado ASCII: %c", 
                         $time, baud_rate, rx_byte, (rx_byte >= 32 && rx_byte <= 126) ? rx_byte : ".");
            end
        end
    end
endtask

// Inicializa o monitor em paralelo
initial begin
    fork
        monitor_uart();
    join_none
end

// Sequência de teste em rajada
initial begin
    data_in_en  = 1'b0;
    data_in     =   '0;
    baud_select = 2'b00;

    @(negedge reset);
    #200ns;

    $display("[%0t ns] Iniciando teste de rajada com retenção do último Baud...", $time);
    
    send_data("N", 2'b00);
    send_data("A", 2'b01);
    send_data("T", 2'b10);
    send_data("E", 2'b11); // Define a taxa final da rajada

    #2000000; 
    $display("[%0t ns] Fim dos testes!\n", $time);
    $finish;
end

endmodule