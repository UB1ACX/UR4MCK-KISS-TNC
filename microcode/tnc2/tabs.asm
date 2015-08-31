;************************************************************************
;		 		Various Constants										*
;				  Version 0.0.3											*
;			     (c) 2006-2007 UR4MCK									*
;																		*
;************************************************************************

.org CRC_TAB_ADDR

		; HDLC CRC16 constants table
CRCTAB:
        .dw 0x0000, 0x1189, 0x2312, 0x329b, 0x4624, 0x57ad, 0x6536, 0x74bf
        .dw 0x8c48, 0x9dc1, 0xaf5a, 0xbed3, 0xca6c, 0xdbe5, 0xe97e, 0xf8f7
        .dw 0x1081, 0x0108, 0x3393, 0x221a, 0x56a5, 0x472c, 0x75b7, 0x643e
        .dw 0x9cc9, 0x8d40, 0xbfdb, 0xae52, 0xdaed, 0xcb64, 0xf9ff, 0xe876
        .dw 0x2102, 0x308b, 0x0210, 0x1399, 0x6726, 0x76af, 0x4434, 0x55bd
        .dw 0xad4a, 0xbcc3, 0x8e58, 0x9fd1, 0xeb6e, 0xfae7, 0xc87c, 0xd9f5
        .dw 0x3183, 0x200a, 0x1291, 0x0318, 0x77a7, 0x662e, 0x54b5, 0x453c
        .dw 0xbdcb, 0xac42, 0x9ed9, 0x8f50, 0xfbef, 0xea66, 0xd8fd, 0xc974

        .dw 0x4204, 0x538d, 0x6116, 0x709f, 0x0420, 0x15a9, 0x2732, 0x36bb
        .dw 0xce4c, 0xdfc5, 0xed5e, 0xfcd7, 0x8868, 0x99e1, 0xab7a, 0xbaf3
        .dw 0x5285, 0x430c, 0x7197, 0x601e, 0x14a1, 0x0528, 0x37b3, 0x263a
        .dw 0xdecd, 0xcf44, 0xfddf, 0xec56, 0x98e9, 0x8960, 0xbbfb, 0xaa72
        .dw 0x6306, 0x728f, 0x4014, 0x519d, 0x2522, 0x34ab, 0x0630, 0x17b9
        .dw 0xef4e, 0xfec7, 0xcc5c, 0xddd5, 0xa96a, 0xb8e3, 0x8a78, 0x9bf1
        .dw 0x7387, 0x620e, 0x5095, 0x411c, 0x35a3, 0x242a, 0x16b1, 0x0738
        .dw 0xffcf, 0xee46, 0xdcdd, 0xcd54, 0xb9eb, 0xa862, 0x9af9, 0x8b70

        .dw 0x8408, 0x9581, 0xa71a, 0xb693, 0xc22c, 0xd3a5, 0xe13e, 0xf0b7
        .dw 0x0840, 0x19c9, 0x2b52, 0x3adb, 0x4e64, 0x5fed, 0x6d76, 0x7cff
        .dw 0x9489, 0x8500, 0xb79b, 0xa612, 0xd2ad, 0xc324, 0xf1bf, 0xe036
        .dw 0x18c1, 0x0948, 0x3bd3, 0x2a5a, 0x5ee5, 0x4f6c, 0x7df7, 0x6c7e
        .dw 0xa50a, 0xb483, 0x8618, 0x9791, 0xe32e, 0xf2a7, 0xc03c, 0xd1b5
        .dw 0x2942, 0x38cb, 0x0a50, 0x1bd9, 0x6f66, 0x7eef, 0x4c74, 0x5dfd
        .dw 0xb58b, 0xa402, 0x9699, 0x8710, 0xf3af, 0xe226, 0xd0bd, 0xc134
        .dw 0x39c3, 0x284a, 0x1ad1, 0x0b58, 0x7fe7, 0x6e6e, 0x5cf5, 0x4d7c

        .dw 0xc60c, 0xd785, 0xe51e, 0xf497, 0x8028, 0x91a1, 0xa33a, 0xb2b3
        .dw 0x4a44, 0x5bcd, 0x6956, 0x78df, 0x0c60, 0x1de9, 0x2f72, 0x3efb
        .dw 0xd68d, 0xc704, 0xf59f, 0xe416, 0x90a9, 0x8120, 0xb3bb, 0xa232
        .dw 0x5ac5, 0x4b4c, 0x79d7, 0x685e, 0x1ce1, 0x0d68, 0x3ff3, 0x2e7a
        .dw 0xe70e, 0xf687, 0xc41c, 0xd595, 0xa12a, 0xb0a3, 0x8238, 0x93b1
        .dw 0x6b46, 0x7acf, 0x4854, 0x59dd, 0x2d62, 0x3ceb, 0x0e70, 0x1ff9
        .dw 0xf78f, 0xe606, 0xd49d, 0xc514, 0xb1ab, 0xa022, 0x92b9, 0x8330
        .dw 0x7bc7, 0x6a4e, 0x58d5, 0x495c, 0x3de3, 0x2c6a, 0x1ef1, 0x0f78

