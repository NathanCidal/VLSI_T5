
module FPGA_UART_Top #( 
    parameter int CLK_FREQUENCE = 32'd100_000_000
)(
    input  logic       clk,
    input  logic       reset_i,
    input  logic [1:0] select_baud_i,  
    input  logic [2:0] select_data_i,
    input  logic       new_data_i,

    output logic [2:0] select_data_o,
    output logic       buffer_full,
    output logic       uart_tx_o
);

logic [7:0] uart_data;
assign select_data_o = select_data_i;

always_comb begin
    unique case(select_data_i)
        3'd0: begin uart_data = 8'("A");  end
        3'd1: begin uart_data = 8'("B");  end
        3'd2: begin uart_data = 8'("C");  end
        3'd3: begin uart_data = 8'("D");  end
        3'd4: begin uart_data = 8'("E");  end
        3'd5: begin uart_data = 8'("F");  end
        3'd6: begin uart_data = 8'("G");  end
        3'd7: begin uart_data = 8'("\n"); end
        default: uart_data = '0;
    endcase
end

uart_tx #(
    .CLK_REF(CLK_FREQUENCE)
) u_uart_tx (
    .clock_in         (clk),
    .reset_in         (!reset_i),
    .data_p_in        (uart_data),
    .data_p_en_in     (new_data_i),
    .uart_rate_tx_sel (select_baud_i),
    .buffer_full      (buffer_full),
    .uart_data_tx     (uart_tx_o)
);


endmodule