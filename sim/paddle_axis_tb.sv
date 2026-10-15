// Self-checking testbench for rtl/io/paddle_axis.sv
// Run: verilator --binary --timing -Wno-DECLFILENAME sim/paddle_axis_tb.sv rtl/io/paddle_axis.sv
`timescale 1ns/1ps
module paddle_axis_tb;
	reg clk = 0;
	always #5 clk = ~clk;

	reg              enable = 1, f3_mode = 0;
	reg        [1:0] sens = 0;
	reg              delta_stb = 0, step_stb = 0;
	reg signed [9:0] delta = 0;
	wire       [6:0] pos;
	wire       [1:0] quad;

	paddle_axis dut(.clk(clk), .enable(enable), .f3_mode(f3_mode), .sens(sens),
		.delta_stb(delta_stb), .delta(delta), .step_stb(step_stb), .pos(pos), .quad(quad));

	integer errors = 0;

	task automatic check(input string what, input integer got, input integer exp);
		if (got !== exp) begin
			$display("FAIL %s: got %0d expected %0d", what, got, exp);
			errors = errors + 1;
		end else $display("ok   %s = %0d", what, got);
	endtask

	task automatic push(input integer d);
		@(negedge clk); delta = d[9:0]; delta_stb = 1;
		@(negedge clk); delta_stb = 0; delta = 0;
	endtask

	task automatic idle(input integer n);
		repeat (n) @(negedge clk);
	endtask

	// Gray index from quad {L,R}: 00->0, 01->1, 11->2, 10->3
	function automatic integer gidx(input [1:0] q);
		case (q) 2'b00: gidx = 0; 2'b01: gidx = 1; 2'b11: gidx = 2; default: gidx = 3; endcase
	endfunction

	// One step strobe; checks that at most one quadrature line changed
	integer steps_fwd, steps_back;
	task automatic step();
		reg [1:0] q_prev;
		integer d;
		q_prev = quad;
		@(negedge clk); step_stb = 1;
		@(negedge clk); step_stb = 0;
		if ((q_prev ^ quad) == 2'b11) begin
			$display("FAIL quadrature jumped two states (%b -> %b)", q_prev, quad);
			errors = errors + 1;
		end
		d = (gidx(quad) - gidx(q_prev) + 4) % 4;
		if (d == 1) steps_fwd = steps_fwd + 1;
		if (d == 3) steps_back = steps_back + 1;
	endtask

	integer i, p0;
	initial begin
		idle(3);

		// ---- Neo Geo position, 1 count per unit ----
		p0 = pos;
		push(5);   idle(10); check("neo +5 -> pos moves -5", (p0 - pos) & 127, 5);
		push(-3);  idle(10); check("neo -3 -> net -2", (p0 - pos) & 127, 2);
		push(255); idle(300); check("neo +255 wraps 7 bits", (p0 - pos) & 127, (2 + 255) & 127);

		// ---- sensitivity: 4 counts per unit, remainder kept ----
		sens = 2; p0 = pos;
		push(3);  idle(5); check("neo 1:4, +3 counts -> no move", (p0 - pos) & 127, 0);
		push(1);  idle(5); check("neo 1:4, +1 more -> one unit", (p0 - pos) & 127, 1);
		push(-8); idle(5); check("neo 1:4, -8 -> back two units", (p0 - pos) & 127, 127);
		sens = 0;

		// ---- F3 quadrature: no movement without step strobes ----
		f3_mode = 1; steps_fwd = 0; steps_back = 0;
		begin : no_strobe
			reg [1:0] q0; q0 = quad;
			push(3); idle(20);
			check("f3 holds without step_stb", quad, q0);
		end
		for (i = 0; i < 6; i = i + 1) step();
		check("f3 +3 counts -> 3 forward steps", steps_fwd, 3);
		check("f3 no extra steps", steps_back, 0);

		// Gray sequence direction: forward = RIGHT (bit0) leads LEFT (bit1)
		begin : seq
			reg [1:0] a, b;
			// bring to index 0
			while (quad != 2'b00) begin push(1); step(); end
			push(2);
			step(); a = quad;
			step(); b = quad;
			check("forward 00 -> 01 (RIGHT first)", a, 2'b01);
			check("forward 01 -> 11", b, 2'b11);
		end

		// Backward
		steps_fwd = 0; steps_back = 0;
		push(-4);
		for (i = 0; i < 8; i = i + 1) step();
		check("f3 -4 -> 4 backward steps", steps_back, 4);
		check("f3 -4 -> no forward steps", steps_fwd, 0);

		// Clamp: a huge flick yields at most 32 steps of backlog
		steps_fwd = 0; steps_back = 0;
		for (i = 0; i < 4; i = i + 1) push(255);  // 1020 counts
		for (i = 0; i < 100; i = i + 1) step();
		check("f3 backlog clamped to 32 steps", steps_fwd, 32);

		// Clamp scales with sensitivity: 1:8 -> 32 steps = 256 counts
		sens = 3; steps_fwd = 0;
		for (i = 0; i < 4; i = i + 1) push(255);
		for (i = 0; i < 100; i = i + 1) step();
		check("f3 1:8 backlog clamped to 32 steps", steps_fwd, 32);
		sens = 0;

		// Disable clears the backlog
		steps_fwd = 0;
		push(10); enable = 0; idle(2); enable = 1;
		for (i = 0; i < 20; i = i + 1) step();
		check("disable clears pending", steps_fwd, 0);

		// Delta arriving on the same clock as a step is counted
		p0 = gidx(quad);
		@(negedge clk); delta = 2; delta_stb = 1; step_stb = 1;
		@(negedge clk); delta_stb = 0; step_stb = 0; delta = 0;
		step(); step();
		check("delta + step on same clock -> 2 steps total", (gidx(quad) - p0 + 4) % 4, 2);

		if (errors == 0) $display("ALL PASS");
		else $display("%0d FAILURE(S)", errors);
		$finish;
	end
endmodule
