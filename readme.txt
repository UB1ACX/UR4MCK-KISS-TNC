Added adjusted scheme and trace in format PCAD2002.
scheme\PCAD2002\TNC.sch
scheme\PCAD2002\TNC.pcb
scheme\PCAD2002\TNC.lib
scheme\PCAD2002\TNC Э3.pdf	- scheme in pdf
scheme\PCAD2002\pcb.jpg - trace (print-screen)

- in the original scheme replaced the microcontroller housing (PDIP28 -> TQFP32)
- added in-circuit programming connector X5
- added push-button "RESET"
- Added protection for the power supply and input signal PTT
- formalized connectors external connections (CWF-*)

avr_tnc.zip contents:

config\avrtnc_setup.exe			- AVR TNC setup program
config\src\				- Setup program source code (C + WinAPI)

microcode\configuration_bits.bmp	- Configuration bits for MCU programming
microcode\tnc2\				- MCU firmware source code
microcode\tnc2\tnc2.hex			- Firmware HEX-file

scheme\tnc.spl				- Schematics in RusPlan format
scheme\tnc.lay				- PCB in SprintLayout format
scheme\tnc.gif				- принципиальная схема в формате GIF
scheme\tnc_bottom_mirrored.gif		- PCB in GIF (mirrored for LUT)
scheme\tnc_top.gif			- components placement (in GIF)

photo\					- Some TNC / modem photos

\readme.txt				- This file. :)

During development I have used this software:
Sprint Layout 5.0, RusPlan (sPlan 5.0), AVR Studio 4 (ver. 4.13), PonyProg2000 (Ver. 2.07a Beta),
Micro$oft Visual C++ 6.0

With any questions feel free to contact me via e-mails:
ur4mck@gmail.com, info@daemon.co.ua

License: This software, schematics, PCBs and source code are distributed AS IS and
it is freeware and opensource under the terms of GNU GPL v3. You are able to modify
or redistribute this product as freeware, leaving this declaration and my callsign in the
source file headers.

Good luck!
---
Dmitry
