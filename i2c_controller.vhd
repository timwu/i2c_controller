library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_controller is
	generic(
		device_addr  : std_logic_vector(6 downto 0);
		clock_period : time := 20 ns;
		t_start_hold : time := 600 ns;
		t_stop_hold  : time := 600 ns;
		t_pulse_low  : time := 1300 ns;
		t_pulse_high : time := 600 ns;
		t_data_setup : time := 100 ns
	);
	port(
		clk          : in    std_logic;
		rst          : in    std_logic;
		read, en     : in    std_logic;
		dataIn       : in    std_logic_vector(7 downto 0);

		dataOut      : out   std_logic_vector(7 downto 0);
		done         : out   std_logic;
		busy         : out   std_logic;

		currentState : out   std_logic_vector(7 downto 0);

		SDA, SCL     : inout std_logic
	);
end entity i2c_controller;

architecture RTL of i2c_controller is
	constant start_ticks      : natural := t_start_hold / clock_period;
	constant stop_ticks       : natural := t_stop_hold / clock_period;
	constant low_ticks        : natural := t_pulse_low / clock_period;
	constant high_ticks       : natural := t_pulse_high / clock_period;
	constant data_setup_ticks : natural := t_data_setup / clock_period;

	type ControllerState_t is (Idle, Start, WriteData, ReadData, WriteDone, ReadDone, Stop);
	type OutputState_t is (Low, High, Released);

	signal sclState : OutputState_t := Released;
	signal sdaState : OutputState_t := Released;

	signal controllerState   : ControllerState_t := Idle;
	signal sendingDeviceAddr : std_logic;

	signal shiftRegister : std_logic_vector(7 downto 0);
	signal shiftCount    : integer range 0 to 8;
begin
	with sclState select SCL <=
		'0' when Low,
		'1' when High,
		'H' when Released;

	with sdaState select SDA <=
		'0' when Low,
		'1' when High,
		'H' when Released;

	with controllerState select busy <=
		'0' when Idle,
		'1' when others;

	done <= '1' when controllerState = WriteDone and sendingDeviceAddr = '0' else '1' when controllerState = ReadDone else '0';

	with controllerState select currentState <=
		x"00" when Idle,
		x"01" when Start,
		x"02" when WriteData,
		x"03" when ReadData,
		x"04" when WriteDone,
		X"05" when ReadDone,
		x"06" when Stop,
		x"FF" when others;

	process(clk, rst)
		variable counter : integer range 0 to low_ticks;
	begin
		if (rst = '1') then
			controllerState <= Idle;
			sclState        <= Released;
			sdaState        <= Released;
			shiftCount      <= 0;
			counter         := 0;
		elsif rising_edge(clk) then
			if counter /= 0 then
				counter := counter - 1;
			end if;
			case controllerState is
				when Idle =>
					sclState <= Released;
					sdaState <= Released;
					if en = '1' then
						counter         := start_ticks;
						controllerState <= Start;
					end if;
				when Start =>
					sdaState <= Low;
					sclState <= High;
					if counter = 0 then
						controllerState   <= WriteData;
						shiftRegister     <= device_addr & read;
						shiftCount        <= 8;
						sendingDeviceAddr <= '1';
					end if;
				when WriteData =>
					case sclState is
						when Low =>
							if counter = data_setup_ticks then
								if shiftRegister(shiftCount - 1) = '1' then
									sdaState <= High;
								else
									sdaState <= Low;
								end if;
							end if;
							if counter = 0 then
								-- let the pullup bring it high so we can handle ack clock stretch
								sclState <= Released;
								counter  := high_ticks;
							end if;
						when High =>
							if counter = 0 then
								sclState <= Low;
								counter  := low_ticks;
							end if;
						when Released =>
							if shiftCount /= 0 and counter = 0 then
								-- ugly hack to release SDA at the same time as clock going low.
								if shiftCount = 1 then
									sdaState        <= Released;
									controllerState <= WriteDone;
								end if;
								shiftCount <= shiftCount - 1;
								sclState   <= Low;
								counter    := low_ticks;
							end if;
					end case;
				when WriteDone =>
					-- get ack and check for continue
					case sclState is
						when Low =>
							sdaState <= Released;
							if counter = 0 then
								sclState <= Released;
							end if;
						when High =>
							null;
						when Released =>
							if SCL = '1' or SCL = 'H' then
								-- setup for 1 high pulse before moving on
								counter  := high_ticks;
								sclState <= High;
								if SDA = '1' or SDA = 'H' then
									-- Device NACK'd, bail out
									controllerState <= Stop;
								else
									-- keep SDA low so we don't generate a stop condition
									sdaState <= Low;
									if en = '0' then
										controllerState <= Stop;
									elsif read = '1' then
										-- check sendingDeviceAddr to figure out if we're in a doing a repeated start
										if sendingDeviceAddr = '1' then
											sendingDeviceAddr <= '0';
											shiftRegister <= x"00";
											shiftCount <= 8;
											controllerState <= ReadData;
										else
											controllerState <= Start;
										end if;
									else
										-- keep writing so latch the dataIn and keep going
										sendingDeviceAddr <= '0';
										shiftRegister <= dataIn;
										shiftCount    <= 8;
										controllerState <= WriteData;
									end if;
								end if;
							end if;
					end case;
				when ReadData =>
					sdaState <= Released;
					case sclState is
						when Low =>
							if counter = 0 then
								sclState <= Released;
								counter  := high_ticks;
								if shiftCount /= 0 then
									shiftRegister(shiftCount - 1) <= SDA;
								end if;
							end if;
						when High =>
							if counter = 0 then
								counter  := low_ticks;
								sclState <= Low;
								if shiftCount /= 0 then
									sdaState <= Released;
								end if;
							end if;
						when Released =>
							if counter = 0 then
								if shiftCount = 1 then
									dataOut         <= shiftRegister;
									controllerState <= ReadDone;
									sclState <= Low;
									counter := low_ticks;
								else
									shiftCount <= shiftCount - 1;
									sclState   <= Low;
									counter    := low_ticks;
								end if;
							end if;
					end case;
				when ReadDone =>
					-- do ack and check for continue here
					case sclState is 
						when Low =>
							sdaState <= Low;
							if counter = 0 then
								sclState <= High;
								counter := high_ticks;
								if en = '0' then
									-- user says done, so stop the transaction
									controllerState <= Stop;
								elsif read = '1' then
									-- user says more to read, so keep reading
									shiftRegister <= x"00";
									shiftCount <= 8;
									controllerState <= ReadData;
								else
									-- user wants to switch mode, do repeated start
									counter := start_ticks;
									controllerState <= Start;
								end if;
							end if;
						when High =>
							assert False; -- not reached
						when Released =>
							if counter = 0 then
								sclState <= Low;
								counter := low_ticks;
							end if;
					end case;
				when Stop =>
					case sclState is
						when Low =>
							if counter = data_setup_ticks then
								sdaState <= Low;
							elsif counter = 0 then
								sclState <= Released;
								counter  := stop_ticks;
							end if;
						when High =>
							if counter = 0 then
								sclState <= Low;
								counter  := low_ticks;
							end if;
						when Released =>
							if counter = 0 then
								sdaState        <= Released;
								controllerState <= Idle;
							end if;
					end case;
			end case;
		end if;
	end process;

end architecture RTL;
