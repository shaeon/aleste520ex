// ============================================================================
// tb_u765.sv - Prueba del controlador de disco (rtl/cpc/u765.sv) con imagenes
// reales: simula la SD del firmware MiST, monta +img=FICHERO en la unidad A y
// hace RECALIBRATE, SEEK +c, READ ID en la cara +h y READ DATA del sector
// +r. Guarda los bytes leidos en +out y el resultado (ST0..N) en pantalla.
// ============================================================================
`timescale 1ns/1ps

module tb_u765;
    logic clk = 0;
    always #9.259 clk = ~clk;                   // 54 MHz
    logic [3:0] div = 0;
    logic ce = 0;
    always @(posedge clk) begin div <= (div == 4'd6) ? 4'd0 : div + 4'd1; ce <= (div == 4'd6); end  // 7,71 MHz, como el core

    logic        reset = 1;
    int T_ACT = 26, T_IDLE = 26;          // ciclos de 54 MHz: +t_act= +t_idle=
    initial begin void'($value$plusargs("t_act=%d", T_ACT)); void'($value$plusargs("t_idle=%d", T_IDLE)); end
    logic        a0 = 0, nRD = 1, nWR = 1;
    logic [7:0]  din = 0, dout;
    logic [1:0]  img_mounted = 0;
    logic [31:0] img_size = 0;
    logic [31:0] sd_lba;
    logic [1:0]  sd_rd, sd_wr;
    logic        sd_ack = 0, sd_buff_wr = 0;
    logic [8:0]  sd_buff_addr = 0;
    logic [7:0]  sd_buff_dout = 0, sd_buff_din;
    logic        fdc_int;

    u765 #(.CYCLES(20'd3857)) fdc (
        .clk_sys(clk), .ce(ce), .reset(reset),
        .ready(2'b11), .motor(2'b11), .available(2'b11), .fast(1'b1),
        .a0(a0), .nRD(nRD), .nWR(nWR), .din(din), .dout(dout), .int_o(fdc_int),
        .img_mounted(img_mounted), .img_wp(1'b1), .img_size(img_size),
        .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din),
        .sd_buff_wr(sd_buff_wr)
    );

    // ---- SD: la imagen en memoria
    logic [7:0] img [0:(1<<20)-1];
    logic [7:0] img_b [0:(1<<20)-1];
    int n_blocks = 0;
    always @(posedge clk) begin
        if (sd_rd != 0 && !sd_ack) begin
            automatic bit drv_b = sd_rd[1];       // la unidad se fija al aceptar la peticion, como user_io
            n_blocks++;
            repeat (20) @(posedge clk);
            sd_ack <= 1;
            for (int i = 0; i < 512; i++) begin
                @(posedge clk);
                sd_buff_addr <= 9'(i);
                sd_buff_dout <= drv_b ? img_b[sd_lba * 512 + i] : img[sd_lba * 512 + i];
                sd_buff_wr   <= 1;
                @(posedge clk);
                sd_buff_wr   <= 0;
            end
            @(posedge clk);
            sd_ack <= 0;
        end
    end

    // ---- Bus de la CPU
    task automatic rd(input bit a, output logic [7:0] v);
        @(posedge clk); a0 <= a; nRD <= 0;
        repeat (T_ACT) @(posedge clk); v = dout;       // como el acceso del core (aleste_core.sv)
        nRD <= 1; repeat (T_IDLE) @(posedge clk);
    endtask
    task automatic wr(input bit a, input logic [7:0] v);
        @(posedge clk); a0 <= a; din <= v; nWR <= 0;
        repeat (T_ACT) @(posedge clk);
        nWR <= 1; repeat (T_IDLE) @(posedge clk);
    endtask
    task automatic cmd(input logic [7:0] b);
        logic [7:0] m;
        do rd(0, m); while (!(m[7] && !m[6]));       // RQM y CPU -> FDC
        wr(1, b);
    endtask
    task automatic result(output logic [7:0] b);
        logic [7:0] m;
        do rd(0, m); while (!(m[7] && m[6]));        // RQM y FDC -> CPU
        rd(1, b);
    endtask
    task automatic sense_int(output logic [7:0] st0, output logic [7:0] pcn);
        cmd(8'h08); result(st0); result(pcn);
    endtask

    initial begin
        string f, out;
        int fd, size, c, h, r, drv;
        logic [7:0] st0, st1, st2, rc, rh, rr, rn, pcn, m, b;
        logic [7:0] data [0:511];
        int got;
        if (!$value$plusargs("img=%s", f)) $fatal(1, "falta +img=");
        if (!$value$plusargs("out=%s", out)) out = "sector.bin";
        if (!$value$plusargs("c=%d", c)) c = 0;
        if (!$value$plusargs("h=%d", h)) h = 0;
        if (!$value$plusargs("r=%d", r)) r = 1;
        if (!$value$plusargs("drv=%d", drv)) drv = 0;
        fd = $fopen(f, "rb");
        size = $fread(img, fd);
        $fclose(fd);
        $display("== %s: %0d bytes", f, size);

        repeat (20) @(posedge clk);
        reset <= 0;
        repeat (20) @(posedge clk);
        img_size <= size;
        img_mounted <= 2'b01;
        repeat (50) @(posedge clk);
        img_mounted <= 2'b00;
        if ($value$plusargs("img_b=%s", f)) begin
            fd = $fopen(f, "rb"); size = $fread(img_b, fd); $fclose(fd);
            $display("== unidad B: %s, %0d bytes", f, size);
            repeat (200000) @(posedge clk);
            img_size <= size; img_mounted <= 2'b10;
            repeat (50) @(posedge clk); img_mounted <= 2'b00;
        end
        // esperar a que termine el escaneo de la imagen
        repeat (200000) @(posedge clk);
        $display("   imagen: lista=%0d raw=%0d edsk=%0d pistas=%0d caras=%0d sectores/pista=%0d",
                 fdc.fdc.image_ready[0], fdc.image_raw[0], fdc.fdc.image_edsk[0], fdc.fdc.image_tracks[0],
                 fdc.fdc.image_sides[0] + 1, fdc.image_spt[0]);

        cmd(8'h03); cmd(8'hDF); cmd(8'h03);           // SPECIFY, sin DMA
        cmd(8'h07); cmd(8'(drv));                        // RECALIBRATE
        do begin repeat (100) @(posedge clk); sense_int(st0, pcn); end while (st0[7:6] == 2'b10);
        cmd(8'h0F); cmd({5'd0, h[0], 1'b0, drv[0]}); cmd(8'(c));   // SEEK
        do begin repeat (100) @(posedge clk); sense_int(st0, pcn); end while (st0[7:6] == 2'b10);
        $display("   SEEK: ST0=%02h PCN=%0d", st0, pcn);

        cmd(8'h4A); cmd({5'd0, h[0], 1'b0, drv[0]});         // READ ID (MFM)
        result(st0); result(st1); result(st2); result(rc); result(rh); result(rr); result(rn);
        $display("   READ ID: ST0=%02h ST1=%02h ST2=%02h  C=%0d H=%0d R=%02h N=%0d", st0, st1, st2, rc, rh, rr, rn);

        // READ DATA (MFM): C H R N EOT GPL DTL
        cmd(8'h46); cmd({5'd0, h[0], 1'b0, drv[0]}); cmd(8'(c)); cmd(8'(h)); cmd(8'(r)); cmd(8'h02);
        cmd(8'(r)); cmd(8'h2A); cmd(8'hFF);
        got = 0;
        forever begin
            rd(0, m);
            if (m[7] && m[6] && m[5]) begin rd(1, b); if (got < 512) data[got] = b; got++; end   // ejecucion
            else if (m[7] && m[6] && !m[5]) break;                                            // resultado
        end
        result(st0); result(st1); result(st2); result(rc); result(rh); result(rr); result(rn);
        $display("   READ DATA C=%0d H=%0d R=%02h: %0d bytes, ST0=%02h ST1=%02h ST2=%02h, bloques SD leidos=%0d",
                 c, h, r, got, st0, st1, st2, n_blocks);
        fd = $fopen(out, "wb");
        for (int i = 0; i < got && i < 512; i++) $fwrite(fd, "%c", data[i]);
        $fclose(fd);
        $finish;
    end

    initial begin #2s; $display("TIMEOUT"); $finish; end
endmodule
