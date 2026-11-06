module ringbuffer #(
        parameter int DATA_WIDTH = 8, // Bit Width
        parameter int BUFFER_SIZE = 16 // Deve ser 
)
(
        input logic clk_i,
        input logic reset_i,
        
        input  logic [DATA_WIDTH-1:0] data_i,
        output logic [DATA_WIDTH-1:0] data_o, 
        input  logic rx_we_i,
        input  logic tx_re_i,

        output logic empty_o,
        output logic full_o,

        output logic rx_ack_o,
        output logic tx_ack_o 
);

localparam int ADDR_WIDTH = $clog2(BUFFER_SIZE);

logic [DATA_WIDTH - 1 : 0] buffer [BUFFER_SIZE - 1 : 0] ;
logic [ADDR_WIDTH - 1 : 0] write_pointer;
logic [ADDR_WIDTH - 1 : 0] read_pointer;

assign empty_o = (write_pointer == read_pointer); //Same Position -> No New Data
assign full_o  = ((write_pointer + 1'b1) == read_pointer);

logic [DATA_WIDTH - 1: 0] data_i_q;
logic rx_we_ff1;
logic tx_re_ff1;
always_ff @(posedge clk_i or posedge reset_i) begin
        if(reset_i) begin
                rx_we_ff1 <= 1'b0;
                tx_re_ff1 <= 1'b0;
                data_i_q <= '0;
        end     
        else begin
                rx_we_ff1 <= rx_we_i;
                tx_re_ff1 <= tx_re_i;
                data_i_q  <= data_i;
        end
end

logic new_write;
logic new_read;
assign new_write = (!rx_we_ff1 && rx_we_i); // Rise Edge
assign new_read  = (!tx_re_ff1 && tx_re_i); // Rise Edge
assign rx_ack_o  = new_write && !full_o;
assign tx_ack_o  = new_read  && !empty_o;

always_ff @(posedge clk_i or posedge reset_i) begin
        if(reset_i) begin
                read_pointer <= '0;
        end
        else begin
                if(new_read) begin
                        read_pointer <= read_pointer + 1'b1;
                end     
        end
end

always_ff @(posedge clk_i or posedge reset_i) begin
        if(reset_i) begin
                write_pointer <= '0;
        end
        else begin
                if(new_write) begin
                        write_pointer <= write_pointer + 1'b1;
                end     
        end
end

always_ff @(posedge clk_i or posedge reset_i) begin
        if(reset_i) begin
                // Nothing
        end
        else begin
                if(new_write) begin
                        buffer[write_pointer] <= data_i_q;
                end     
        end
end

always_ff @(posedge clk_i or posedge reset_i) begin
        if(reset_i) begin
                data_o <= '0;
        end
        else begin
                if(new_read) begin
                        data_o <= buffer[read_pointer];
                end 
        end
end

endmodule