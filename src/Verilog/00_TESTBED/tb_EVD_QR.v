
`timescale 1ns/1ps

module tb_EVD_QR;

    // Dump waveform and annotate SDF.
    // RTL simulation uses EVD_QR_rtl.fsdb.
    // Gate-level simulation defines GATE and uses EVD_QR_gate.fsdb with SDF.
`ifdef GATE
    initial begin
        $sdf_annotate("../02_SYN/Netlist/EVD_QR_syn.sdf", dut);
        $fsdbDumpfile("EVD_QR_gate.fsdb");
        $fsdbDumpvars(0, tb_EVD_QR);
    end
`else
    initial begin
        $fsdbDumpfile("EVD_QR_rtl.fsdb");
        $fsdbDumpvars(0, tb_EVD_QR);
    end
`endif


    parameter W = 20;
    parameter FRAC_BITS = 14;
    parameter real CLK_PERIOD = 1.500;
    parameter integer MAX_SIM_CYCLES = 2000;

    reg clk;
    reg Reset;
    reg InValid;
    reg signed [W-1:0] InData1;
    reg signed [W-1:0] InData2;
    reg signed [W-1:0] InData3;

    wire OutValid;
    wire signed [W-1:0] OutData1;
    wire signed [W-1:0] OutData2;
    wire signed [W-1:0] OutData3;

    integer cycle_count;
    integer first_input_cycle;
    integer first_output_cycle;
    integer last_output_cycle;
    integer output_line_cnt;
    integer input_fd;
    integer output_fd;
    integer scan_ret;

    real in_r1;
    real in_r2;
    real in_r3;

    // Time-based measurement for M.
    real first_input_time_ns;
    real first_output_time_ns;
    real output_end_time_ns;
    real output_start_latency_cycles;
    real M_cycles_time_based;

    integer have_first_input;
    integer have_first_output;
    integer have_output_end;
    integer wait_i;

`ifdef GATE
    // The synthesized gate-level netlist has no Verilog parameters, so do not
    // override parameters in gate-level simulation. This avoids VCS AOUP
    // warnings such as "Attempt to override undefined parameter K_INV_Q".
    EVD_QR dut (
        .clk(clk),
        .Reset(Reset),
        .InValid(InValid),
        .InData1(InData1),
        .InData2(InData2),
        .InData3(InData3),
        .OutValid(OutValid),
        .OutData1(OutData1),
        .OutData2(OutData2),
        .OutData3(OutData3)
    );
`else
    EVD_QR #(
        .W(W),
        .INT_BITS(6),
        .FRAC_BITS(FRAC_BITS),
        .STAGES(10),
        .QR_ITERS(7),
        .WAIT_CYCLES(0),
        .K_INV_Q(9949)
    ) dut (
        .clk(clk),
        .Reset(Reset),
        .InValid(InValid),
        .InData1(InData1),
        .InData2(InData2),
        .InData3(InData3),
        .OutValid(OutValid),
        .OutData1(OutData1),
        .OutData2(OutData2),
        .OutData3(OutData3)
    );
