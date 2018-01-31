project = miniSpartan6-plus
vendor = xilinx
family = spartan6
MODEL ?= xc6slx25
part = ${MODEL}-ftg256-3 # last number -3 is speed grade
flashsize = 8192 # KB (kilobytes) - SPI flash device is M25P40
top_module = top_synth
isedir = /opt/Xilinx/ISE/14.7/ISE_DS
xil_env = . $(isedir)/settings64.sh
SHELL = /bin/bash
# openocd_interface = interface/altera-usb-blaster.cfg
# openocd_interface = ../include/ft2232-fpu1.ocd
openocd_interface = ./ft2232-generic.ocd
xc3sprog_interface = ftdi

#vfiles = \
#../../../../soc/pid/ctrlpid_v.v \
#../../../../soc/pid/simotor_v.v \
#../../../../soc/pid/rotary_decoder_v.v \

vhdfiles = \
top/top_scarab.vhd \
../synth.vhd \
../sigmadelta.vhd \
../spdif_tx.vhd \
../bram_true2p_1clk.vhd \


include ./xilinx.mk
