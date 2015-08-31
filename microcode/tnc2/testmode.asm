;************************************************************************
;			TESTING MODE routine										*
;				Version 0.0.3											*
;			   (c) 2006-2007 UR4MCK										*
;																		*
;************************************************************************


test_mode:
		cbi PORTD, MODE_PIN		; Deactivate pull-up at MODE_PIN

		ldi XH, high(BANNER1 << 1)
		ldi XL, low(BANNER1 << 1)
		rcall printstr			; Print BANNER1
		rcall printstr			; Print BANNER2
		clr sum2_hi`			; Reset test mode number
		rcall start_tx			; Start transmiter
		rjmp tm_p0				; Start with test mode #0

tm_loop:
		rcall uart_rx			; Precees UART RX task

		; Check if any data in UART RX buffer waiting
		lds YL, TXB_LEN			; Get TXB_LEN low byte
		lds YH, TXB_LEN + 1		; Get TXB_LEN high byte
		adiw YH:YL, 0			; Check if TXB_LEN = 0
		breq tm_cp				; Branch if no data

		lds XL, TXB_RDPTR		; Get TXB_RDPTR low byte
		lds XH, TXB_RDPTR + 1	; Get TXB_RDPTR high byte
		rcall fram_load			; Load byte (to tmp) from FRAM

		; Increment TXB_RDPTR and wrap it around
		adiw XH:XL, 1
		andi XH, high(TXB_SIZE - 1)

		; Decrement TXB_LEN
		sbiw YH:YL, 1

		; Store TXB_RDPTR, TXB_LEN
		sts TXB_RDPTR, XL		; Store TXB_RDPTR low byte
		sts TXB_RDPTR + 1, XH	; Store TXB_RDPTR high byte
		sts TXB_LEN, YL			; Store TXB_LEN low byte
		sts TXB_LEN + 1, YH		; Store TXB_LEN high byte

		cpi tmp, ' '			; Check for [Space] code
		brne tm_cp

		mov tmp, sum2_hi
		inc tmp					; Increment to the next test mode
		andi tmp, 3				; And wrap around
		mov sum2_hi, tmp

		cpi tmp, 1
		brne tm_p2
		; Print banner for MODE #1 */
		ldi XH, high(BANNER_M1<< 1)
		ldi XL, low(BANNER_M1<< 1)
		rcall printstr
		rjmp tm_1

tm_p2:
		cpi tmp, 2
		brne tm_p3
		; Print banner for MODE #2 */
		ldi XH, high(BANNER_M2<< 1)
		ldi XL, low(BANNER_M2<< 1)
		rcall printstr
		rjmp tm_2

tm_p3:
		cpi tmp, 3
		brne tm_p0
		; Print banner for MODE #3 */
		ldi XH, high(BANNER_M3<< 1)
		ldi XL, low(BANNER_M3<< 1)
		rcall printstr
		rjmp tm_3

tm_p0:
		; Print banner for MODE #0 */
		ldi XH, high(BANNER_M0<< 1)
		ldi XL, low(BANNER_M0<< 1)
		rcall printstr
		rjmp tm_0

tm_cp:
		mov tmp, sum2_hi
		cpi tmp, 1				; Check for test mode #1
		breq tm_1

		cpi tmp, 2				; Check for test mode #2
		breq tm_2

		cpi tmp, 3				; Check for test mode #3
		breq tm_3

tm_0:
		/* MODE #0: 2200 Hz generator */
		ldi tmp, TX_SPACE		; 2200 Hz
		sts TIMER_STEP, tmp		; Set for modulator
		rjmp tm_loop

tm_1:
		/* MODE #1: 1200 Hz generator */
		ldi tmp, TX_MARK		; 1200 Hz
		sts TIMER_STEP, tmp		; Set for modulator
		rjmp tm_loop

tm_2:
		/* MODE #0: HDLC Flag generator */
		rcall hdlc_sendflag
		rjmp tm_loop

tm_3:
		/* MODE #0: Send 0x00 via HDLC protocol */
		clr tmp
		rcall hdlc_send
		rjmp tm_loop

;---------------------------------------------------------
;		PRINTSTR - Send an ASCIIZ string via UART
;
;	Input:	X
;	Output: X
;	Used:	tmp, Z
;---------------------------------------------------------
printstr:
		cli
		push ZH
		push ZL
		mov ZH, XH
		mov ZL, XL
pstr_loop:
		lpm tmp, Z+				; Get char from FLASH
		tst tmp					; Check for zero (end of string)
		breq pstr_ret			; Branch if so
		rcall print				; Print single char
		rjmp pstr_loop			; And again

pstr_ret:
		mov XH, ZH
		mov XL, ZL
		pop ZL
		pop ZH
		sei
		ret

;---------------------------------------------------------
;		PRINT - Send single byte to the UART
;
;	Input:	tmp
;	Output: none
;	Used:	none
;---------------------------------------------------------
print:
		sbis UCSRA, UDRE		; Wait for UART ready
		rjmp print
		out UDR, tmp			; Send byte to the UART
		ret

#ifdef TESTING
;---------------------------------------------------------
;		PRINTHEX - Print HEX number
;
;	Input:	tmp
;	Output:	none
;	Used:	none
;---------------------------------------------------------
printhex:
		; Most nibble
		push tmp
		lsr tmp
		lsr tmp
		lsr tmp
		lsr tmp
		cpi tmp, 10
		brlo ph_digit1

		subi tmp, 10-('a')
		rjmp ph_put1

ph_digit1:
		subi tmp, -('0')
ph_put1:
		rcall print

		; Least nibble
		pop tmp
		andi tmp, 0x0f
		cpi tmp, 10
		brlo ph_digit2

		subi tmp, 10-('a')
		rjmp ph_put2

ph_digit2:
		subi tmp, -('0')
ph_put2:
		rcall print

		ret

#endif
