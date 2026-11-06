`timescale 1ns/1ps
module tb_top;
    logic clk = 0, reset_i = 0, new_data_i = 0;
    logic [1:0] baud = 2'b00;
    logic [2:0] sd_o;
    logic full, tx;

    always #5 clk = ~clk; // 100 MHz

    FPGA_UART_Top dut (
        .clk(clk), 
        .reset_i(reset_i), 
        .select_baud_i(baud),
        .select_data_i(3'b0), 
        .new_data_i(new_data_i),
        .select_data_o(sd_o), 
        .buffer_full(full), 
        .uart_tx_o(tx)
    );

    localparam int BIT_NS = (100_000_000/9600) * 10;
    string rx = "";
    logic [7:0] b;

    initial begin
        #100 reset_i = 1;
        #100 new_data_i = 1;
        #100 new_data_i = 0;
    end

    initial begin
        forever begin
            @(negedge tx);
            #(BIT_NS + BIT_NS/2);
            for (int i = 0; i < 8; i++) begin
                b[i] = tx;
                #(BIT_NS);
            end
            if (tx !== 1'b1) $display("ERRO: stop bit invalido");
            rx = {rx, string'(b)};
        end
    end

    initial begin
        #(BIT_NS * 10 * 21);
        $display("RECEBIDO: [%s]", rx);
        if (rx == "HELLO WORLD!!! 123\n") $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule