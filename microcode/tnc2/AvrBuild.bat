@ECHO OFF
"C:\Program Files\Atmel\AVR Tools\AvrAssembler2\avrasm2.exe" -S "C:\avr-projects\tnc2\labels.tmp" -fI -W+ie -o "C:\avr-projects\tnc2\tnc2.hex" -d "C:\avr-projects\tnc2\tnc2.obj" -e "C:\avr-projects\tnc2\tnc2.eep" -m "C:\avr-projects\tnc2\tnc2.map" "C:\avr-projects\tnc2\tnc2.asm"
