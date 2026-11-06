module uart_tx
#(
    parameter int CLK_REF = 100_000_000 // Hertz
)
(
    input  logic       clock_in,
    input  logic       reset_in,        // ativo em 1
    input  logic [7:0] data_p_in,
    input  logic       data_p_en_in,    // escreve data_p_in no buffer (se não cheio)
    input  logic [1:0] uart_rate_tx_sel,
    output logic       buffer_full,
    output logic       uart_data_tx
);

logic uart_busy;

///////////////////////////////////////////////////////////
//                   States for FSM                      //
///////////////////////////////////////////////////////////
typedef enum logic [3:0] {
    IDLE     = 0,
    GET_DATA = 1,
    START    = 2,
    D0       = 3,
    D1       = 4,
    D2       = 5,
    D3       = 6,
    D4       = 7,
    D5       = 8,
    D6       = 9,
    D7       = 10,
    STOP     = 11
} state_t;

state_t current_state;
state_t next_state;

///////////////////////////////////////////////////////////
//        Sincronizador da seleção de baud (2 FFs)       //
///////////////////////////////////////////////////////////
logic [1:0] uart_rate_tx_sel_q1;
logic [1:0] uart_rate_tx_sel_q;

always_ff @(posedge clock_in or posedge reset_in) begin
    if (reset_in) begin
        uart_rate_tx_sel_q1 <= '0;
        uart_rate_tx_sel_q  <= '0;
    end
    else begin
        uart_rate_tx_sel_q1 <= uart_rate_tx_sel;
        uart_rate_tx_sel_q  <= uart_rate_tx_sel_q1;
    end
end

///////////////////////////////////////////////////////////
//                     UART Speed                        //
///////////////////////////////////////////////////////////
logic [31:0] clks_per_bit;
logic [31:0] clks_per_bit_target;

always_comb begin
    unique case (uart_rate_tx_sel_q)
        2'b00:   clks_per_bit_target = CLK_REF / 9600;
        2'b01:   clks_per_bit_target = CLK_REF / 19200;
        2'b10:   clks_per_bit_target = CLK_REF / 28800;
        default: clks_per_bit_target = CLK_REF / 57600;
    endcase
end

always_ff @(posedge clock_in or posedge reset_in) begin
    if (reset_in) begin
        clks_per_bit <= CLK_REF / 9600;
    end
    else begin
        if (current_state == IDLE) begin
            clks_per_bit <= clks_per_bit_target;
        end
    end
end

///////////////////////////////////////////////////////////
//              UART Pulse Generator                     //
///////////////////////////////////////////////////////////
logic        uart_pulse;
logic [31:0] bit_counter;

assign uart_pulse = uart_busy && (bit_counter >= clks_per_bit - 1);

always_ff @(posedge clock_in or posedge reset_in) begin
    if (reset_in) begin
        bit_counter <= '0;
    end
    else begin
        if (!uart_busy) begin
            bit_counter <= '0;
        end  
        else if (uart_pulse) begin
            bit_counter <= '0;
        end else begin
            bit_counter <= bit_counter + 1'b1;
        end
    end
end

///////////////////////////////////////////////////////////
//                    Ring Buffer                        //
///////////////////////////////////////////////////////////
logic [7:0] read_data;
logic       re;
logic       empty;
logic       full;

assign re = (current_state == GET_DATA);

ringbuffer #(
    .DATA_WIDTH (8),
    .BUFFER_SIZE(16)
) u_RingBuffer (
    .clk_i   (clock_in),
    .reset_i (reset_in),
    .data_i  (data_p_in),
    .data_o  (read_data),
    .rx_we_i (data_p_en_in),
    .tx_re_i (re),
    .empty_o (empty),
    .full_o  (full)
);

///////////////////////////////////////////////////////////
//                         FSM                           //
///////////////////////////////////////////////////////////
always_ff @(posedge clock_in or posedge reset_in) begin
    if (reset_in) current_state <= IDLE;
    else          current_state <= next_state;
end

assign uart_busy = (current_state != IDLE) && (current_state != GET_DATA);

always_comb begin
    next_state = current_state;

    unique case (current_state)
        IDLE: begin
            if (!empty) next_state = GET_DATA;
        end

        GET_DATA: begin
            next_state = START;
        end

        START: if (uart_pulse) next_state = D0;
        D0:    if (uart_pulse) next_state = D1;
        D1:    if (uart_pulse) next_state = D2;
        D2:    if (uart_pulse) next_state = D3;
        D3:    if (uart_pulse) next_state = D4;
        D4:    if (uart_pulse) next_state = D5;
        D5:    if (uart_pulse) next_state = D6;
        D6:    if (uart_pulse) next_state = D7;
        D7:    if (uart_pulse) next_state = STOP;
        STOP:  if (uart_pulse) next_state = IDLE;

        default: next_state = IDLE;
    endcase
end

///////////////////////////////////////////////////////////
//                  Saída serial                         //
///////////////////////////////////////////////////////////
logic uart_data_tx_reg;

always_ff @(posedge clock_in or posedge reset_in) begin
    if (reset_in) begin
        uart_data_tx_reg <= 1'b1;
    end
    else begin
        case (current_state)
            START:   uart_data_tx_reg <= 1'b0;
            D0:      uart_data_tx_reg <= read_data[0];
            D1:      uart_data_tx_reg <= read_data[1];
            D2:      uart_data_tx_reg <= read_data[2];
            D3:      uart_data_tx_reg <= read_data[3];
            D4:      uart_data_tx_reg <= read_data[4];
            D5:      uart_data_tx_reg <= read_data[5];
            D6:      uart_data_tx_reg <= read_data[6];
            D7:      uart_data_tx_reg <= read_data[7];
            default: uart_data_tx_reg <= 1'b1;   
        endcase
    end
end

assign buffer_full  = full;
assign uart_data_tx = uart_data_tx_reg;

endmodule