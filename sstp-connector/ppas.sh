#!/bin/sh
DoExitAsm ()
{ echo "An error occurred while assembling $1"; exit 1; }
DoExitLink ()
{ echo "An error occurred while linking $1"; exit 1; }
echo Linking /home/marsik/Рабочий стол/sstp-connector/sstp_connector
OFS=$IFS
IFS="
"
/bin/ld -b elf64-x86-64 -m elf_x86_64  --build-id --dynamic-linker=/lib64/ld-linux-x86-64.so.2  --gc-sections -s  -L. -o '/home/marsik/Рабочий стол/sstp-connector/sstp_connector' -T '/home/marsik/Рабочий стол/sstp-connector/link92079.res' -e _start
if [ $? != 0 ]; then DoExitLink /home/marsik/Рабочий стол/sstp-connector/sstp_connector; fi
IFS=$OFS
