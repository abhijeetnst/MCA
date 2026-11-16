// MAC unit + Processing Element (PE) of the output-stationary systolic array.
/* verilator lint_off DECLFILENAME */  // mac and pe share this file on purpose

// MAC unit: sum = acc + a*b  (signed INT8 x INT8 -> 16-bit product, 32-bit accumulate)
module mac (
    input  signed [7:0]  a,
    input  signed [7:0]  b,
    input  signed [31:0] acc,
    output signed [31:0] sum
);
    wire signed [15:0] prod = a * b;
    assign sum = acc + {{16{prod[15]}}, prod};
endmodule

// PE(i,j): holds C[i][j] in acc. a moves right, b moves down, one register each.
//   clr : synchronous clear of acc and the a/b pipeline registers (start of a run)
//   en  : advance one systolic step (MAC + pass a/b on)
module pe (
    input                    clk,
    input                    clr,
    input                    en,
    input      signed [7:0]  a_in,
    input      signed [7:0]  b_in,
    output reg signed [7:0]  a_out,
    output reg signed [7:0]  b_out,
    output reg signed [31:0] acc
);
    wire signed [31:0] sum;
    mac u_mac (.a(a_in), .b(b_in), .acc(acc), .sum(sum));

    always @(posedge clk) begin
        if (clr) begin
            a_out <= 8'sd0;
            b_out <= 8'sd0;
            acc   <= 32'sd0;
        end else if (en) begin
            a_out <= a_in;
            b_out <= b_in;
            acc   <= sum;
        end
    end
endmodule
