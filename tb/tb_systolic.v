// Matmul demo: loads the same A,B into systolic_top and seq_matmul, checks both
// against a triple-loop reference model, and reports cycle counts.
//   run with +vcd to dump build/systolic.vcd
`timescale 1ns/1ps
module tb_systolic;
    parameter N = 4;
    localparam AW = $clog2(N*N);

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, we = 0, sel = 0, start = 0;
    reg [AW-1:0] addr = 0, rd_addr = 0;
    reg [7:0] din = 0;
    wire sys_done, seq_done;
    wire [31:0] sys_rd, seq_rd;

    systolic_top #(.N(N)) u_sys (.clk(clk), .rst(rst), .we(we), .sel(sel), .addr(addr), .din(din),
        .start(start), .done(sys_done), .rd_addr(rd_addr), .rd_data(sys_rd));
    seq_matmul   #(.N(N)) u_seq (.clk(clk), .rst(rst), .we(we), .sel(sel), .addr(addr), .din(din),
        .start(start), .done(seq_done), .rd_addr(rd_addr), .rd_data(seq_rd));

    integer A [0:N*N-1];
    integer B [0:N*N-1];
    integer R [0:N*N-1];
    integer i, j, k, tc, seed, errors, ncases, cyc, sys_cyc, seq_cyc;

    // write matrices through the data interface, then run and compare
    task run_case(input [255:0] name);
        integer bad;
        begin
            for (i = 0; i < N*N; i = i + 1) begin
                we = 1; sel = 0; addr = i; din = A[i]; @(posedge clk); #1;
                sel = 1;                    din = B[i]; @(posedge clk); #1;
            end
            we = 0;

            // reference model
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    R[i*N+j] = 0;
                    for (k = 0; k < N; k = k + 1)
                        R[i*N+j] = R[i*N+j] + A[i*N+k] * B[k*N+j];
                end

            // start both, count clock edges until each raises done
            start = 1; cyc = 0; sys_cyc = 0; seq_cyc = 0;
            while ((sys_cyc == 0 || seq_cyc == 0) && cyc < 100000) begin
                @(posedge clk); #1;
                start = 0; cyc = cyc + 1;
                if (sys_done && sys_cyc == 0) sys_cyc = cyc;
                if (seq_done && seq_cyc == 0) seq_cyc = cyc;
            end

            bad = 0;
            for (i = 0; i < N*N; i = i + 1) begin
                rd_addr = i; #1;
                if ($signed(sys_rd) !== R[i] || $signed(seq_rd) !== R[i]) begin
                    if (bad < 4) $display("  MISMATCH C[%0d][%0d]: expected %0d systolic %0d sequential %0d",
                                          i / N, i % N, R[i], $signed(sys_rd), $signed(seq_rd));
                    bad = bad + 1;
                end
            end
            ncases = ncases + 1;
            if (bad) errors = errors + 1;
            $display("%0s %0s (systolic %0d cycles, sequential %0d cycles)",
                     bad ? "FAIL" : "PASS", name, sys_cyc, seq_cyc);
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/systolic.vcd");
            $dumpvars(0, tb_systolic);
        end
        errors = 0; ncases = 0; seed = 2026;
        repeat (2) @(posedge clk);
        #1 rst = 0;

        // 1. small distinct values (first case: used for the waveform plot)
        for (i = 0; i < N*N; i = i + 1) begin A[i] = i + 1; B[i] = (i % 3) - 1 + 2 * (i / N); end
        run_case("counting A x small B");
        // 2. identity x random
        for (i = 0; i < N*N; i = i + 1) begin A[i] = (i / N == i % N); B[i] = ($random(seed) % 128); end
        run_case("identity x random");
        // 3. zero
        for (i = 0; i < N*N; i = i + 1) begin A[i] = 0; B[i] = $random(seed) % 128; end
        run_case("zero x random");
        // 4. all +127
        for (i = 0; i < N*N; i = i + 1) begin A[i] = 127; B[i] = 127; end
        run_case("all +127");
        // 5. all -128 (largest product, +16384 each)
        for (i = 0; i < N*N; i = i + 1) begin A[i] = -128; B[i] = -128; end
        run_case("all -128");
        // 6. mixed sign extremes
        for (i = 0; i < N*N; i = i + 1) begin A[i] = (i % 2) ? -128 : 127; B[i] = (i % 3) ? 127 : -128; end
        run_case("mixed sign extremes");
        // 7..26. random
        for (tc = 0; tc < 20; tc = tc + 1) begin
            for (i = 0; i < N*N; i = i + 1) begin
                A[i] = $signed(8'($random(seed)));
                B[i] = $signed(8'($random(seed)));
            end
            run_case("random");
        end

        $display("CYCLES N=%0d systolic=%0d sequential=%0d", N, sys_cyc, seq_cyc);
        if (errors == 0) $display("ALL TESTS PASSED (%0d cases)", ncases);
        else             $display("TESTS FAILED: %0d of %0d cases", errors, ncases);
        $finish;
    end
endmodule
