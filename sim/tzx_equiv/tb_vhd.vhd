library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
use std.textio.all; use work.tape_pkg.all;
entity tb_vhd is end;
architecture t of tb_vhd is
  signal clk : std_logic := '0';
  signal restart, ack, motor : std_logic := '0';
  signal req, cass, running, lstart, lnext, stp, stp48 : std_logic;
  signal din : unsigned(7 downto 0) := (others => '0');
begin
  dut: entity work.tzxplayer generic map (TZX_MS => 3500, NORMAL_PILOT_LEN => 30, NORMAL_SYNC1_LEN => 9, NORMAL_SYNC2_LEN => 10, NORMAL_ZERO_LEN => 12, NORMAL_ONE_LEN => 24, HEADER_PILOT_PULSES => 20, NORMAL_PILOT_PULSES => 15)
    port map (clk => clk, ce => '1', restart_tape => restart, host_tap_in => din, tzx_req => req, tzx_ack => ack,
              loop_start => lstart, loop_next => lnext, stop => stp, stop48k => stp48,
              cass_read => cass, cass_motor => motor, cass_running => running);
  process
    variable cyc, addr, wait_c : integer := 0;
    variable last : std_logic := 'X';
    variable l : line;
  begin
    for i in 0 to 600000 loop
      clk <= '1'; wait for 1 ns;
      -- entradas (tras el flanco, como un registro)
      if cyc >= 2 and cyc < 5 then restart <= '1'; else restart <= '0'; end if;
      if cyc >= 20 then motor <= '1'; end if;
      if cyc > 5 and req /= ack then
        if wait_c = 2 then
          if addr < TAPE_LEN then din <= TAPE(addr); addr := addr + 1; ack <= req; end if;
          wait_c := 0;
        else wait_c := wait_c + 1; end if;
      end if;
      if cass /= last or lstart = '1' or lnext = '1' or stp = '1' or stp48 = '1' then
        write(l, cyc); write(l, string'(" ")); write(l, std_logic'image(cass));
        write(l, string'(" ")); write(l, std_logic'image(lstart)); write(l, std_logic'image(lnext));
        write(l, std_logic'image(stp)); write(l, std_logic'image(stp48)); writeline(output, l);
        last := cass;
      end if;
      clk <= '0'; wait for 1 ns;
      cyc := cyc + 1;
    end loop;
    write(l, string'("bytes ")); write(l, addr); writeline(output, l);
    wait;
  end process;
end;
