module synch_fifo #(
    parameter DATA_WIDTH = 32;
    parameter DEPTH = 16;
    parameter int PROG_FULL = 14;
    parameter int PROG_EMPTY = 2;
)(
    input logic clk,
    input logic rst_n,

    input logic wr_en,
    input logic [DATA_WIDTH-1:0] wr_data,
    output logic full, 
    output logic almost_full,

    input logic rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic empty,
    output logic almost_empty
);


localparam int ADDR_WIDTH = $clog2(DEPTH);

logic [ADDR_WIDTH:0] wr_ptr, wr_ptr_next;
logic [ADDR_WIDTH:0] rd_ptr, rd_ptr_next;

logic [DATA_WIDTH-1:0] mem_array [0:DEPTH-1];

logic [ADDR_WIDTH:0] word_count;

assign wr_ptr_next = (wr_en && !full) ? wr_ptr + 1'b1 : wr_ptr;
assign rd_ptr_next = (rd_en && !empty) ? rd_ptr + 1'b1 : rd_ptr;


always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        wr_ptr <= '0;
        rd_ptr <= '0;
        rd_data <= '0;
    end else begin
        wr_ptr <= wr_ptr_next;
        rd_ptr <= rd_ptr_next;

        if(wr_en && !full) begin
            mem_array[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        end

        if(rd_en && !empty) begin
            rd_data <= mem_array[rd_ptr[ADDR_WIDTH-1:0]];
        end
    end
    always_comb begin
        word_count = wr_ptr - rd_ptr;
    end

    always_comb begin
        empty = (wr_ptr == rd_ptr);

        full = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

        almost_full = (word_count >= PROG_FULL);
        almost_empty = (word_count <= PROG_EMPTY)
    end
end
endmodule


