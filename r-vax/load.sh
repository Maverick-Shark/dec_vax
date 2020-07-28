#!/bin/csh

# export LD_PRELOAD=/opt/Xilinx/usb-driver/libusb-driver.so
# . /opt/Xilinx/14.7/ISE_DS/settings64.sh

setenv LD_PRELOAD /opt/Xilinx/usb-driver/libusb-driver.so
source /opt/Xilinx/14.7/ISE_DS/settings64.csh


promgen -w -p mcs -c FF -o nvax -x xcf04s -u 00000000 nvax.bit
if ($status) exit (1);

impact -batch batch_impact

exit(0);
