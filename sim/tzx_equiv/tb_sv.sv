`timescale 1ns/1ps
module tb_sv;
  logic clk = 0, restart = 0, ack = 0, motor = 0;
  logic req, cass, running, lstart, lnext, stp, stp48;
  logic [7:0] din = 0;
  logic [7:0] tape [0:4095];
  int tape_len;
  tzxplayer #(.TZX_MS(3500), .NORMAL_PILOT_LEN(30), .NORMAL_SYNC1_LEN(9), .NORMAL_SYNC2_LEN(10),
              .NORMAL_ZERO_LEN(12), .NORMAL_ONE_LEN(24), .HEADER_PILOT_PULSES(20), .NORMAL_PILOT_PULSES(15))
    dut (.clk, .ce(1'b1), .restart_tape(restart), .host_tap_in(din), .tzx_req(req), .tzx_ack(ack),
         .loop_start(lstart), .loop_next(lnext), .stop(stp), .stop48k(stp48),
         .cass_read(cass), .cass_motor(motor), .cass_running(running));
  initial begin
    int cyc, addr, wait_c; logic last;
    int fd;
    tape_len = 0;
    $readmemh("tape.hex", tape);
    while (tape_len < 4096 && tape[tape_len] !== 8'bx) tape_len++;
    last = 1'bx; addr = 0; wait_c = 0;
    for (cyc = 0; cyc <= 600000; cyc++) begin
      #1 clk = 1;
      #0.5;
      restart = (cyc >= 2 && cyc < 5);
      if (cyc >= 20) motor = 1;
      if (cyc > 5 && req != ack) begin
        if (wait_c == 2) begin
          if (addr < tape_len) begin din = tape[addr]; addr++; ack = req; end
          wait_c = 0;
        end else wait_c++;
      end
      if (cass !== last || lstart || lnext || stp || stp48) begin
        $display("%0d '%b' '%b''%b''%b''%b'", cyc, cass, lstart, lnext, stp, stp48);
        last = cass;
      end
      #0.5 clk = 0;
    end
    $display("bytes %0d", addr);
    $finish;
  end
endmodule