.org METRIC_TAB_ADDR

		; Metric table used for soft decision about symbol
METRIC_TAB:
		.db $00, $0c, $19, $26, $26, $33, $3f, $4c
		.db $33, $3f, $4c, $59, $59, $66, $72, $7f
		.db $33, $3f, $4c, $59, $59, $66, $72, $7f
		.db $66, $72, $7f, $8c, $8c, $99, $a5, $b2
		.db $26, $33, $3f, $4c, $4c, $59, $66, $72
		.db $59, $66, $72, $7f, $7f, $8c, $99, $a5
		.db $59, $66, $72, $7f, $7f, $8c, $99, $a5
		.db $8c, $99, $a5, $b2, $b2, $bf, $cc, $d8
		.db $19, $26, $33, $3f, $3f, $4c, $59, $66
		.db $4c, $59, $66, $72, $72, $7f, $8c, $99
		.db $4c, $59, $66, $72, $72, $7f, $8c, $99
		.db $7f, $8c, $99, $a5, $a5, $b2, $bf, $cc
		.db $3f, $4c, $59, $66, $66, $72, $7f, $8c
		.db $72, $7f, $8c, $99, $99, $a5, $b2, $bf
		.db $72, $7f, $8c, $99, $99, $a5, $b2, $bf
		.db $a5, $b2, $bf, $cc, $cc, $d8, $e5, $f2
		.db $0c, $19, $26, $33, $33, $3f, $4c, $59
		.db $3f, $4c, $59, $66, $66, $72, $7f, $8c
		.db $3f, $4c, $59, $66, $66, $72, $7f, $8c
		.db $72, $7f, $8c, $99, $99, $a5, $b2, $bf
		.db $33, $3f, $4c, $59, $59, $66, $72, $7f
		.db $66, $72, $7f, $8c, $8c, $99, $a5, $b2
		.db $66, $72, $7f, $8c, $8c, $99, $a5, $b2
		.db $99, $a5, $b2, $bf, $bf, $cc, $d8, $e5
		.db $26, $33, $3f, $4c, $4c, $59, $66, $72
		.db $59, $66, $72, $7f, $7f, $8c, $99, $a5
		.db $59, $66, $72, $7f, $7f, $8c, $99, $a5
		.db $8c, $99, $a5, $b2, $b2, $bf, $cc, $d8
		.db $4c, $59, $66, $72, $72, $7f, $8c, $99
		.db $7f, $8c, $99, $a5, $a5, $b2, $bf, $cc
		.db $7f, $8c, $99, $a5, $a5, $b2, $bf, $cc
		.db $b2, $bf, $cc, $d8, $d8, $e5, $f2, $ff

.org COS_TAB_ADDR

		; Two cosine tables used as coefficients for two matched filters
COS_TAB:
		.db 63, 58, 44, 24, 0, -24, -44, -58, -62, -58, -44, -24, 0, 24, 44, 58 	; For signal #1 1200 Hz
		.db 76, 56, 9, -42, -72, -67, -29, 24, 65, 73, 46, -5, -53, -74, -59, -14 	; For signal #2 2200 Hz (x 1.2)

;		.db 63, 47, 8, -35, -60, -56, -24, 20, 54, 61, 38, -4, -44, -62, -49, -12 	; For signal #2 2200 Hz (x 1.0)
;		.db 69, 52, 9, -38, -66, -62, -26, 22, 59, 67, 42, -4, -48, -68, -54, -13 	; For signal #2 2200 Hz (x 1.1)
;		.db 82, 61, 10, -45, -78, -73, -31, 26, 70, 79, 49, -5, -57, -81, -62, -16 	; For signal #2 2200 Hz (x 1.3)
;		.db 88, 66, 11, -49, -84, -78, -34, 28, 76, 85, 53, -6, -62, -87, -69, -17 	; For signal #2 2200 Hz (x 1.4)
;		.db 94, 70, 12, -52, -90, -84, -36, 30, 81, 91, 57, -6, -66, -94, -73, -18 	; For signal #2 2200 Hz (x 1.5)

.org SINE_TAB_ADDR

		; Sinus table used by PWM DAC (24 points)
SINE_TAB_F:
		.db 128, 160, 191, 218, 238, 251, 255, 251, 238, 218, 191, 160, 128, 95, 64, 37, 17, 4, 0, 4, 17, 37, 64, 95


		; Texts used in various test modes
BANNER1:
		.db $0d, $0a, "AVRTNC & AFSK MODEM Version 0.0.3", $0d, $0a, $0d, $0a, 0
BANNER2:
		.db "Press [Space] to toggle between test modes ", $0d, $0a, 0
BANNER_M0:
		.db "* TEST MODE #0 * 2200 Hz generator ", $0d, $0a, 0
BANNER_M1:
		.db "* TEST MODE #1 * 1200 Hz generator ", $0d, $0a, 0
BANNER_M2:
		.db "* TEST MODE #2 * HDLC Flag generator ", $0d, $0a, 0
BANNER_M3:
		.db "* TEST MODE #3 * Send 0x00 via HDLC protocol ", $0d, $0a, 0
