library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_codec_test is
	port (
		clk : in std_logic;
		LEDR : out std_logic_vector(8 downto 0);
		audio_scl, audio_sda : inout std_logic
	);
end entity audio_codec_test;

architecture RTL of audio_codec_test is
	constant clock_period : time := 20 ns;
	component i2c_controller
		generic(device_addr  : std_logic_vector(7 downto 0) := x"34";
			    clock_period : time := clock_period;
			    t_start_hold : time := 600 ns;
			    t_stop_hold  : time := 600 ns;
			    t_pulse_low  : time := 1300 ns;
			    t_pulse_high : time := 600 ns;
			    t_data_setup : time := 100 ns);
		port(clk          : in    std_logic;
			 rst          : in    std_logic;
			 read, en     : in    std_logic;
			 dataIn       : in    std_logic_vector(7 downto 0);
			 dataOut      : out   std_logic_vector(7 downto 0);
			 done         : out   std_logic;
			 busy         : out   std_logic;
			 SDA, SCL     : inout std_logic);
	end component i2c_controller;
	
	type state_t is (Idle, WriteAddr, WriteDone, ReadDataLow, ReadLowDone, ReadDataHigh, ReadHighDone);
	
	signal read, en, done, busy, rst : std_logic;
	signal dataIn, dataOut : std_logic_vector(7 downto 0);
	
	signal state, nextState : state_t := Idle;
begin
	controller: component i2c_controller
		port map(clk          => clk,
			     rst          => rst,
			     read         => read,
			     en           => en,
			     dataIn       => dataIn,
			     dataOut      => dataOut,
			     done         => done,
			     busy         => busy,
			     SDA          => audio_sda,
			     SCL          => audio_scl);
			     
	
	dataIn <= x"0C";
	rst <= '0';
	
	process (clk)
	begin
		if rising_edge(clk) then
			state <= nextState;
			if state = ReadLowDone then
				LEDR(7 downto 0) <= dataOut;
			elsif state = ReadHighDone then
				LEDR(8) <= dataOut(0);
			end if;
		end if;
	end process;
	
	process (state, busy, done)
	begin
		read <= '0';
		en <= '0';
		nextState <= state;
		case state is 
			when Idle =>
				nextState <= WriteAddr;
			when WriteAddr =>
				en <= '1';
				if done = '1' then
					nextState <= WriteDone;
					read <= '1';
				end if;
			when WriteDone =>
				en <= '1';
				read <= '1';
				if done = '0' then
					nextState <= ReadDataLow;
				end if;
			when ReadDataLow =>
				en <= '1';
				read <= '1';
				if done = '1' then
					nextState <= ReadLowDone;
				end if;
			when ReadLowDone =>
				en <= '1';
				read <= '1';
				if done = '0' then
					nextState <= ReadDataHigh;
				end if;
			when ReadDataHigh =>
				en <= '1';
				read <= '1';
				if done = '1' then
					nextState <= ReadHighDone;
				end if;
			when ReadHighDone =>
				if busy = '0' then
					nextState <= Idle;
				end if;
		end case;
	end process;
	
end architecture RTL;
