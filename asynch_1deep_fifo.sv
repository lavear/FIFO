module asynch_fifo_1deep #(
    parameter int DATA_WIDTH = 32
)(
    input logic wr_clk,
    input logic wr_rstn,
    input logic wr_en,
    input logic [DATA_WIDTH-1:0]wr_data;
    output logic full;

    input logic rd_clk,
    input logic rd_rstn,
    input logic rd_en,
    output logic [DATA_WIDTH-1:0]rd_data;
    output logic empty
);

logic [DATA_WIDTH-1:0] mem_array[0:1];
logic wr_ptr;
logic rd_ptr;

logic [1:0]wr_ptr_sync_chain;
logic [1:0]rd_ptr_sync_chain;
logic sync_wr_ptr;
logic sync_rd_ptr;

assign sync_wr_ptr = wr_ptr_sync_chain[1];
assign sync_rd_ptr = rd_ptr_sync_chain[1];

always_ff@(posedge wr_clk or negedge wr_rstn) begin
    if(!wr_rstn) begin
        wr_ptr <= '0;
    end else if (wr_en && !full) begin
        mem_array[wr_ptr] <= wr_data;
        wr_ptr <= ~wr_ptr;
    end
end;

always_ff@(posedge rd_clk or negedge rd_rstn) begin
    if(!rd_rstn) begin
        wr_ptr_sync_chain <= 0';
    end else begin
        wr_ptr_sync_chain <= {wr_ptr_sync_chain[0], wr_ptr};
    end
end;

assign empty = (rd_ptr == sync_wr_ptr);

always_ff @(posedge rd_clk or negedge rd_rstn) begin
    if(!rd_rstn) begin
        rd_ptr <= '0;
        rd_data <= '0;
    end else if(rd_en && !empty) begin
        rd_data <= mem_array[rd_ptr];
        rd_ptr <= ~rd_ptr;
    end
end;

always_ff @(posedge wr_clk or negedge wr_rstn) begin
    if(!wr_rstn) begin
        rd_ptr_sync_chain <= '0;
    end else begin
        rd_ptr_sync_chain <= {rd_ptr_sync_chain[0], rd_ptr};
    end
end;

assign full = (wr_ptr!= sync_rd_ptr);

endmodule


