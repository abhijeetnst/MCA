// NxN grid of PEs. Row i of A enters on the left, column j of B enters on the top.
// C[i][j] is read straight from PE(i,j)'s accumulator (output-stationary).
module systolic_array #(parameter N = 4) (
    input                 clk,
    input                 clr,
    input                 en,
    input  [8*N-1:0]      a_left,   // row i    at [8*i +: 8]
    input  [8*N-1:0]      b_top,    // column j at [8*j +: 8]
    output [32*N*N-1:0]   c         // C[i][j]  at [32*(i*N+j) +: 32]
);
    // ah: a value entering PE(i,j) from the left, index i*(N+1)+j (j = N is the right edge)
    // bv: b value entering PE(i,j) from the top,  index j*(N+1)+i (i = N is the bottom edge)
    /* verilator lint_off UNUSEDSIGNAL */  // right/bottom edge values leave the array unused
    wire [8*N*(N+1)-1:0] ah;
    wire [8*N*(N+1)-1:0] bv;
    /* verilator lint_on UNUSEDSIGNAL */

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_edge
            assign ah[8*(i*(N+1)) +: 8] = a_left[8*i +: 8];
            assign bv[8*(i*(N+1)) +: 8] = b_top[8*i +: 8];
        end
        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                pe u_pe (
                    .clk  (clk),
                    .clr  (clr),
                    .en   (en),
                    .a_in (ah[8*(i*(N+1)+j)   +: 8]),
                    .b_in (bv[8*(j*(N+1)+i)   +: 8]),
                    .a_out(ah[8*(i*(N+1)+j+1) +: 8]),
                    .b_out(bv[8*(j*(N+1)+i+1) +: 8]),
                    .acc  (c[32*(i*N+j) +: 32])
                );
            end
        end
    endgenerate
endmodule
