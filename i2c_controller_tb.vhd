library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_controller_tb is
end entity i2c_controller_tb;

architecture RTL of i2c_controller_tb is
	constant clock_period : time                         := 1 ns;
	constant device_addr  : std_logic_vector(7 downto 0) := x"13";

	component i2c_controller
		generic(device_addr  : std_logic_vector(7 downto 0) := device_addr;
			    clock_period : time                         := clock_period;
			    t_start_hold : time                         := 4 ns;
			    t_stop_hold  : time                         := 4 ns;
			    t_pulse_low  : time                         := 5 ns;
			    t_pulse_high : time                         := 2 ns;
			    t_data_setup : time                         := 1 ns);
		port(clk          : in    std_logic;
			 rst          : in    std_logic;
			 read, en     : in    std_logic;
			 dataIn       : in    std_logic_vector(7 downto 0);
			 dataOut      : out   std_logic_vector(7 downto 0);
			 done         : out   std_logic;
			 busy         : out   std_logic;
			 SDA, SCL     : inout std_logic);
	end component i2c_controller;

	type tristate is (HIGH, LOW, Z);

	signal clk, rst, read, en : std_logic := '0';
	signal dataIn, dataOut    : std_logic_vector(7 downto 0);
	signal done, busy         : std_logic;
	signal SDA, SCL           : std_logic;

	signal test_done  : std_logic                    := '0';

	signal sdaBuffer      : tristate := Z;
	signal sdaBufferState : integer range 0 to 2;
	
	signal full_device_addr : std_logic_vector(7 downto 0);
begin
	uut : i2c_controller
		port map(clk          => clk,
			     rst          => rst,
			     read         => read,
			     en           => en,
			     dataIn       => dataIn,
			     dataOut      => dataOut,
			     done         => done,
			     busy         => busy,
			     SDA          => SDA,
			     SCL          => SCL);

	full_device_addr <= device_addr(7 downto 1) & read;

	SCL <= 'H';

	with sdaBuffer select SDA <=
		'H' when Z,
		'1' when High,
		'0' when Low;

	with sdaBuffer select sdaBufferState <=
		0 when Low,
		1 when High,
		2 when Z;

	clock_driver : process
	begin
		if test_done = '1' then
			wait;
		end if;
		wait for clock_period / 2;
		clk <= clk xor '1';
	end process;

	i2c_device : process
		procedure handleWrite(expected : std_logic_vector(7 downto 0)) is
			variable actual : std_logic_vector(7 downto 0) := x"00";
		begin
			assert SCL = '0';
			for i in 7 downto 0 loop
				wait until SCL = '1' or SCL = 'H';
				actual(i) := SDA;
				wait until SCL = '0';
			end loop;

			assert actual = expected report "Incorrect write byte";
			
			sdaBuffer <= Low;
			wait until SCL = '1' or SCL = 'H';
			wait until SCL = '0';
			sdaBuffer <= Z;
		end procedure;
		
		procedure waitForStart is
		begin
			wait until falling_edge(SDA);
			assert SCL /= '0' report "SCL is low during start condition.";
		end procedure;
		
		procedure waitForStop is
		begin
			wait until rising_edge(SDA);
			assert SCL /= '0' report "SCL is low on stop condition";
		end procedure;
		
		procedure write_test is
		begin
			waitForStart;

			wait until SCL = '0';

			handleWrite(full_device_addr);

			handleWrite(x"FF");

			handleWrite(x"00");

			waitForStop;
		end procedure;
		
		procedure handleRead(value : std_logic_vector(7 downto 0);
			                 ack : std_logic) is
		begin
			assert SCL = '0';
			for i in 7 downto 0 loop
				if value(i) = '1' then
					sdaBuffer <= High;
				else
					sdaBuffer <= Low;
				end if;
				wait until SCL = '1' or SCL = 'H';
				wait until SCL = '0';
			end loop;

			sdaBuffer <= Z;
			wait until SCL = '1' or SCL = 'H';
			assert SDA = ack report "Read ack doesn't match.";
			wait until SCL = '0';
		end procedure;
		
		procedure read_test is
		begin
			waitForStart;

			wait until SCL = '0';

			handleWrite(full_device_addr);

			handleRead(x"33", '0');

			handleRead(x"11", '1');

			waitForStop;
		end procedure;
	
		procedure write_read_test is
		begin
			waitForStart;
			wait until SCL = '0';
			
			handleWrite(full_device_addr);
			
			handleWrite(x"A1");
			
			waitForStart;
			
			wait until SCL = '0';
			handleWrite(full_device_addr);
			handleRead(x"B1", '0');
			handleRead(x"C2", '1');
			
			waitForStop;
		end procedure;
	begin
		
		write_test;
		
		read_test;

		write_read_test;
		wait;
	end process;

	test_user : process
		procedure write_test is
		begin
			en     <= '1';
			read   <= '0';
			dataIn <= x"FF";
			wait until done = '1';

			dataIn <= x"00";

			wait until done = '0';
			wait until done = '1';
			en <= '0';

			wait until busy = '0';
		end procedure;

		procedure read_test is
		begin
			en   <= '1';
			read <= '1';
			wait until busy = '1';

			wait until done = '1';
			assert dataOut = x"33";
			wait until done = '0';

			wait until done = '1';
			assert dataOut = x"11";
			en <= '0';
			wait until busy = '0';

		end procedure;
	
		procedure write_read_test is
		begin
			en <= '1';
			read <= '0';
			dataIn <= x"A1";
			wait until done = '1';
			
			read <= '1';
			wait until done = '1';
			assert dataOut = x"B1" report "Data read back doesn't match";
			
			wait until done = '1';
			assert dataOut = x"C2" report "Read data does not match.";
			en <= '0';
			
			wait until busy = '0';
			
		end procedure;
	begin
		write_test;

		read_test;
		
		write_read_test;

		-- done
		test_done <= '1';
		wait;
	end process;

end architecture RTL;
