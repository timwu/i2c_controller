export MACOSX_DEPLOYMENT_TARGET=10.9

all: dump.vcd

analyze:
	ghdl -a *.vhd

elaborate: analyze
	ghdl -e i2c_controller_tb

dump.vcd: elaborate
	ghdl -r i2c_controller_tb --vcd=dump.vcd
	
dump.ghw: elaborate
	ghdl -r i2c_controller_tb --wave=dump.ghw
	
clean:
	ghdl --remove
	rm *.vcd
	