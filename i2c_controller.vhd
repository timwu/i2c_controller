library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_controller is
	generic(
		device_addr  : std_logic_vector(7 downto 0);
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

		SDA, SCL     : inout std_logic
	);
end entity i2c_controller;

architecture RTL of i2c_controller is
	constant start_ticks      : natural := t_start_hold / clock_period;
	constant stop_ticks       : natural := t_stop_hold / clock_period;
	constant low_ticks        : natural := t_pulse_low / clock_period;
	constant high_ticks       : natural := t_pulse_high / clock_period;
	constant data_setup_ticks : natural := t_data_setup / clock_period;

	type ControllerState_t is (Idle, Start, SendDeviceAddr, SendDeviceAddrDone, WriteData, ReadData, WriteDone, ReadDone, Stop);
	type OutputState_t is (Low, High, Released);
	type AckState_t is (Waiting, Ok, Error);

	signal sclState : OutputState_t := Released;
	signal sdaState : OutputState_t := Released;

	signal controllerState : ControllerState_t := Idle;

	signal shiftRegister : std_logic_vector(7 downto 0);
	signal shiftCount    : integer range 0 to 8;

	signal ackState : AckState_t := Waiting;

	signal currentState : std_logic_vector(7 downto 0);
begin
	with sclState select SCL <=
		'0' when Low,
		'1' when High,
		'Z' when Released;

	with sdaState select SDA <=
		'0' when Low,
		'1' when High,
		'Z' when Released;

	with controllerState select busy <=
		'0' when Idle,
		'1' when others;

	with controllerState select done <=
		'1' when ReadDone,
		'1' when WriteDone,
		'0' when others;

	with controllerState select currentState <=
		x"00" when Idle,
		x"01" when Start,
		x"02" when WriteData,
		x"03" when ReadData,
		x"04" when WriteDone,
		X"05" when ReadDone,
		x"06" when Stop,
		x"07" when SendDeviceAddr,
		x"08" when SendDeviceAddrDone,
		x"FF" when others;

	process(clk, rst)
		variable counter : integer range 0 to high_ticks + low_ticks;

		procedure clock(state : in OutputState_t) is
		begin
			sclState <= state;
			case state is
				when Low =>
					counter := low_ticks;
				when High =>
					counter := high_ticks;
				when Released =>
					counter := high_ticks;
			end case;
		end procedure;

		procedure enterStart is
		begin
			assert SCL /= '0' report "SCL is low on enterStart";
			
			if SDA = '0' then
				clock(Low);
				sdaState <= High;
			else
				counter := start_ticks + high_ticks;
			end if;
			controllerState <= Start;
		end procedure;

		procedure enterSendDeviceAddr is
		begin
			assert SCL /= '0' report "SCL is low on enterSendDeviceAddr";

			clock(Low);
			shiftRegister   <= device_addr(7 downto 1) & read;
			shiftCount      <= 8;
			controllerState <= SendDeviceAddr;
		end procedure;

		procedure enterSendDeviceAddrDone is
		begin
			assert SCL /= '0' report "SCL is low on enterSendDeviceAddrDone";

			clock(Low);
			sdaState        <= Released;
			controllerState <= SendDeviceAddrDone;
			ackState        <= Waiting;
		end procedure;

		procedure enterWrite is
		begin
			assert SCL /= '0' report "SCL is low on enterWrite";

			clock(Low);
			sdaState        <= Low;
			shiftRegister   <= dataIn;
			shiftCount      <= 8;
			controllerState <= WriteData;
		end procedure;

		procedure enterRead is
		begin
			assert SCL /= '0' report "SCL is low on enterRead";

			clock(Low);
			sdaState        <= Released;
			shiftRegister   <= x"00";
			shiftCount      <= 8;
			controllerState <= ReadData;
		end procedure;

		procedure enterWriteDone is
		begin
			assert shiftCOunt = 0;
			assert SCL /= '0' report "SCL is low on enterWriteDone";

			clock(Low);
			sdaState        <= Released;
			controllerState <= WriteDone;
			ackState        <= Waiting;
		end procedure;

		procedure enterReadDone is
		begin
			assert shiftCount = 0;
			assert SCL /= '0' report "SCL is low on enterReadDone";

			clock(Low);
			dataOut         <= shiftRegister;
			controllerState <= ReadDone;
			ackState        <= Waiting;
		end procedure;

		procedure enterStop is
		begin
			assert SCL /= '0' report "SCL is low on enter stop";

			clock(Low);
			sdaState        <= Low;
			controllerState <= Stop;
		end procedure;

		procedure writeBit is
		begin
			assert sdaState /= Released report "SDA is released during writes.";

			case sclState is
				when Low =>
					if shiftRegister(shiftCount - 1) = '1' then
						sdaState <= High;
					else
						sdaState <= Low;
					end if;
					if counter = 0 then
						clock(High);
					end if;
				when High =>
					if counter = 0 then
						if shiftCount /= 1 then
							clock(Low);
						end if;
						shiftCount <= shiftCount - 1;
					end if;
				when Released =>
					assert False;
			end case;
		end procedure writeBit;

		procedure readBit is
		begin
			assert sdaState = Released;

			case sclState is
				when Low =>
					if counter = 0 then
						clock(High);
					end if;
				when High =>
					shiftRegister(shiftCount - 1) <= SDA;
					if counter = 0 then
						if shiftCount /= 1 then
							clock(Low);
						end if;
						shiftCount <= shiftCount - 1;
					end if;
				when Released =>
					assert False;
			end case;
		end procedure;

		procedure sendAck is
		begin
			case sclState is
				when Low =>
					if en = '0' then
						sdaState <= High;
					else
						sdaState <= Low;
					end if;
					if counter = 0 then
						clock(High);
					end if;
				when High =>
					if counter = 0 then
						sdaState <= Released;
						ackState <= Ok;
					end if;
				when Released =>
					assert False;
			end case;
		end procedure;

		procedure receiveAck is
		begin
			assert sdaState = Released report "SDA is not released on waiting for ack";

			case sclState is
				when Low =>
					if counter = 0 then
						clock(Released);
					end if;
				when High =>
					assert False report "SCL state moved to high on receive ack";
				when Released =>
					if SCL = '0' then
						-- hold the ticks until SCL is released by the slave
						counter := counter + 1;
					elsif counter = 0 then
						if SDA = '0' then
							ackState <= Ok;
						else
							ackState <= Error;
						end if;
					end if;
			end case;
		end procedure;

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
						enterStart;
					end if;
				when Start =>
					case sclState is
						when Low =>
							sdaState <= High;
							if counter = 0 then
								clock(Released);
								counter := high_ticks + start_ticks;
							end if;
						when High =>
							assert False;
						when Released =>
							if counter = start_ticks then
								sdaState <= Low;
							elsif counter = 0 then
								enterSendDeviceAddr;
							end if;
					end case;
				when SendDeviceAddr =>
					if shiftCount = 0 then
						enterSendDeviceAddrDone;
					else
						writeBit;
					end if;
				when SendDeviceAddrDone =>
					case ackState is
						when Waiting =>
							receiveAck;
						when Ok =>
							if en = '0' then
								enterStop;
							elsif read = '1' then
								enterRead;
							else
								enterWrite;
							end if;
						when Error =>
							enterStop;
					end case;
				when WriteData =>
					if shiftCount = 0 then
						enterWriteDone;
					else
						writeBit;
					end if;
				when WriteDone =>
					case ackState is
						when Waiting =>
							receiveAck;
						when Ok =>
							if en = '0' then
								enterStop;
							elsif read = '1' then
								enterStart;
							else
								enterWrite;
							end if;
						when Error =>
							enterStop;
					end case;
				when ReadData =>
					if shiftCount = 0 then
						enterReadDone;
					else
						readBit;
					end if;
				when ReadDone =>
					case ackState is
						when Waiting =>
							sendAck;
						when Ok =>
							if en = '0' then
								enterStop;
							elsif read = '1' then
								enterRead;
							else
								enterStart;
							end if;
						when Error =>
							assert False;
					end case;
				when Stop =>
					case sclState is
						when Low =>
							sdaState <= Low;
							if counter = 0 then
								clock(Released);
								counter := stop_ticks;
							end if;
						when High =>
							assert False;
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
