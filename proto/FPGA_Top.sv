module FPGA_UART_Top #(
    parameter int CLK_FREQUENCE = 100_000_000
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

assign select_data_o = select_data_i;

localparam int MSG_LEN = 19;
localparam logic [7:0] UART_MEM [MSG_LEN] = '{
    "H", "E", "L", "L", "O", " ",
    "W", "O", "R", "L", "D",
    "!", "!", "!", " ",
    "1", "2", "3", "\n"
};

logic [2:0] new_data_sync;
logic       new_data;

always_ff @(posedge clk or negedge reset_i) begin
    if (!reset_i) begin 
        new_data_sync <= '0;
    end
    else begin
        new_data_sync <= {new_data_sync[1:0], new_data_i};
    end
end

assign new_data = new_data_sync[1] & ~new_data_sync[2];

///////////////////////////////////////////////////////////
//  FSM de envio
///////////////////////////////////////////////////////////
typedef enum logic {
    IDLE    = 1'b0,
    SENDING = 1'b1
} data_t;

data_t current;
data_t next;

logic       buffer_full_q;
logic [4:0] counter;     
logic [7:0] uart_data;
logic       insert_data; 

assign insert_data = (current == SENDING) && !buffer_full_q;
assign uart_data   = UART_MEM[counter];

always_ff @(posedge clk or negedge reset_i) begin
    if (!reset_i) begin 
        current <= IDLE; 
    end 
    else begin
        current <= next;
    end
end

always_comb begin
    next = current;
    unique case (current)
        IDLE:    if (new_data) next = SENDING;
        SENDING: if (insert_data && (counter == 5'(MSG_LEN-1))) next = IDLE;
        default: next = IDLE;
    endcase
end

always_ff @(posedge clk or negedge reset_i) begin
    if (!reset_i) begin
        counter <= '0;
    end
    else if (insert_data) begin
        if (counter == 5'(MSG_LEN-1)) counter <= '0;
        else                          counter <= counter + 1'b1;
    end
end

///////////////////////////////////////////////////////////
//  UART TX
///////////////////////////////////////////////////////////
uart_tx #(
    .CLK_REF(CLK_FREQUENCE)
) u_uart_tx (
    .clock_in         (clk),
    .reset_in         (!reset_i),
    .data_p_in        (uart_data),
    .data_p_en_in     (insert_data),
    .uart_rate_tx_sel (select_baud_i),
    .buffer_full      (buffer_full_q),
    .uart_data_tx     (uart_tx_o)
);

assign buffer_full = buffer_full_q;

endmodule