module uart_tx
#(
    parameter int CLK_REF = 32'd100_000_000 // Hertz
)
(
    input  logic       clock_in,
    input  logic       reset_in,
    input  logic [7:0] data_p_in,
    input  logic       data_p_en_in,
    input  logic [1:0] uart_rate_tx_sel,
    output logic       buffer_full,           // For Control    
    output logic       uart_data_tx
);

logic uart_busy;

///////////////////////////////////////////////////////////
//                   States for FSM                      //
///////////////////////////////////////////////////////////
typedef enum logic [4:0] {
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
//                       Sync Flops                      //
///////////////////////////////////////////////////////////
logic [1:0] uart_rate_tx_sel_q;
logic       data_p_en_in_q;

always_ff @(posedge clock_in or posedge reset_in) begin
    if(reset_in) begin
        uart_rate_tx_sel_q <= '0;
        data_p_en_in_q     <= 1'b0;
    end
    else begin
        uart_rate_tx_sel_q <= uart_rate_tx_sel;
        data_p_en_in_q     <= data_p_en_in;
    end
end

///////////////////////////////////////////////////////////
//                     UART Speed                        //
///////////////////////////////////////////////////////////
logic [31:0] clks_per_bit;
logic [31:0] clks_per_bit_target;

always_comb begin
    unique case(uart_rate_tx_sel_q)
        2'b00: begin clks_per_bit_target <= (CLK_REF /  32'd9600); end
        2'b01: begin clks_per_bit_target <= (CLK_REF / 32'd19200); end
        2'b10: begin clks_per_bit_target <= (CLK_REF / 32'd28800); end
        2'b11: begin clks_per_bit_target <= (CLK_REF / 32'd57600); end
    endcase 
end

always_ff @(posedge clock_in or posedge reset_in) begin
    if(reset_in) begin
        clks_per_bit        <= (CLK_REF / 32'd9600);
    end
    else begin
        if(current_state == IDLE) begin
            clks_per_bit <= clks_per_bit_target;
        end
    end
end

///////////////////////////////////////////////////////////
//              UART Pulse Generator                     //
///////////////////////////////////////////////////////////
logic uart_pulse;
logic [31:0] bit_counter;

always_ff @(posedge clock_in or posedge reset_in) begin
    if(reset_in) begin
        bit_counter <= '0;
        uart_pulse  <= 1'b0;
    end
    else begin
        if(uart_busy) begin
            bit_counter <= bit_counter + 1'b1;
            
            if(bit_counter >= clks_per_bit - 1) begin
                bit_counter <= '0;
                uart_pulse <= 1'b1;
            end
            else begin
                uart_pulse <= 1'b0;
            end
        end
        else begin
            uart_pulse  <= 1'b0;
            bit_counter <= '0;
        end
    end
end

///////////////////////////////////////////////////////////
//                    Send Data Logic                    //
///////////////////////////////////////////////////////////

always_ff @(posedge clock_in or posedge reset_in) begin
    if(reset_in) begin
        current_state <= IDLE;
    end
    else begin
        current_state <= next_state;
    end
end

logic [7:0] write_data;
logic [7:0] read_data;
logic we;
logic re;
logic empty;
logic full;
logic rx_ack;
logic tx_ack;

assign we         = data_p_en_in_q;
assign write_data = data_p_in;

// Ring Buffer
ringbuffer #(
    .DATA_WIDTH(8),
    .BUFFER_SIZE(16)
) u_RingBuffer (
    .clk_i   (clock_in),
    .reset_i (reset_in),
    .data_i  (write_data),
    .data_o  (read_data), 
    .rx_we_i (we),
    .tx_re_i (re),
    .empty_o (empty), // Condition to start sending new datas
    .full_o  (full),  // Intended for the user to know that there's no space in the buffer
    .rx_ack_o(),      // No Use in this context
    .tx_ack_o(tx_ack) 
);

// Read Logic (RingBuffer)
always_ff @(posedge clock_in or posedge reset_in) begin
    if(reset_in) begin
        re <= 1'b0;
    end
    else begin
        if((current_state == IDLE) && !empty) begin
            re <= 1'b1;
        end
        else begin
            re <= 1'b0;
        end
    end
end

always_comb begin
    next_state = IDLE;
    uart_busy = 1'b1;

    unique case(current_state)
        IDLE:  begin
            if(!empty) begin // Theres Data Inside RingBuffer
                next_state = GET_DATA;
            end
            uart_busy = 1'b0;
        end

        GET_DATA: begin
            // Condition to go to START (RingBuffer successfully returned a new data)
            next_state = START;
            uart_busy = 1'b0;
        end

        START: begin
            next_state = START;
            if(uart_pulse) begin
                next_state = D0;
            end
        end
        D0   : begin
            next_state = D0;
            if(uart_pulse) begin
                next_state = D1;
            end
        end
        D1   : begin
            next_state = D1;
            if(uart_pulse) begin
                next_state = D2;
            end
        end
        D2   : begin
            next_state = D2;
            if(uart_pulse) begin
                next_state = D3;
            end
        end
        D3   : begin
            next_state = D3;
            if(uart_pulse) begin
                next_state = D4;
            end
        end
        D4   : begin
            next_state = D4;
            if(uart_pulse) begin
                next_state = D5;
            end
        end
        D5   : begin
            next_state = D5;
            if(uart_pulse) begin
                next_state = D6;
            end
        end
        D6   : begin
            next_state = D6;
            if(uart_pulse) begin
                next_state = D7;
            end
        end
        D7   : begin
            next_state = D7;
            if(uart_pulse) begin
                next_state = STOP;
            end
        end
        STOP : begin
            next_state = STOP;
            if(uart_pulse) begin
                next_state = IDLE; 
            end
        end
        default: begin next_state = IDLE; end
    endcase
end

logic uart_data_tx_reg; 
always_ff @(posedge clock_in or posedge reset_in) begin
    if(reset_in) begin
        uart_data_tx_reg <= 1'b1;
    end
    else begin
        case(current_state)
            START:   uart_data_tx_reg <= 1'b0;
            D0:      uart_data_tx_reg <= read_data[0];
            D1:      uart_data_tx_reg <= read_data[1];
            D2:      uart_data_tx_reg <= read_data[2];
            D3:      uart_data_tx_reg <= read_data[3];
            D4:      uart_data_tx_reg <= read_data[4];
            D5:      uart_data_tx_reg <= read_data[5];
            D6:      uart_data_tx_reg <= read_data[6];
            D7:      uart_data_tx_reg <= read_data[7];
            STOP:    uart_data_tx_reg <= 1'b1;
            default: uart_data_tx_reg <= 1'b1;
        endcase
    end
end

assign buffer_full = full;
assign uart_data_tx = uart_data_tx_reg;

endmodule