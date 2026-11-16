// Systolic array controller.
//   IDLE  --start--> CLEAR --> FEED (t = 0 .. 3N-3) --> DONE --start--> CLEAR ...
//   CLEAR: clr=1 for one cycle (zero accumulators and a/b pipelines)
//   FEED : en=1, t is the systolic step; top level feeds A[i][t-i] and B[t-j][j]
//   DONE : done=1, results stay in the accumulators until the next start
module controller #(parameter N = 4) (
    input                         clk,
    input                         rst,
    input                         start,
    output reg [$clog2(3*N)-1:0]  t,
    output                        clr,
    output                        en,
    output                        done
);
    localparam [1:0] IDLE = 2'd0, CLEAR = 2'd1, FEED = 2'd2, DONE = 2'd3;
    // A[i][k] meets B[k][j] in PE(i,j) at step k+i+j, so the last MAC is at t = 3N-3
    localparam [$clog2(3*N)-1:0] LAST = 3*N - 3;

    reg [1:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            t     <= 0;
        end else begin
            case (state)
                IDLE, DONE: if (start) state <= CLEAR;
                CLEAR: begin
                    state <= FEED;
                    t     <= 0;
                end
                FEED: if (t == LAST) state <= DONE;
                      else           t     <= t + 1'b1;
            endcase
        end
    end

    assign clr  = (state == CLEAR);
    assign en   = (state == FEED);
    assign done = (state == DONE);
endmodule