`endif

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    always @(posedge clk) begin
        if (Reset) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    function signed [W-1:0] real_to_q;
        input real x;
        real scaled;
        integer q;
        integer max_q;
        integer min_q;
        begin
            scaled = x * (1 << FRAC_BITS);

            if (scaled >= 0.0)
                q = $rtoi(scaled + 0.5);
            else
                q = -$rtoi((-scaled) + 0.5);

            max_q = (1 << (W-1)) - 1;
            min_q = -(1 << (W-1));

            if (q > max_q)
                q = max_q;
            else if (q < min_q)
                q = min_q;

            real_to_q = q[W-1:0];
        end
    endfunction

    task send_row_real;
        input real x1;
        input real x2;
        input real x3;
        reg signed [W-1:0] q1;
        reg signed [W-1:0] q2;
        reg signed [W-1:0] q3;
        begin
            q1 = real_to_q(x1);
            q2 = real_to_q(x2);
            q3 = real_to_q(x3);

            @(negedge clk);
            InValid = 1'b1;
            InData1 = q1;
            InData2 = q2;
            InData3 = q3;

            // The first time InValid becomes high is the left boundary of M.
            if (!have_first_input) begin
                first_input_time_ns = $realtime;
                have_first_input = 1;
                first_input_cycle = cycle_count;
            end

            $display("[%0.3f ns] feed row(real): %f %f %f",
                     $realtime, x1, x2, x3);
            $display("[%0.3f ns] feed row(Q6.14): %0d %0d %0d",
                     $realtime, q1, q2, q3);
        end
    endtask

    task read_and_send_one_row;
        begin
            scan_ret = $fscanf(input_fd, "%f %f %f\n", in_r1, in_r2, in_r3);
            if (scan_ret != 3) begin
                $display("ERROR: failed to read one input row from matrix8_input_real.txt");
                $finish;
            end
            send_row_real(in_r1, in_r2, in_r3);
        end
    endtask

    // First output valid time.
    // This is only the start latency, not the full M.
    always @(posedge OutValid) begin
        if (!Reset && !have_first_output) begin
            first_output_time_ns = $realtime;
            have_first_output = 1;
            first_output_cycle = cycle_count;

            output_start_latency_cycles =
                (first_output_time_ns - first_input_time_ns) / (1.0 * CLK_PERIOD);

            $display("[%0.3f ns] first output valid detected",
                     first_output_time_ns);
        end
    end

    // Output end time.
    // This is the right boundary of M in the timing diagram.
    always @(negedge OutValid) begin
        if (!Reset && have_first_output && !have_output_end) begin
            output_end_time_ns = $realtime;
            have_output_end = 1;

            M_cycles_time_based =
                (output_end_time_ns - first_input_time_ns) / (1.0 * CLK_PERIOD);

            $display("[%0.3f ns] output valid ended",
                     output_end_time_ns);
        end
    end

    initial begin
        Reset = 1'b1;
        InValid = 1'b0;
        InData1 = 0;
        InData2 = 0;
        InData3 = 0;

        first_input_cycle = -1;
        first_output_cycle = -1;
        last_output_cycle = -1;
        cycle_count = 0;
        output_line_cnt = 0;

        first_input_time_ns = 0.0;
        first_output_time_ns = 0.0;
        output_end_time_ns = 0.0;
        output_start_latency_cycles = 0.0;
        M_cycles_time_based = 0.0;

        have_first_input = 0;
        have_first_output = 0;
        have_output_end = 0;

        input_fd = $fopen("../00_TESTBED/matrix8_input_real.txt", "r");
        if (input_fd == 0) begin
            input_fd = $fopen("matrix8_input_real.txt", "r");
        end
        if (input_fd == 0) begin
            $display("ERROR: cannot open matrix8_input_real.txt. Check ../00_TESTBED or current folder.");
            $finish;
        end

        output_fd = $fopen("hw_output_matrix8_q6_14.txt", "w");
        if (output_fd == 0) begin
            $display("ERROR: cannot open hw_output_matrix8_q6_14.txt for writing.");
            $finish;
        end

        $fwrite(output_fd, "# Hardware behavior simulation output for Matrix(:,:,8)\n");
        $fwrite(output_fd, "# Format: signed Q6.14 integer values\n");
        $fwrite(output_fd, "# Divide by 2^14 to obtain real values\n");

        #(5*CLK_PERIOD);
        @(negedge clk);
        Reset = 1'b0;

        $display("Reading Matrix(:,:,8) from matrix8_input_real.txt and converting to Q6.14 inside testbench.");

        read_and_send_one_row;
        read_and_send_one_row;
        read_and_send_one_row;

        @(negedge clk);
        InValid = 1'b0;

        // Input data are don't-care after InValid is deasserted.
        // Clear them to avoid extending the third row on the waveform.
        InData1 = 0;
        InData2 = 0;
        InData3 = 0;

        // Wait until the complete output window is observed.
        // This optimized scheduled RTL has a longer latency than the old
        // combinational behavior model, so do not terminate after a fixed 160 ns.
        for (wait_i = 0; wait_i < MAX_SIM_CYCLES && !have_output_end; wait_i = wait_i + 1) begin
            @(posedge clk);
        end

        if (!have_first_input) begin
            $display("ERROR: first input time was not detected.");
            $finish;
        end

        if (!have_first_output) begin
            $display("ERROR: first output time was not detected within %0d cycles.", MAX_SIM_CYCLES);
            $finish;
        end

        if (!have_output_end) begin
            $display("ERROR: OutValid falling edge was not detected within %0d cycles.", MAX_SIM_CYCLES);
            $finish;
        end

        $display("first_input_time_ns  = %0.3f", first_input_time_ns);
        $display("first_output_time_ns = %0.3f", first_output_time_ns);
        $display("output_end_time_ns   = %0.3f", output_end_time_ns);
        $display("first_input_cycle    = %0d", first_input_cycle);
        $display("first_output_cycle   = %0d", first_output_cycle);
        $display("last_output_cycle    = %0d", last_output_cycle);
        $display("clock_period_ns      = %0.3f", 1.0 * CLK_PERIOD);
        $display("output start latency = %0.3f cycles",
                 output_start_latency_cycles);
        $display("M cycles             = %0.3f cycles",
                 M_cycles_time_based);

        $fwrite(output_fd, "first_input_time_ns %.3f\n", first_input_time_ns);
        $fwrite(output_fd, "first_output_time_ns %.3f\n", first_output_time_ns);
        $fwrite(output_fd, "output_end_time_ns %.3f\n", output_end_time_ns);
        $fwrite(output_fd, "first_input_cycle %0d\n", first_input_cycle);
        $fwrite(output_fd, "first_output_cycle %0d\n", first_output_cycle);
        $fwrite(output_fd, "last_output_cycle %0d\n", last_output_cycle);
        $fwrite(output_fd, "clock_period_ns %.3f\n", 1.0 * CLK_PERIOD);
        $fwrite(output_fd, "output_start_latency_cycles %.3f\n",
                output_start_latency_cycles);
        $fwrite(output_fd, "M_cycles %.3f\n",
                M_cycles_time_based);

        $fclose(input_fd);
        $fclose(output_fd);
        $finish;
    end

    always @(negedge clk) begin
        if (!Reset && OutValid) begin
            if (output_line_cnt == 0) begin
                $display("[%0.3f ns] eigenvalues: %0d %0d %0d",
                         $realtime, OutData1, OutData2, OutData3);
                $fwrite(output_fd, "eigenvalues %0d %0d %0d\n",
                        OutData1, OutData2, OutData3);
            end else if (output_line_cnt == 1) begin
                $display("[%0.3f ns] eigenvector row 0: %0d %0d %0d",
                         $realtime, OutData1, OutData2, OutData3);
                $fwrite(output_fd, "vrow0 %0d %0d %0d\n",
                        OutData1, OutData2, OutData3);
            end else if (output_line_cnt == 2) begin
                $display("[%0.3f ns] eigenvector row 1: %0d %0d %0d",
                         $realtime, OutData1, OutData2, OutData3);
                $fwrite(output_fd, "vrow1 %0d %0d %0d\n",
                        OutData1, OutData2, OutData3);
            end else if (output_line_cnt == 3) begin
                $display("[%0.3f ns] eigenvector row 2: %0d %0d %0d",
                         $realtime, OutData1, OutData2, OutData3);
                $fwrite(output_fd, "vrow2 %0d %0d %0d\n",
                        OutData1, OutData2, OutData3);
                last_output_cycle = cycle_count;
            end

            output_line_cnt = output_line_cnt + 1;
        end
    end

endmodule

