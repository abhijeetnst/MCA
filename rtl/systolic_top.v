// Systolic matrix-multiply accelerator, top level: C = A x B (NxN, signed INT8 in, INT32 out).
//
// Matrix data interface (same as seq_matmul):
//   write : we=1, sel=0 -> A, sel=1 -> B, addr = row*N + col, din = element
//   run   : pulse start, wait for done
//   read  : rd_addr = row*N + col -> rd_data = C[row][col]
module systolic_top #(parameter N = 4) (
    input                         clk,
    input                         rst,
    input                         we,
    input                         sel,
    input  [$clog2(N*N)-1:0]      addr,
    input  [7:0]                  din,
    input                         start,
    output                        done,
    input  [$clog2(N*N)-1:0]      rd_addr,
    output [31:0]                 rd_data
);
    // Input buffers, element (r,c) at [8*(r*N+c) +: 8]
    // plain registers, fine for small N; move to BRAM if N >= 16
    reg [8*N*N-1:0] a_buf, b_buf;

    always @(posedge clk)
        if (we) begin
            if (sel) b_buf[8*addr +: 8] <= din;
            else     a_buf[8*addr +: 8] <= din;
        end

    wire [$clog2(3*N)-1:0] t;
    wire clr, en;

    controller #(.N(N)) u_ctrl (
        .clk(clk), .rst(rst), .start(start),
        .t(t), .clr(clr), .en(en), .done(done)
    );

    // Skew by indexing (no shift registers): at step t
    //   left input of row r = A[r][t-r],  top input of column c = B[t-c][c]   (0 if out of range)
    // Both use the same test: element k of line x is sent when t == x + k.
    wire [31:0] t32 = {{(32-$clog2(3*N)){1'b0}}, t};
    reg  [8*N-1:0] a_left, b_top;
    integer x, k;
    always @* begin
        a_left = {8*N{1'b0}};
        b_top  = {8*N{1'b0}};
        for (x = 0; x < N; x = x + 1)
            for (k = 0; k < N; k = k + 1)
                if (t32 == x + k) begin
                    a_left[8*x +: 8] = a_buf[8*(x*N+k) +: 8];   // A[x][k]
                    b_top [8*x +: 8] = b_buf[8*(k*N+x) +: 8];   // B[k][x]
                end
    end

    wire [32*N*N-1:0] c;
    systolic_array #(.N(N)) u_array (
        .clk(clk), .clr(clr), .en(en),
        .a_left(a_left), .b_top(b_top), .c(c)
    );

    assign rd_data = c[32*rd_addr +: 32];
endmodule
