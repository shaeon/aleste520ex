// ============================================================================
// tzxplayer.sv - Reproductor de cintas TZX/CDT
//
// Traduccion a SystemVerilog de tzxplayer.vhd de Gyorgy Szombathelyi (gyurco),
// del core Amstrad de MiST (https://github.com/gyurco/Amstrad_MiST), basado en
// el reproductor de TAP del C1530 de darfpga. La traduccion es linea a linea
// (mismas maquinas de estados y contadores) y se ha comprobado contra el VHDL
// original con GHDL: misma senal de salida, ciclo a ciclo, con cintas reales
// (sim/tzx_equiv/).
//
// Pide los bytes del fichero de uno en uno (tzx_req/tzx_ack, por flanco) y
// genera la senal de la cinta en cass_read, contando en estados T del
// Spectrum (3,5 MHz): en cada ce suma 3500 y avanza un estado cuando pasa de
// TZX_MS (= ciclos de ce por milisegundo).
// ============================================================================
`default_nettype none

module tzxplayer #(
    parameter int TZX_MS              = 64000,   // ciclos de ce por milisegundo
    // Por defecto, Spectrum; el Amstrad CPC usa 2000/855/855/855/1710/4095/4095
    parameter int NORMAL_PILOT_LEN    = 2168,
    parameter int NORMAL_SYNC1_LEN    = 667,
    parameter int NORMAL_SYNC2_LEN    = 735,
    parameter int NORMAL_ZERO_LEN     = 855,
    parameter int NORMAL_ONE_LEN      = 1710,
    parameter int HEADER_PILOT_PULSES = 8063,
    parameter int NORMAL_PILOT_PULSES = 3223
)(
    input  logic       clk,
    input  logic       ce,
    input  logic       restart_tape,

    input  logic [7:0] host_tap_in,     // byte pedido
    output logic       tzx_req,         // peticion de byte nuevo (por cambio)
    input  logic       tzx_ack,         // byte disponible (por cambio)
    output logic       loop_start,
    output logic       loop_next,
    output logic       stop,
    output logic       stop48k,
    output logic       cass_read,       // senal de la cinta
    input  logic       cass_motor,      // 1 = motor encendido
    output logic       cass_running     // la cinta se esta reproduciendo
);

typedef enum logic [5:0] {
    TZX_HEADER, TZX_NEWBLOCK, TZX_LOOP_START, TZX_LOOP_END, TZX_PAUSE, TZX_PAUSE2,
    TZX_STOP48K, TZX_HWTYPE, TZX_TEXT, TZX_MESSAGE, TZX_ARCHIVE_INFO, TZX_CUSTOM_INFO,
    TZX_GLUE, TZX_TONE, TZX_PULSES, TZX_DATA, TZX_NORMAL, TZX_TURBO, TZX_PLAY_TONE,
    TZX_PLAY_SYNC1, TZX_PLAY_SYNC2, TZX_PLAY_TAPBLOCK, TZX_PLAY_TAPBLOCK2,
    TZX_PLAY_TAPBLOCK3, TZX_PLAY_TAPBLOCK4, TZX_DIRECT, TZX_DIRECT2, TZX_DIRECT3
} tzx_state_t;

tzx_state_t  tzx_state;
logic [16:0] tick_cnt;
logic [23:0] wave_cnt;
logic        wave_period, wave_inverted, playing;
logic [2:0]  bit_cnt;
logic [7:0]  tzx_offset;
logic [15:0] pause_len, ms_counter, pilot_l, sync1_l, sync2_l, zero_l, one_l, pilot_pulses;
logic [3:0]  last_byte_bits;
logic [23:0] data_len;
logic [15:0] pulse_len;
logic        end_period, cass_motor_D;
logic [21:0] motor_counter;
logic [15:0] loop_iter;
logic [31:0] data_len_dword;

wire [7:0] tap_fifo_do = host_tap_in;
assign cass_read    = wave_period;
assign cass_running = playing;

// ultimo bit del bloque: bit_cnt = 8 - last_byte_bits (4 bits) o sin bits sueltos
wire last_bit = (data_len == 24'd1) &&
                (({1'b0, bit_cnt} == (4'd8 - last_byte_bits)) || (last_byte_bits == 4'd0));

always_ff @(posedge clk) begin
    if (restart_tape) begin
        tzx_offset    <= '0;
        tzx_state     <= TZX_HEADER;
        pulse_len     <= '0;
        motor_counter <= '0;
        wave_period   <= 1'b0;
        playing       <= 1'b0;
        tzx_req       <= tzx_ack;
        loop_start    <= 1'b0;
        loop_next     <= 1'b0;
        loop_iter     <= '0;
        wave_inverted <= 1'b0;
    end else begin
        // inercia del motor: no cambia de estado si se conmuta en menos de 50 ms
        // (la proteccion K17 de Opera Soft lo necesita)
        cass_motor_D <= cass_motor;
        if (cass_motor_D != cass_motor)
            motor_counter <= 22'(50 * TZX_MS);
        else if (motor_counter != 0) begin
            if (ce) motor_counter <= motor_counter - 22'd1;
        end else
            playing <= cass_motor;

        if (pulse_len != 0) begin
            if (ce) begin
                tick_cnt <= tick_cnt + 17'd3500;
                if (tick_cnt >= 17'(TZX_MS)) begin
                    tick_cnt <= tick_cnt - 17'(TZX_MS);
                    wave_cnt <= wave_cnt + 24'd1;
                    if (wave_cnt == {8'd0, pulse_len - 16'd1}) begin
                        wave_cnt <= '0;
                        if (wave_period == end_period) pulse_len <= '0;
                        else                           wave_period <= ~wave_period;
                    end
                end
            end
        end else begin
            wave_cnt <= '0;
            tick_cnt <= '0;
        end

        loop_start <= 1'b0;
        loop_next  <= 1'b0;
        stop       <= 1'b0;
        stop48k    <= 1'b0;

        if (playing && pulse_len == 0 && tzx_req == tzx_ack) begin
            tzx_req <= ~tzx_ack;                          // por defecto, pedir otro byte

            case (tzx_state)
            TZX_HEADER: begin
                wave_period   <= 1'b1;
                wave_inverted <= 1'b0;
                tzx_offset    <= tzx_offset + 8'd1;
                if (tzx_offset == 8'h0A) tzx_state <= TZX_NEWBLOCK;   // salta 9 bytes
            end

            TZX_NEWBLOCK: begin
                tzx_offset <= '0;
                ms_counter <= '0;
                case (tap_fifo_do)
                    8'h10: tzx_state <= TZX_NORMAL;
                    8'h11: tzx_state <= TZX_TURBO;
                    8'h12: tzx_state <= TZX_TONE;
                    8'h13: tzx_state <= TZX_PULSES;
                    8'h14: tzx_state <= TZX_DATA;
                    8'h15: tzx_state <= TZX_DIRECT;
                    8'h20: tzx_state <= TZX_PAUSE;
                    8'h21: tzx_state <= TZX_TEXT;         // inicio de grupo
                    8'h24: tzx_state <= TZX_LOOP_START;
                    8'h25: tzx_state <= TZX_LOOP_END;
                    8'h2A: tzx_state <= TZX_STOP48K;
                    8'h30: tzx_state <= TZX_TEXT;
                    8'h31: tzx_state <= TZX_MESSAGE;
                    8'h32: tzx_state <= TZX_ARCHIVE_INFO;
                    8'h33: tzx_state <= TZX_HWTYPE;
                    8'h35: tzx_state <= TZX_CUSTOM_INFO;
                    8'h5A: tzx_state <= TZX_GLUE;
                    default: ;                            // 18, 19, 22, 23, 26-28, 2B: sin implementar
                endcase
            end

            TZX_LOOP_START: begin
                tzx_offset <= tzx_offset + 8'd1;
                if (tzx_offset == 8'h00) loop_iter[7:0] <= tap_fifo_do;
                else if (tzx_offset == 8'h01) begin
                    loop_iter[15:8] <= tap_fifo_do;
                    tzx_state  <= TZX_NEWBLOCK;
                    loop_start <= 1'b1;
                end
            end

            TZX_LOOP_END: begin
                if (loop_iter > 16'd1) begin
                    loop_iter <= loop_iter - 16'd1;
                    loop_next <= 1'b1;
                end else
                    tzx_req <= tzx_ack;
                tzx_state <= TZX_NEWBLOCK;
            end

            TZX_PAUSE: begin
                tzx_offset <= tzx_offset + 8'd1;
                if (tzx_offset == 8'h00) pause_len[7:0] <= tap_fifo_do;
                else if (tzx_offset == 8'h01) begin
                    pause_len[15:8] <= tap_fifo_do;
                    tzx_state <= TZX_PAUSE2;
                    if (pause_len[7:0] == 8'd0 && tap_fifo_do == 8'd0) stop <= 1'b1;
                end
            end

            TZX_PAUSE2: begin
                tzx_req <= tzx_ack;
                if (ms_counter != 0) begin
                    if (ce) begin
                        ms_counter <= ms_counter - 16'd1;
                        if (ms_counter == 16'd1) begin          // nivel bajo pasado 1 ms
                            wave_inverted <= 1'b0;
                            wave_period   <= 1'b0;
                            end_period    <= 1'b0;
                        end
                    end
                end else if (pause_len != 0) begin
                    pause_len  <= pause_len - 16'd1;
                    ms_counter <= 16'(TZX_MS);
                end else
                    tzx_state <= TZX_NEWBLOCK;
            end

            TZX_STOP48K: begin
                tzx_offset <= tzx_offset + 8'd1;
                if (tzx_offset == 8'h03) begin
                    stop48k   <= 1'b1;
                    tzx_state <= TZX_NEWBLOCK;
                end
            end

            TZX_HWTYPE: begin
                tzx_offset <= tzx_offset + 8'd1;
                if (tzx_offset == 8'h00) data_len[7:0] <= tap_fifo_do;
                else if (tzx_offset == 8'h03) begin
                    if (data_len[7:0] == 8'h01) tzx_state <= TZX_NEWBLOCK;
                    else begin
                        data_len[7:0] <= data_len[7:0] - 8'd1;
                        tzx_offset    <= 8'h01;
                    end
                end
            end

            TZX_MESSAGE: tzx_state <= TZX_TEXT;           // salta el tiempo de mensaje

            TZX_TEXT: begin
                tzx_offset <= tzx_offset + 8'd1;
                if (tzx_offset == 8'h00) data_len[7:0] <= tap_fifo_do;
                else if (tzx_offset == data_len[7:0]) tzx_state <= TZX_NEWBLOCK;
            end

            TZX_ARCHIVE_INFO: begin
                tzx_offset <= tzx_offset + 8'd1;
                if (tzx_offset == 8'h00) data_len[7:0] <= tap_fifo_do;
                else if (tzx_offset == 8'h01) data_len[15:8] <= tap_fifo_do;
                else begin
                    tzx_offset <= 8'h02;
                    data_len   <= data_len - 24'd1;
                    if (data_len == 24'd1) tzx_state <= TZX_NEWBLOCK;
                end
            end

            TZX_CUSTOM_INFO: begin
                tzx_offset <= tzx_offset + 8'd1;
                if      (tzx_offset == 8'h10) data_len_dword[7:0]   <= tap_fifo_do;
                else if (tzx_offset == 8'h11) data_len_dword[15:8]  <= tap_fifo_do;
                else if (tzx_offset == 8'h12) data_len_dword[23:16] <= tap_fifo_do;
                else if (tzx_offset == 8'h13) data_len_dword[31:24] <= tap_fifo_do;
                else if (tzx_offset == 8'h14) begin
                    tzx_offset <= 8'h14;
                    if (data_len_dword == 32'd1) tzx_state <= TZX_NEWBLOCK;
                    else data_len_dword <= data_len_dword - 32'd1;
                end
            end

            TZX_GLUE: begin
                tzx_offset <= tzx_offset + 8'd1;
                if (tzx_offset == 8'h08) tzx_state <= TZX_NEWBLOCK;
            end

            TZX_TONE: begin
                tzx_offset <= tzx_offset + 8'd1;
                if      (tzx_offset == 8'h00) pilot_l[7:0]      <= tap_fifo_do;
                else if (tzx_offset == 8'h01) pilot_l[15:8]     <= tap_fifo_do;
                else if (tzx_offset == 8'h02) pilot_pulses[7:0] <= tap_fifo_do;
                else if (tzx_offset == 8'h03) begin
                    tzx_req <= tzx_ack;
                    pilot_pulses[15:8] <= tap_fifo_do;
                end else begin
                    tzx_offset <= 8'h04;
                    tzx_req    <= tzx_ack;
                    if (pilot_pulses == 16'd0) begin
                        tzx_req   <= ~tzx_ack;
                        tzx_state <= TZX_NEWBLOCK;
                    end else begin
                        pilot_pulses <= pilot_pulses - 16'd1;
                        if (!wave_inverted) begin
                            wave_period <= ~wave_period;
                            end_period  <= ~wave_period;
                        end else begin
                            wave_inverted <= 1'b0;
                            end_period    <= wave_period;
                        end
                        pulse_len <= pilot_l;
                    end
                end
            end

            TZX_PULSES: begin
                tzx_offset <= tzx_offset + 8'd1;
                if      (tzx_offset == 8'h00) data_len[7:0] <= tap_fifo_do;
                else if (tzx_offset == 8'h01) one_l[7:0]    <= tap_fifo_do;
                else if (tzx_offset == 8'h02) begin
                    tzx_req <= tzx_ack;
                    if (!wave_inverted) begin
                        wave_period <= ~wave_period;
                        end_period  <= ~wave_period;
                    end else begin
                        wave_inverted <= 1'b0;
                        end_period    <= wave_period;
                    end
                    pulse_len <= {tap_fifo_do, one_l[7:0]};
                end else if (tzx_offset == 8'h03) begin
                    if (data_len[7:0] == 8'h01) tzx_state <= TZX_NEWBLOCK;
                    else begin
                        data_len[7:0] <= data_len[7:0] - 8'd1;
                        tzx_offset    <= 8'h01;
                    end
                end
            end

            TZX_DATA: begin
                tzx_offset <= tzx_offset + 8'd1;
                if      (tzx_offset == 8'h00) zero_l[7:0]     <= tap_fifo_do;
                else if (tzx_offset == 8'h01) zero_l[15:8]    <= tap_fifo_do;
                else if (tzx_offset == 8'h02) one_l[7:0]      <= tap_fifo_do;
                else if (tzx_offset == 8'h03) one_l[15:8]     <= tap_fifo_do;
                else if (tzx_offset == 8'h04) last_byte_bits  <= tap_fifo_do[3:0];
                else if (tzx_offset == 8'h05) pause_len[7:0]  <= tap_fifo_do;
                else if (tzx_offset == 8'h06) pause_len[15:8] <= tap_fifo_do;
                else if (tzx_offset == 8'h07) data_len[7:0]   <= tap_fifo_do;
                else if (tzx_offset == 8'h08) data_len[15:8]  <= tap_fifo_do;
                else if (tzx_offset == 8'h09) begin
                    data_len[23:16] <= tap_fifo_do;
                    tzx_state <= TZX_PLAY_TAPBLOCK;
                end
            end

            TZX_NORMAL: begin
                tzx_offset <= tzx_offset + 8'd1;
                if      (tzx_offset == 8'h00) pause_len[7:0]  <= tap_fifo_do;
                else if (tzx_offset == 8'h01) pause_len[15:8] <= tap_fifo_do;
                else if (tzx_offset == 8'h02) data_len[7:0]   <= tap_fifo_do;
                else if (tzx_offset == 8'h03) begin
                    data_len[15:8]  <= tap_fifo_do;
                    data_len[23:16] <= 8'd0;
                end else if (tzx_offset == 8'h04) begin
                    // primer byte: cabecera o datos (en el Spectrum)
                    tzx_req <= tzx_ack;
                    pilot_l <= 16'(NORMAL_PILOT_LEN);
                    sync1_l <= 16'(NORMAL_SYNC1_LEN);
                    sync2_l <= 16'(NORMAL_SYNC2_LEN);
                    zero_l  <= 16'(NORMAL_ZERO_LEN);
                    one_l   <= 16'(NORMAL_ONE_LEN);
                    pilot_pulses   <= (tap_fifo_do == 8'd0) ? 16'(HEADER_PILOT_PULSES) : 16'(NORMAL_PILOT_PULSES);
                    last_byte_bits <= 4'b1000;
                    tzx_state      <= TZX_PLAY_TONE;
                end
            end

            TZX_TURBO: begin
                tzx_offset <= tzx_offset + 8'd1;
                if      (tzx_offset == 8'h00) pilot_l[7:0]       <= tap_fifo_do;
                else if (tzx_offset == 8'h01) pilot_l[15:8]      <= tap_fifo_do;
                else if (tzx_offset == 8'h02) sync1_l[7:0]       <= tap_fifo_do;
                else if (tzx_offset == 8'h03) sync1_l[15:8]      <= tap_fifo_do;
                else if (tzx_offset == 8'h04) sync2_l[7:0]       <= tap_fifo_do;
                else if (tzx_offset == 8'h05) sync2_l[15:8]      <= tap_fifo_do;
                else if (tzx_offset == 8'h06) zero_l[7:0]        <= tap_fifo_do;
                else if (tzx_offset == 8'h07) zero_l[15:8]       <= tap_fifo_do;
                else if (tzx_offset == 8'h08) one_l[7:0]         <= tap_fifo_do;
                else if (tzx_offset == 8'h09) one_l[15:8]        <= tap_fifo_do;
                else if (tzx_offset == 8'h0A) pilot_pulses[7:0]  <= tap_fifo_do;
                else if (tzx_offset == 8'h0B) pilot_pulses[15:8] <= tap_fifo_do;
                else if (tzx_offset == 8'h0C) last_byte_bits     <= tap_fifo_do[3:0];
                else if (tzx_offset == 8'h0D) pause_len[7:0]     <= tap_fifo_do;
                else if (tzx_offset == 8'h0E) pause_len[15:8]    <= tap_fifo_do;
                else if (tzx_offset == 8'h0F) data_len[7:0]      <= tap_fifo_do;
                else if (tzx_offset == 8'h10) data_len[15:8]     <= tap_fifo_do;
                else if (tzx_offset == 8'h11) begin
                    data_len[23:16] <= tap_fifo_do;
                    tzx_state <= TZX_PLAY_TONE;
                end
            end

            TZX_PLAY_TONE: begin
                tzx_req <= tzx_ack;
                if (!wave_inverted) begin
                    wave_period <= ~wave_period;
                    end_period  <= ~wave_period;
                end else begin
                    end_period    <= wave_period;
                    wave_inverted <= 1'b0;
                end
                pulse_len <= pilot_l;
                if (pilot_pulses == 16'd1) tzx_state <= TZX_PLAY_SYNC1;
                else pilot_pulses <= pilot_pulses - 16'd1;
            end

            TZX_PLAY_SYNC1: begin
                tzx_req     <= tzx_ack;
                wave_period <= ~wave_period;
                end_period  <= ~wave_period;
                pulse_len   <= sync1_l;
                tzx_state   <= TZX_PLAY_SYNC2;
            end

            TZX_PLAY_SYNC2: begin
                tzx_req     <= tzx_ack;
                wave_period <= ~wave_period;
                end_period  <= ~wave_period;
                pulse_len   <= sync2_l;
                tzx_state   <= TZX_PLAY_TAPBLOCK;
            end

            TZX_PLAY_TAPBLOCK: begin
                tzx_req   <= tzx_ack;
                bit_cnt   <= 3'b111;
                tzx_state <= TZX_PLAY_TAPBLOCK2;
            end

            TZX_PLAY_TAPBLOCK2: begin
                tzx_req <= tzx_ack;
                bit_cnt <= bit_cnt - 3'd1;
                if (bit_cnt == 3'b000 || last_bit) begin
                    data_len  <= data_len - 24'd1;
                    tzx_state <= TZX_PLAY_TAPBLOCK3;
                end
                if (!wave_inverted) begin
                    wave_period <= ~wave_period;
                    end_period  <= wave_period;            // periodo completo
                end else begin
                    end_period    <= ~wave_period;
                    wave_inverted <= 1'b0;
                end
                pulse_len <= tap_fifo_do[bit_cnt] ? one_l : zero_l;
            end

            TZX_PLAY_TAPBLOCK3: begin
                if (data_len == 24'd0) begin
                    wave_period   <= ~wave_period;
                    wave_inverted <= 1'b1;
                    tzx_state     <= TZX_PAUSE2;
                end else
                    tzx_state <= TZX_PLAY_TAPBLOCK4;
            end

            TZX_PLAY_TAPBLOCK4: begin
                tzx_req   <= tzx_ack;
                tzx_state <= TZX_PLAY_TAPBLOCK2;
            end

            TZX_DIRECT: begin
                tzx_offset <= tzx_offset + 8'd1;
                if      (tzx_offset == 8'h00) zero_l[7:0]     <= tap_fifo_do;   // aqui, duracion de un bit
                else if (tzx_offset == 8'h01) zero_l[15:8]    <= tap_fifo_do;
                else if (tzx_offset == 8'h02) pause_len[7:0]  <= tap_fifo_do;
                else if (tzx_offset == 8'h03) pause_len[15:8] <= tap_fifo_do;
                else if (tzx_offset == 8'h04) last_byte_bits  <= tap_fifo_do[3:0];
                else if (tzx_offset == 8'h05) data_len[7:0]   <= tap_fifo_do;
                else if (tzx_offset == 8'h06) data_len[15:8]  <= tap_fifo_do;
                else if (tzx_offset == 8'h07) begin
                    data_len[23:16] <= tap_fifo_do;
                    tzx_state <= TZX_DIRECT2;
                    bit_cnt   <= 3'b111;
                end
            end

            TZX_DIRECT2: begin
                tzx_req <= tzx_ack;
                bit_cnt <= bit_cnt - 3'd1;
                if (bit_cnt == 3'b000 || last_bit) begin
                    data_len  <= data_len - 24'd1;
                    tzx_state <= TZX_DIRECT3;
                end
                pulse_len   <= zero_l;
                wave_period <= tap_fifo_do[bit_cnt];
                end_period  <= tap_fifo_do[bit_cnt];
            end

            TZX_DIRECT3: begin
                if (data_len == 24'd0) begin
                    wave_inverted <= 1'b0;
                    tzx_state     <= TZX_PAUSE2;
                end else
                    tzx_state <= TZX_DIRECT2;
            end

            default: ;
            endcase
        end
    end
end

// valores iniciales (en VHDL quedan sin definir hasta el primer restart_tape)
initial begin
    tick_cnt = '0; wave_cnt = '0; end_period = 1'b0; cass_motor_D = 1'b0;
    stop = 1'b0; stop48k = 1'b0;
end

endmodule

`default_nettype wire
