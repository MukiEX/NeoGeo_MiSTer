//============================================================================
//  PaddleNeoGeo: one paddle axis driven by mouse/spinner deltas
//
//  Two output formats from the same pending-count accumulator:
//   - Neo Geo: 7-bit absolute position (Pop 'n Bounce style), drained
//     instantly, one unit per clock.
//   - Taito F3 "Sensor": 2-bit Gray-code quadrature on the joystick
//     RIGHT/LEFT lines, advanced at most one step per step_stb so the
//     game never sees two transitions between reads.
//
//  Counts are right/forward-positive. sens selects how many input counts
//  make one unit (1, 2, 4 or 8). Leftover counts below one unit are kept.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================

module paddle_axis (
	input              clk,
	input              enable,     // 0 clears pending counts
	input              f3_mode,    // 0: Neo Geo position, 1: F3 quadrature
	input        [1:0] sens,       // counts per unit = 1 << sens
	input              delta_stb,  // one-clock strobe, delta valid
	input signed [9:0] delta,      // right/forward-positive
	input              step_stb,   // F3: allow one quadrature step
	output reg   [6:0] pos = 7'd0, // Neo Geo position (decreases moving right, as in the stock spinner mode)
	output       [1:0] quad        // {LEFT, RIGHT}, active-high ("pressed")
);

	// Largest pending backlog, in units. Keeps a hard flick from moving the
	// F3 paddle for seconds after the mouse stops (32 steps ~ 0.5 s at 60 Hz).
	localparam signed [11:0] MAX_UNITS = 12'sd32;

	reg signed [11:0] pend  = 12'sd0;
	reg         [1:0] phase = 2'd0;

	wire signed [11:0] unit = 12'sd1 <<< sens;
	// Neo Geo mode drains one unit per clock, so it only needs overflow protection
	wire signed [11:0] lim  = f3_mode ? (MAX_UNITS <<< sens) : 12'sd1023;
	wire signed [11:0] acc  = pend + (delta_stb ? {{2{delta[9]}}, delta} : 12'sd0);

	wire take = f3_mode ? step_stb : 1'b1;
	wire fwd  = take && (acc >= unit);
	wire back = take && (acc <= -unit);

	reg signed [11:0] nxt;
	always @(*) begin
		nxt = acc;
		if (fwd)       nxt = acc - unit;
		else if (back) nxt = acc + unit;
		if (nxt > lim)        nxt = lim;
		else if (nxt < -lim)  nxt = -lim;
	end

	always @(posedge clk) begin
		if (!enable) begin
			pend <= 12'sd0;
		end else begin
			pend <= nxt;
			if (fwd) begin
				pos   <= pos - 7'd1;
				phase <= phase + 2'd1;
			end else if (back) begin
				pos   <= pos + 7'd1;
				phase <= phase - 2'd1;
			end
		end
	end

	// Gray code of the step index: 00 -> 01 -> 11 -> 10 moving right,
	// so RIGHT leads LEFT when turning right.
	assign quad = {phase[1], phase[1] ^ phase[0]};

endmodule
