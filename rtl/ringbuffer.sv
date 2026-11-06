module ringbuffer #(
    parameter int DATA_WIDTH  = 8,
    parameter int BUFFER_SIZE = 16
)
(
    input  logic                  clk_i,
    input  logic                  reset_i,

    input  logic [DATA_WIDTH-1:0] data_i,
    output logic [DATA_WIDTH-1:0] data_o,
    input  logic                  rx_we_i,
    input  logic                  tx_re_i,

    output logic                  empty_o,
    output logic                  full_o,

    output logic                  rx_ack_o,
    output logic                  tx_ack_o
);

localparam int ADDR_WIDTH = $clog2(BUFFER_SIZE);

logic [DATA_WIDTH-1:0] buffer [BUFFER_SIZE];
logic [ADDR_WIDTH-1:0] write_pointer;
logic [ADDR_WIDTH-1:0] read_pointer;
logic [ADDR_WIDTH-1:0] write_pointer_next;

assign write_pointer_next = write_pointer + 1'b1;

assign empty_o = (write_pointer      == read_pointer);
assign full_o  = (write_pointer_next == read_pointer);

assign rx_ack_o = rx_we_i && !full_o;
assign tx_ack_o = tx_re_i && !empty_o;

// Write Pointer
always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin       
        write_pointer <= '0;
    end
    else begin
        if (rx_ack_o) begin
                write_pointer <= write_pointer_next;
        end
    end
end

// Read Pointer
always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin       
        read_pointer <= '0;
    end
    else begin
        if (tx_ack_o) begin
                read_pointer <= read_pointer + 1'b1;
        end
    end
end

// Buffer Write
always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin       
        // Nothing
    end
    else begin
        if (rx_ack_o) begin 
            buffer[write_pointer] <= data_i;
        end
    end
end

// Buffer Read
always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin
        data_o <= '0;
    end
    else begin
        if (tx_ack_o) begin
                data_o <= buffer[read_pointer];
        end
    end
end

endmodule