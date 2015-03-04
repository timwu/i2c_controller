library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_controller_tb is
end entity i2c_controller_tb;

architecture RTL of i2c_controller_tb is
	constant clock_period : time := 1 ns;
	constant device_addr : std_logic_vector(6 downto 0) := "1110010";
	
	component i2c_controller
		generic(device_addr  : std_logic_vector(6 downto 0) := device_addr;
			    clock_period : time := clock_period;
			    t_start_hold : time := 4 ns;
			    t_stop_hold  : time := 4 ns;
			    t_pulse_low  : time := 5 ns;
			    t_pulse_high : time := 2 ns;
			    t_data_setup : time := 1 ns);
		port(clk      : in    std_logic;
			 rst      : in    std_logic;
			 read, en : in    std_logic;
			 dataIn   : in    std_logic_vector(7 downto 0);
			 dataOut  : out   std_logic_vector(7 downto 0);
			 done     : out   std_logic;
			 busy     : out   std_logic;
			 currentState : out std_logic_vector(7 downto 0);
			 SDA, SCL : inout std_logic);
	end component i2c_controller;
	
	type tristate is (HIGH, LOW, Z);
	
	signal clk, rst, read, en : std_logic := '0';
	signal dataIn, dataOut : std_logic_vector(7 downto 0);
	signal done, busy : std_logic;
	signal SDA, SCL : std_logic;
	
	signal test_done : std_logic := '0';
	signal deviceAddr : std_logic_vector(7 downto 0) := x"00";
	signal data : std_logic_vector(7 downto 0) := x"00";
	
	signal currentState : std_logic_vector(7 downto 0);
	
	signal sdaBuffer : tristate := Z;
	signal sdaBufferState : integer range 0 to 2;
begin
	
	uut: i2c_controller
		port map(clk     => clk,
			     rst     => rst,
			     read    => read,
			     en      => en,
			     dataIn  => dataIn,
			     dataOut => dataOut,
			     done    => done,
			     busy    => busy,
			     currentState => currentState,
			     SDA     => SDA,
			     SCL     => SCL);
	
	with sdaBuffer select SDA <=
		'Z' when Z,
		'1' when High,
		'0' when Low;
	
	with sdaBuffer select sdaBufferState <= 
		0 when Low,
		1 when High,
		2 when Z;
	
	clock_driver: process
	begin
		if test_done = '1' then
			wait;
		end if;
		wait for clock_period / 2;
		clk <= clk xor '1';
	end process;
	
	i2c_device: process
	begin
		-- wait for start condition
		wait until falling_edge(SDA);
		assert SCL = '1' or SCL = 'H';
		
		wait until SCL = '0';
		
		for i in 7 downto 0 loop
			wait until SCL = '1' or SCL = 'H';
			deviceAddr(i) <= SDA;
			wait until SCL = '0';
		end loop;
		
		assert deviceAddr = device_addr & '0';
		
		sdaBuffer <= Low;
		wait until SCL = '1' or SCL = 'H';
		wait until SCL = '0';
		sdaBuffer <= Z;
		
		for i in 7 downto 0 loop
			wait until SCL = '1' or SCL = 'H';
			data(i) <= SDA;
			wait until SCL = '0';
		end loop;
		
		assert data = x"FF";
		
		sdaBuffer <= Low;
		wait until SCL = '1' or SCL = 'H';
		wait until SCL = '0';
		sdaBuffer <= Z;
		
		for i in 7 downto 0 loop
			wait until SCL = '1' or SCL = 'H';
			data(i) <= SDA;
			wait until SCL = '0';
		end loop;
		
		assert data = x"00";
		
		sdaBuffer <= Low;
		wait until SCL = '1' or SCL = 'H';
		wait until SCL = '0';
		sdaBuffer <= Z;
		
		wait until rising_edge(SDA);
		assert SCL = '1' or SCL = 'H';
		-- write test done stop condition
		
		
		wait until falling_edge(SDA);
		assert SCL = '1' or SCL = 'H';
		
		deviceAddr <= x"00";
		
		wait until SCL = '0';
		
		for i in 7 downto 0 loop
			wait until SCL = '1' or SCL = 'H';
			deviceAddr(i) <= SDA;
			wait until SCL = '0';
		end loop;
		
		assert deviceAddr = device_addr & '1';
		
		sdaBuffer <= Low;
		wait until SCL = '1' or SCL = 'H';
		wait until SCL = '0';
		
		data <= x"33";
		
		for i in 7 downto 0 loop
			if data(i) = '1' then
				sdaBuffer <= High;
			else
				sdaBuffer <= Low;
			end if;
			wait until SCL = '1' or SCL = 'H';
			wait until SCL = '0';
		end loop;
			
		sdaBuffer <= Z;
		wait until SCL = '1' or SCL = 'H';
		assert SDA = '0';
		wait until SCL = '0';
		
		data <= x"11";
		
		for i in 7 downto 0 loop
			if data(i) = '1' then
				sdaBuffer <= High;
			else
				sdaBuffer <= Low;
			end if;
			wait until SCL = '1' or SCL = 'H';
			wait until SCL = '0';
		end loop;
		
		sdaBuffer <= Z;
		wait until SCL = '1' or SCL = 'H';
		assert SDA = '0';
		wait until SCL = '0';
		
		wait until rising_edge(SDA);
		assert SCL = '1' or SCL = 'H';
		
		wait;
	end process;
	
	test_user: process
	begin
		en <= '1';
		read <= '0';
		dataIn <= x"FF";
		wait until done = '1';

		dataIn <= x"00";

		wait until done = '0';
		wait until done = '1';
		en <= '0';
		
		wait until busy = '0';
		
		en <= '1';
		read <= '1';
		wait until busy = '1';
		
		wait until done = '1';
		assert dataOut = x"33";
		wait until done = '0';
		
		wait until done = '1';
		assert dataOut = x"11";
		en <= '0';
		wait until busy = '0';

		-- done
		test_done <= '1';
		wait;
	end process;
		
	
end architecture RTL;