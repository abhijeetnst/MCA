// PE + MAC testbench: exhaustive MAC check, then directed PE tests.
`timescale 1ns/1ps
module tb_pe;
    reg clk = 0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer ref_acc, x, y, n, seed;

    // ---- MAC unit: all 65536 INT8 x INT8 products, on top of a few accumulator values
    reg  signed [7:0]  ma, mb;
    reg  signed [31:0] macc;
    wire signed [31:0] msum;
    mac u_mac (.a(ma), .b(mb), .acc(macc), .sum(msum));

    // ---- PE
    reg clr = 0, en = 0;
    reg  signed [7:0]  a_in = 0, b_in = 0;
    wire signed [7:0]  a_out, b_out;
    wire signed [31:0] acc;
    pe dut (.clk(clk), .clr(clr), .en(en), .a_in(a_in), .b_in(b_in),
            .a_out(a_out), .b_out(b_out), .acc(acc));

    task check(input [511:0] name, input integer got, input integer exp);
        if (got !== exp) begin
            $display("FAIL %0s: got %0d expected %0d", name, got, exp);
            errors = errors + 1;
        end else
            $display("PASS %0s = %0d", name, got);
    endtask

    // one PE step with inputs a,b (inputs change away from the clock edge)
    task step(input integer a, input integer b, input e);
        begin
            a_in = a; b_in = b; en = e;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        // MAC exhaustive
        n = 0;
        for (x = -128; x < 128; x = x + 1)
            for (y = -128; y < 128; y = y + 1) begin
                ma = x; mb = y;
                macc = (x * 7919) ^ y;             // varied accumulator, incl. negatives
                #1;
                if (msum !== macc + x * y) begin
                    if (n < 5) $display("FAIL mac %0d*%0d + %0d = %0d", x, y, macc, msum);
                    n = n + 1;
                end
            end
        errors = errors + n;
        $display("%0s mac exhaustive: 65536 products, %0d mismatches", n ? "FAIL" : "PASS", n);

        // PE directed tests
        @(negedge clk);
        clr = 1; @(posedge clk); #1; clr = 0;
        check("clear acc", acc, 0);
        check("clear a_out", a_out, 0);
        check("clear b_out", b_out, 0);

        a_in = 3; b_in = 4; en = 1; #1;
        check("a_out before edge (1-cycle delay)", a_out, 0);
        @(posedge clk); #1;
        check("3*4", acc, 12);
        check("a pass-through", a_out, 3);
        check("b pass-through", b_out, 4);

        step(5, -6, 1);     check("+ 5*-6", acc, -18);
        step(-128, -128, 1); check("+ -128*-128", acc, 16366);
        step(127, -128, 1); check("+ 127*-128", acc, 110);
        step(-7, -9, 1);    check("+ -7*-9", acc, 173);
        check("b_out after -9", b_out, -9);

        step(9, 9, 0);      check("en=0 holds acc", acc, 173);
        check("en=0 holds a_out", a_out, -7);
        check("en=0 holds b_out", b_out, -9);

        clr = 1; step(9, 9, 1); clr = 0;
        check("clr wins over en", acc, 0);

        // 200 random steps against a reference accumulator
        seed = 12; ref_acc = 0; n = 0;
        for (x = 0; x < 200; x = x + 1) begin
            ma = $random(seed); mb = $random(seed);
            ref_acc = ref_acc + ma * mb;
            step(ma, mb, 1);
            if (acc !== ref_acc) n = n + 1;
        end
        errors = errors + n;
        $display("%0s 200 random MAC steps, final acc %0d (ref %0d)", n ? "FAIL" : "PASS", acc, ref_acc);

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED: %0d errors", errors);
        $finish;
    end
endmodule
