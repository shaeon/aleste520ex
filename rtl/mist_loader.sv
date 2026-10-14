// ============================================================================
// mist_loader.sv - Carga de ficheros desde la SD (firmware MiST) al bus
// Wishbone del Aleste LX.
//
// Sustituye al puente UART del Aleste LX como maestro de carga. El firmware
// de la MiST/SiDi/Poseidon manda el fichero por data_io byte a byte y sin
// control de flujo, asi que los bytes pasan por una FIFO y un maestro
// Wishbone los escribe cuando el bus puede (la SDRAM compite con el video).
//
// Tipos de fichero, por indice de data_io (ioctl_index[5:0], el Fn del OSD):
//   ROM_INDEX    ROM de arranque, la carga sola el firmware (ALESTE.ROM). Los
//                primeros 16 KB van a ROM_BASE (arranque en modo nativo) y el
//                resto a ROM2_BASE (ROMs del modo CPC: AL512.BIN del 520EX).
//   IMG_INDEX    imagen en bruto a partir de IMG_BASE (pantallas, datos).
//   TAPE_INDEX   cinta (CDT/TZX) a partir de TAPE_BASE (4 MB libres de la
//                SDRAM): la lee el reproductor de cintas (rtl/cpc/tzxplayer.sv).
//   SCRIPT_INDEX guion de bus: registros de 4 bytes {A23..A16, A15..A8,
//                A7..A0, DATO}, cada uno una escritura Wishbone de 8 bits a
//                cualquier direccion (memoria, CRTC, paleta...). Hace lo
//                mismo que las escrituras del puente UART: ver tools/aleste_wbs.py
//
// Errores (pegajosos hasta reset): overflow si la FIFO se llena y timeout si
// un esclavo no responde (direccion sin dispositivo: lo corta el watchdog del
// bus con wb_err_i, o el propio contador). Con timeout el maestro suelta el
// ciclo y sigue con el siguiente, para no colgar el bus.
// ============================================================================
`default_nettype none

module mist_loader #(
    parameter int          FIFO_AW      = 11,          // 2048 entradas
    parameter logic [5:0]  ROM_INDEX    = 6'd0,
    parameter logic [5:0]  IMG_INDEX    = 6'd1,
    parameter logic [5:0]  SCRIPT_INDEX = 6'd2,
    parameter logic [5:0]  TAPE_INDEX   = 6'd3,
    parameter logic [23:0] TAPE_BASE    = 24'h800000,  // cinta: banco 2 de la SDRAM (4 MB)
    parameter logic [23:0] ROM_BASE     = 24'hC00000,  // arranque de la MMU nativa
    parameter logic [23:0] ROM_SPLIT    = 24'h004000,  // a partir de aqui el fichero de ROM va a ROM2_BASE
    parameter logic [23:0] ROM2_BASE    = 24'h400000,  // ROMs del modo CPC (AL512.BIN, ver tools/make_rom.py)
    parameter logic [23:0] IMG_BASE     = 24'h000000,
    parameter int          TIMEOUT      = 1023
)(
    input  logic        clk,
    input  logic        rst,

    // data_io
    input  logic        ioctl_download,
    input  logic [7:0]  ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [7:0]  ioctl_dout,

    // Maestro Wishbone (8 bits, mismo formato que el uart_bridge)
    output logic        wb_cyc_o,
    output logic        wb_stb_o,
    output logic        wb_we_o,
    output logic [23:0] wb_adr_o,
    output logic [7:0]  wb_dat_o,
    input  logic        wb_ack_i,
    input  logic        wb_err_i,     // error del bus (watchdog): se cuenta como timeout

    // Estado
    output logic        busy_o,       // descargando o con escrituras pendientes
    output logic        overflow_o,
    output logic        timeout_o
);

    // ------------------------------------------------------------------
    // Entrada: de bytes de data_io a registros {direccion, dato}
    // ------------------------------------------------------------------
    wire [5:0] index = ioctl_index[5:0];
    wire is_rom    = (index == ROM_INDEX);
    wire is_img    = (index == IMG_INDEX);
    wire is_script = (index == SCRIPT_INDEX);
    wire is_tape   = (index == TAPE_INDEX);

    logic [23:0] script_adr;
    logic        push;
    logic [31:0] push_data;

    always_comb begin
        push      = 1'b0;
        push_data = '0;
        if (ioctl_download && ioctl_wr) begin
            if (is_rom) begin
                push      = 1'b1;
                push_data = (ioctl_addr[23:0] < ROM_SPLIT) ? {ROM_BASE + ioctl_addr[23:0], ioctl_dout}
                                                           : {ROM2_BASE + (ioctl_addr[23:0] - ROM_SPLIT), ioctl_dout};
            end else if (is_img) begin
                push      = 1'b1;
                push_data = {IMG_BASE + ioctl_addr[23:0], ioctl_dout};
            end else if (is_tape && ioctl_addr[23:22] == 2'd0) begin   // hasta 4 MB
                push      = 1'b1;
                push_data = {TAPE_BASE + ioctl_addr[23:0], ioctl_dout};
            end else if (is_script && ioctl_addr[1:0] == 2'd3) begin
                push      = 1'b1;
                push_data = {script_adr, ioctl_dout};
            end
        end
    end

    // Los tres primeros bytes de cada registro del guion son la direccion
    always_ff @(posedge clk) begin
        if (ioctl_download && ioctl_wr && is_script) begin
            case (ioctl_addr[1:0])
                2'd0: script_adr[23:16] <= ioctl_dout;
                2'd1: script_adr[15:8]  <= ioctl_dout;
                2'd2: script_adr[7:0]   <= ioctl_dout;
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // FIFO de un solo reloj (M9K)
    // ------------------------------------------------------------------
    localparam int DEPTH = 1 << FIFO_AW;

    (* ramstyle = "no_rw_check" *) logic [31:0] mem [0:DEPTH-1];
    logic [FIFO_AW:0] wr_ptr, rd_ptr;
    logic [31:0]      q;

    wire empty = (wr_ptr == rd_ptr);
    wire full  = (wr_ptr[FIFO_AW-1:0] == rd_ptr[FIFO_AW-1:0]) &&
                 (wr_ptr[FIFO_AW] != rd_ptr[FIFO_AW]);

    always_ff @(posedge clk) begin
        if (push && !full)
            mem[wr_ptr[FIFO_AW-1:0]] <= push_data;
        q <= mem[rd_ptr[FIFO_AW-1:0]];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr     <= '0;
            overflow_o <= 1'b0;
        end else if (push) begin
            if (full) overflow_o <= 1'b1;
            else      wr_ptr     <= wr_ptr + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Maestro Wishbone: una escritura cada vez. Entre dos ciclos se baja
    // stb al menos un reloj, que el memory_arbiter lo necesita para aceptar
    // el siguiente (wb_enabled).
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {S_IDLE, S_LOAD, S_WAIT, S_GAP} state_t;
    state_t state;
    localparam int TW = $clog2(TIMEOUT + 1);
    localparam [TW-1:0] TIMER_LAST = TIMEOUT;
    logic [TW-1:0] timer;

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            rd_ptr    <= '0;
            wb_cyc_o  <= 1'b0;
            wb_stb_o  <= 1'b0;
            wb_we_o   <= 1'b0;
            wb_adr_o  <= '0;
            wb_dat_o  <= '0;
            timer     <= '0;
            timeout_o <= 1'b0;
        end else begin
            case (state)
                S_IDLE:
                    if (!empty) begin
                        rd_ptr <= rd_ptr + 1'b1;    // q tendra mem[rd_ptr] en S_LOAD
                        state  <= S_LOAD;
                    end
                S_LOAD: begin
                    wb_adr_o <= q[31:8];
                    wb_dat_o <= q[7:0];
                    wb_we_o  <= 1'b1;
                    wb_cyc_o <= 1'b1;
                    wb_stb_o <= 1'b1;
                    timer    <= '0;
                    state    <= S_WAIT;
                end
                S_WAIT:
                    if (wb_ack_i || wb_err_i || timer == TIMER_LAST) begin
                        if (!wb_ack_i) timeout_o <= 1'b1;
                        wb_cyc_o <= 1'b0;
                        wb_stb_o <= 1'b0;
                        wb_we_o  <= 1'b0;
                        state    <= S_GAP;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                S_GAP:
                    state <= S_IDLE;
            endcase
        end
    end

    assign busy_o = ioctl_download || !empty || (state != S_IDLE);

endmodule

`default_nettype wire
