#!/bin/csh

# export LD_PRELOAD=/opt/Xilinx/usb-driver/libusb-driver.so
# . /opt/Xilinx/14.7/ISE_DS/settings64.sh

setenv LD_PRELOAD /opt/Xilinx/usb-driver/libusb-driver.so
source /opt/Xilinx/14.7/ISE_DS/settings64.csh

xst -intstyle ise -ifn sbi.xst -ofn sbi.syr
if ($status) exit (1);

ngdbuild -intstyle ise -dd _ngo -nt timestamp -uc open3500e.ucf -p xc3s500e-pq208-4 sbi.ngc sbi.ngd
if ($status) exit (1);

map -intstyle ise -p xc3s500e-pq208-4 -cm area -ir off -pr off -c 100 -o sbi_map.ncd sbi.ngd sbi.pcf
if ($status) exit (1);

par -w -intstyle ise -ol high -t 1 sbi_map.ncd sbi.ncd sbi.pcf
if ($status) exit (1);

trce -intstyle ise -v 3 -s 4 -n 3 -fastpaths -xml sbi.twx sbi.ncd -o sbi.twr sbi.pcf -ucf open3500e.ucf
if ($status) exit (1);

bitgen -intstyle ise -f sbi.ut sbi.ncd
if ($status) exit (1);
