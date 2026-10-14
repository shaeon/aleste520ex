// ============================================================================
// sdram_model.sv - Modelo de comportamiento de una SDRAM de 16 bits (32 MB,
// 4 bancos x 8192 filas x 512 columnas) para el banco de pruebas.
//
// Funcional y con comprobaciones: avisa de ordenes que violan tiempos (tRCD,
// tRAS, tRP, tRC, tWR), de ACTIVE sobre un banco abierto, de lecturas o
// escrituras sobre un banco cerrado y de choques en el bus DQ (el
// controlador escribiendo mientras la SDRAM aun saca datos de una rafaga).
//
// Retardo cero: las ordenes se muestrean en el flanco de subida de clk y el
// dato leido cambia en el flanco CL, que es lo que ve el controlador si los
// retardos de la placa caben en la ventana (eso lo dice TimeQuest con el
// .sdc, no este modelo).
// ============================================================================
`timescale 1ns/1ps

module sdram_model #(
    parameter real T_RCD = 18.0,
    parameter real T_RAS = 42.0,
    parameter real T_RP  = 18.0,
    parameter real T_RC  = 60.0,
    parameter real T_WR  = 12.0,
    parameter real TCK   = 9.259,     // periodo de reloj (108 MHz)
    parameter bit  VERBOSE = 0
)(
    input  wire        clk,
    input  wire        cke,
    input  wire        ncs,
    input  wire        nras,
    input  wire        ncas,
    input  wire        nwe,
    input  wire [1:0]  ba,
    input  wire [12:0] a,
    input  wire [1:0]  dqm,
    input  wire [15:0] dq_in,      // lo que saca el controlador
    input  wire        dq_in_oe,   // el controlador esta conduciendo DQ
    output reg  [15:0] dq_out,
    output reg         dq_out_oe
);
    // Memoria dispersa
    logic [15:0] mem [int unsigned];

    // Estado por banco
    bit        open_  [4];
    int        row    [4];
    realtime   t_act  [4];
    realtime   t_ready[4];      // cuando el banco puede recibir ACTIVE (precarga terminada)
    realtime   t_ref = -1.0e9;

    // Registro de modo
    int cl = 2, bl = 1;
    bit interleaved = 0, write_single = 0;

    // Contadores
    int errors = 0, n_ref = 0, n_act = 0, n_rd = 0, n_wr = 0;

    // Cola de lectura: palabra a sacar en cada flanco futuro
    typedef struct { int edge_n; logic [15:0] data; } rd_slot_t;
    rd_slot_t rdq[$];
    int edge_n = 0;

    function automatic int unsigned key(input int b, input int r, input int c);
        return (b << 22) | (r << 9) | c;
    endfunction

    function automatic logic [15:0] rd_word(input int b, input int r, input int c);
        int unsigned k = key(b, r, c);
        return mem.exists(k) ? mem[k] : 16'hDEAD;
    endfunction

    task automatic err(input string s);
        errors++;
        if (errors <= 40) $display("[%0t] SDRAM ERROR: %s", $time, s);
    endtask

    initial begin
        dq_out = 16'h0; dq_out_oe = 0;
        foreach (open_[i]) begin open_[i] = 0; t_ready[i] = 0; t_act[i] = -1.0e9; end
    end

    wire [2:0] cmd = {nras, ncas, nwe};

    always @(posedge clk) begin
        realtime now = $realtime;
        int b = ba;
        edge_n++;

        // Salida de datos de lectura en este flanco
        dq_out_oe <= 0;
        while (rdq.size() > 0 && rdq[0].edge_n < edge_n) void'(rdq.pop_front());
        if (rdq.size() > 0 && rdq[0].edge_n == edge_n) begin
            dq_out    <= rdq[0].data;
            dq_out_oe <= 1;
            if (dq_in_oe) err("choque en DQ: el controlador escribe mientras la SDRAM lee");
        end

        if (cke && !ncs) begin
            case (cmd)
                3'b011: begin // ACTIVE
                    n_act++;
                    if (open_[b]) err($sformatf("ACTIVE en banco %0d ya abierto", b));
                    if (now < t_ready[b]) err($sformatf("ACTIVE banco %0d antes de terminar la precarga (tRP): faltan %0.1f ns", b, t_ready[b]-now));
                    if (now - t_act[b] < T_RC) err($sformatf("ACTIVE banco %0d: tRC %0.1f ns < %0.1f", b, now - t_act[b], T_RC));
                    if (now - t_ref < T_RC) err($sformatf("ACTIVE tras REFRESH: %0.1f ns < tRC %0.1f", now - t_ref, T_RC));
                    open_[b] = 1; row[b] = a; t_act[b] = now;
                end
                3'b101, 3'b100: begin // READ / WRITE
                    int col = a[8:0];
                    bit ap = a[10];
                    if (!open_[b]) err($sformatf("%s en banco %0d cerrado", cmd==3'b101 ? "READ":"WRITE", b));
                    if (now - t_act[b] < T_RCD - 0.01) err($sformatf("tRCD %0.1f ns < %0.1f", now - t_act[b], T_RCD));
                    if (cmd == 3'b101) begin
                        n_rd++;
                        for (int i = 0; i < bl; i++) begin
                            int c = interleaved ? ((col & ~(bl-1)) | ((col ^ i) & (bl-1)))
                                                : ((col & ~(bl-1)) | ((col + i) & (bl-1)));
                            rd_slot_t s;
                            s.edge_n = edge_n + cl + i;
                            s.data   = rd_word(b, row[b], c);
                            rdq.push_back(s);
                        end
                        if (ap) begin
                            // la precarga empieza al acabar la rafaga y nunca antes de tRAS
                            realtime t_pre = now + bl * TCK;
                            if (t_pre < t_act[b] + T_RAS) t_pre = t_act[b] + T_RAS;
                            t_ready[b] = t_pre + T_RP;
                            open_[b] = 0;
                        end
                    end else begin
                        n_wr++;
                        if (!dq_in_oe) err("WRITE sin dato en DQ");
                        begin
                            int unsigned k = key(b, row[b], col);
                            logic [15:0] w = mem.exists(k) ? mem[k] : 16'h0000;
                            if (!dqm[0]) w[7:0]  = dq_in[7:0];
                            if (!dqm[1]) w[15:8] = dq_in[15:8];
                            mem[k] = w;
                        end
                        if (ap) begin
                            realtime t_pre = now + TCK + T_WR;   // escritura de una palabra
                            if (t_pre < t_act[b] + T_RAS) t_pre = t_act[b] + T_RAS;
                            t_ready[b] = t_pre + T_RP;
                            open_[b] = 0;
                        end
                    end
                end
                3'b010: begin // PRECHARGE
                    for (int i = 0; i < 4; i++)
                        if ((a[10] || i == b) && open_[i]) begin
                            if (now - t_act[i] < T_RAS) err($sformatf("PRECHARGE banco %0d: tRAS %0.1f < %0.1f", i, now - t_act[i], T_RAS));
                            open_[i] = 0; t_ready[i] = now + T_RP;
                        end else if (a[10] || i == b) begin
                            if (t_ready[i] < now + T_RP) t_ready[i] = now + T_RP;
                        end
                end
                3'b001: begin // AUTO REFRESH
                    n_ref++;
                    for (int i = 0; i < 4; i++) begin
                        if (open_[i]) err($sformatf("REFRESH con el banco %0d abierto", i));
                        if (now < t_ready[i]) err($sformatf("REFRESH antes de acabar la precarga del banco %0d", i));
                        if (now - t_act[i] < T_RC) err($sformatf("REFRESH: tRC desde ACTIVE banco %0d %0.1f ns", i, now - t_act[i]));
                    end
                    if (now - t_ref < T_RC) err($sformatf("REFRESH tras REFRESH: %0.1f ns < tRC %0.1f", now - t_ref, T_RC));
                    t_ref = now;
                end
                3'b000: begin // MODE REGISTER
                    bl = 1 << a[2:0];
                    interleaved = a[3];
                    cl = a[6:4];
                    write_single = a[9];
                    $display("[%0t] SDRAM: modo CL=%0d BL=%0d %s, escritura %s", $time, cl, bl,
                             interleaved ? "intercalada" : "secuencial", write_single ? "simple" : "en rafaga");
                end
                default: ;
            endcase
        end
    end

endmodule
