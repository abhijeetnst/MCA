// Sequential baseline: same interface as systolic_top, one MAC unit, N^3 MAC cycles (N^3+1 from start to done).
//   for i, for j, for k: acc += A[i][k]*B[k][j]; C[i][j] = acc after k = N-1
// FSM: idle (busy=0,done=0) --start--> run (busy=1) --> done (done=1) --start--> run ...
module seq_matmul #(parameter N = 4) (
    input                         clk,
    input                         rst,
    input                         we,
    input                         sel,
    input  [$clog2(N*N)-1:0]      addr,
    input  [7:0]                  din,
    input                         start,
    output reg                    done,
    input  [$clog2(N*N)-1:0]      rd_addr,
    output [31:0]                 rd_data
);
    localparam W = $clog2(N);
    localparam [31:0] LAST = N - 1;

    reg [8*N*N-1:0]  a_buf, b_buf;
    reg [32*N*N-1:0] c_buf;

    always @(posedge clk)
        if (we) begin
            if (sel) b_buf[8*addr +: 8] <= din;
            else     a_buf[8*addr +: 8] <= din;
        end

    reg  [W-1:0] i, j, k;
    wire [31:0]  i32 = {{(32-W){1'b0}}, i};   // zero-extended copies for index math
    wire [31:0]  j32 = {{(32-W){1'b0}}, j};
    wire [31:0]  k32 = {{(32-W){1'b0}}, k};
    reg  [31:0]  acc;
    reg          busy;
    wire [31:0]  sum;

    mac u_mac (
        .a  (a_buf[8*(i32*N+k32) +: 8]),
        .b  (b_buf[8*(k32*N+j32) +: 8]),
        .acc(acc),
        .sum(sum)
    );

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else if (!busy) begin
            if (start) begin
                busy <= 1'b1;
                done <= 1'b0;
                i <= 0; j <= 0; k <= 0;
                acc <= 0;
            end
        end else if (k32 != LAST) begin
            acc <= sum;
            k   <= k + 1'b1;
        end else begin
            c_buf[32*(i32*N+j32) +: 32] <= sum;
            acc <= 0;
            k   <= 0;
            if (j32 != LAST) j <= j + 1'b1;
            else begin
                j <= 0;
                if (i32 != LAST) i <= i + 1'b1;
                else begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

    assign rd_data = c_buf[32*rd_addr +: 32];
endmodule
