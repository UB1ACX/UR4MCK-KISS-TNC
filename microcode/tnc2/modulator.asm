;************************************************************************
;			AFSK VHF 1200 baud modulator routine						*
;				Version 0.0.4											*
;			   (c) 2006-2007 UR4MCK										*
;																		*
;************************************************************************

;---------------------------------------------------------
;		START_TX - Prepare modulator for transmition
;
;	Input:	none
;	Output:	mul_lo, mul_hi, sum1_lo sample, Z, TIMER_STEP
;	Used:	tmp
;---------------------------------------------------------
start_tx:
		cli

		; Set variables
		clr mul_lo					; Init TX phase counter
		clr mul_hi					; Init TX bitrate counter
		ldi sample, SINE_TAB_LEN	; Init TX cycles counter
		ldi ZH, high(SINE_TAB)		; Init sine pointer (high)
		ldi ZL, low(SINE_TAB)		; Init sine pointer (low)

		; Init CRC16
		ser tmp
		sts CRC16, tmp				; Store low byte
		sts CRC16 + 1, tmp			; Store high byte

		; Set inital symbol
;		ldi tmp, TX_SPACE			; Uncomment this if you want to start with SPACE
		ldi tmp, TX_MARK			; Start with MARK
		sts TIMER_STEP, tmp

		; Disable RX Tasks
		sts RXSR, mul_lo

		; Disable ADC
		out ADCSRA, mul_lo

		; Disable Timer/Counter2
		out TCCR2, mul_lo

		; Setup Timer/Counter1
		ldi tmp, 0b10000001 		; Fast PWM, OC1A is used, TOP = 0xff
		out TCCR1A, tmp
		ldi tmp, 0b00001001			; CLK/1
		out TCCR1B, tmp
		ldi tmp, (1 << TOIE1)		; Enable overflow interrupt
		out TIMSK, tmp

		sbi PORTD, PTT_PIN			; Turn PTT on

		sei
		ret

;---------------------------------------------------------
;		TRANSMIT_TASK
;
;	Input:	none
;	Output:	none
;	Used:	none
;---------------------------------------------------------
transmit_task:
		rcall uart_rx			; Do UART RX Task
		rcall kiss2plain		; Do KISS task
		rcall tx_task			; Do TX (modulator) task
		ret

;---------------------------------------------------------
;		UART_RX - UART RX Task routine
;
;	Input:	RXC bit in UCSRA, byte in UDR
;	Output:	TXB_LEN, byte in FRAM
;	Used:	tmp, X, Y, TXB_WRPTR
;---------------------------------------------------------
uart_rx:
		; Check for UART RX complete flag
		sbis UCSRA, RXC
		ret						; Return if no data

		; Check buffer space
		lds YL, TXB_LEN			; Get TXB_LEN low byte
		lds YH, TXB_LEN + 1		; Get TXB_LEN high byte
		ldi tmp, high(TXB_SIZE)
		cpi YL, low(TXB_SIZE)	; Compare with TXB_SIZE (low)
		cpc YH, tmp				; Compare with TXB_SIZE (high)
		brne urx_save
		ret						; Return if buffer is full

urx_save:
		in tmp, UDR				; Get byte from UART buffer
		lds XL, TXB_WRPTR		; Get TXB_WRPTR low byte
		lds XH, TXB_WRPTR + 1	; Get TXB_WRPTR high byte
		rcall fram_save			; Save tmp in FRAM

		; Increment TXB_WRPTR and wrap it around
		adiw XH:XL, 1
		andi XH, high(TXB_SIZE - 1)

		; Increment TXB_LEN
		adiw YH:YL, 1

		; Store TXB_WRPTR, TXB_LEN
		sts TXB_WRPTR, XL		; Store TXB_WRPTR low byte
		sts TXB_WRPTR + 1, XH	; Store TXB_WRPTR high byte
		sts TXB_LEN, YL			; Store TXB_LEN low byte
		sts TXB_LEN + 1, YH		; Store TXB_LEN high byte

		ret

;---------------------------------------------------------
;		KISS2PLAIN - Convert KISS frame to plain data
;
;	Input:	KISS_READY bit in TXSR, TXB_LEN, 
;	Output:	TX_BYTE, TX_<params>, KISSRA
;	Used:	tmp, cnt, TXB_RDPTR, X, Y
;---------------------------------------------------------
kiss2plain:
		; Check if pervious KISS BYTE was grabbed
		lds tmp, TXSR					; Get TX Status Register
		sbrc tmp, KISS_READY			; Check for KISS_READY bit
		ret								; Return if it was set

		; Check if any data in buffer waiting
		lds YL, TXB_LEN					; Get TXB_LEN low byte
		lds YH, TXB_LEN + 1				; Get TXB_LEN high byte
		adiw YH:YL, 0					; Check if TXB_LEN = 0
		brne k2p_load
		ret								; Return if no data

k2p_load:
		lds XL, TXB_RDPTR				; Get TXB_RDPTR low byte
		lds XH, TXB_RDPTR + 1			; Get TXB_RDPTR high byte
		rcall fram_load					; Load byte (to tmp) from FRAM

		; Increment TXB_RDPTR and wrap it around
		adiw XH:XL, 1
		andi XH, high(TXB_SIZE - 1)

		; Decrement TXB_LEN
		sbiw YH:YL, 1

		; Store TXB_RDPTR, TXB_LEN
		sts TXB_RDPTR, XL				; Store TXB_RDPTR low byte
		sts TXB_RDPTR + 1, XH			; Store TXB_RDPTR high byte
		sts TXB_LEN, YL					; Store TXB_LEN low byte
		sts TXB_LEN + 1, YH				; Store TXB_LEN high byte

		lds cnt, KISSRA					; Get KISSRA (KISS status register A)

		cpi tmp, KISS_FEND				; Check for KISS FEND symbol
		breq k2p_fend

		sbrc cnt, KF_FEND				; Check for 'FEND' KISS flag
		rjmp k2p_fend_1
		ret								; Bad protocol. Data not within a frame

k2p_fend:
		ldi tmp, (1 << KF_FEND)
		eor cnt, tmp					; Set 'FEND' KISS flag if cleared, clear if it was set
		andi cnt, (1 << KF_FEND)		; Mask 'FEND' flag
		brne k2p_type
		rjmp k2p_exit

k2p_type:
		sbr cnt, (1 << KF_TYPE)			; Set 'SET_TYPE' flag
		rjmp k2p_exit

k2p_fend_1:
		; KISS frame follows
		sbrc cnt, KF_FESC				; Check for 'FESC' KISS flag
		rjmp k2p_fesc_1

		cpi tmp, KISS_FESC				; Check for KISS FESC symbol
		breq k2p_fesc

k2p_parse:
		sbrc cnt, KF_TYPE				; Check for 'SET_TYPE' flag
		rjmp k2p_settype

		sbrc cnt, KF_HW					; Check for 'KF_HW' flag
		rjmp k2p_gethw

		push cnt

		andi cnt, 7						; Mask low 3 bits
		breq k2p_data					; Branch if type is 'DATA'

		cpi cnt, KISS_CMD_DELAY
		breq k2p_delay					; Branch if type is 'TX_DELAY'

		cpi cnt, KISS_CMD_P
		breq k2p_persist				; Branch if type is 'PERSISTENCE'

		cpi cnt, KISS_CMD_SLOT
		breq k2p_slot					; Branch if type is 'SLOT_TIME'

		cpi cnt, KISS_CMD_TAIL
		breq k2p_tail					; Branch if type is 'TX_TAIL'

		cpi cnt, KISS_CMD_DUPLX
		breq k2p_duplx					; Branch if type is 'FULL_DUPLEX'

		cpi cnt, KISS_CMD_HARDW
		breq k2p_hardw					; Branch if type is 'SET_HARDWARE'

		rjmp k2p_pop					; Bad protocol. Unknown frame type

k2p_fesc:
		sbr cnt, (1 << KF_FESC)			; Set 'FESC' KISS flag
		sts KISSRA, cnt					; Store KISSRA
		rjmp kiss2plain					; Go to start

k2p_fesc_1:
		; KISS Escaped mode
		cbr cnt, (1 << KF_FESC)			; Clear 'FESC' KISS flag

		cpi tmp, KISS_TFEND				; Compare with KISS TFEND symbol
		breq k2p_tfend

		cpi tmp, KISS_TFESC				; Compare with KISS TFESC symbol
		breq k2p_tfesc

		rjmp k2p_exit					; Bad protocol. Just skip it

k2p_tfend:
		ldi tmp, KISS_FEND				; Set data to KISS FEND
		rjmp k2p_parse

k2p_tfesc:
		ldi tmp, KISS_FESC				; Set data to KISS FESC
		rjmp k2p_parse

k2p_settype:
		cbr cnt, (1 << KF_TYPE)			; Clear 'SET_TYPE' flag
		andi tmp, 0b00000111			; Mask low 3 bits of data byte
		andi cnt, 0b11111000			; Mask high 5 bits of KISSRA
		or cnt, tmp						; Add type bits to KISSRA
		rjmp k2p_exit

k2p_data:
		; KISS frame type is 'DATA'
		sts TX_BYTE, tmp				; Store data byte in TX_BYTE buffer

		; Set KISS_READY bit in TXSR
		lds tmp, TXSR
		sbr tmp, (1 << KISS_READY)
		sts TXSR, tmp
		rjmp k2p_pop

k2p_delay:
		; KISS frame type is 'TX_DELAY'
		sts TX_DELAY, tmp
		rjmp k2p_pop

k2p_persist:
		; KISS frame type is 'PERSISTENCE'
		sts TX_PERSIST, tmp
		rjmp k2p_pop

k2p_slot:
		; KISS frame type is 'SLOT_TIME'
		sts TX_SLOT, tmp
		rjmp k2p_pop

k2p_tail:
		; KISS frame type is 'TX_TAIL'
		sts TX_TAIL, tmp
		rjmp k2p_pop

k2p_duplx:
		; KISS frame type is 'FULL DUPLEX'

		; Not implemented

		rjmp k2p_pop

k2p_hardw:
		; KISS frame type is 'SET HARDWARE'
		sts KISS_HW_ADDR, tmp			; Store HW address
		pop cnt							; Restore KISSRA from stack
		sbr cnt, (1 << KF_HW)			; Set 'KF_HW' bit
		rjmp k2p_exit

k2p_gethw:
		; Get a value for 'Set hardware' command
		cbr cnt, (1 << KF_HW)			; Clear 'KF_HW' flag
		push tmp						; Preserve value byte
		lds tmp, KISS_HW_ADDR			; Get previously stored KISS_HW_ADDR

		; Check for UART RATE low byte
		cpi tmp, KISS_HW_ADDR_UBRL
		breq k2p_ubrl

		; Check for UART RATE high byte
		cpi tmp, KISS_HW_ADDR_UBRH
		breq k2p_ubrh

		; Check for STORE_L1
		cpi tmp, KISS_HW_ADDR_L1
		breq k2p_storel1

		; Unsupported 'Set Hardware' address
		pop tmp
		rjmp k2p_exit

k2p_ubrl:
		; Store UART RATE low byte
		pop tmp
		ldi XH, high(EEPROM_ADDR + 1)	; Get high EEPROM address of UBR_L
		ldi XL, low(EEPROM_ADDR + 1)	; Get low EEPROM address of UBR_L
		rjmp k2p_eep					; Store in EEPROM

k2p_ubrh:
		; Store UART RATE high byte
		pop tmp
		push tmp
		ldi XH, high(EEPROM_ADDR + 2)	; Get high EEPROM address of UBR_H
		ldi XL, low(EEPROM_ADDR + 2)	; Get low EEPROM address of UBR_H
		rcall eeprom_save

		; Use new UART rate
		pop tmp
		out UBRRH, tmp					; Set new UART Rate high byte
		sbiw XH:XL, 1
		rcall eeprom_load
		out UBRRL, tmp					; Set new UART Rate low byte
		rjmp k2p_exit

k2p_storel1:
		; Store L1 params
		pop tmp

		ldi XH, high(EEPROM_ADDR + 3)	; Get high EEPROM address of TX_DELAY
		ldi XL, low(EEPROM_ADDR + 3)	; Get low EEPROM address of TX_DELAY

		; Store TX_DELAY
		lds tmp, TX_DELAY				; Get current TX_DELAY value
		rcall eeprom_save				; Save it in EEPROM

		; Store TX_PERSIST
		inc XL
		lds tmp, TX_PERSIST				; Get current TX_PESIST value
		rcall eeprom_save				; Save it in EEPROM

		; Store TX_SLOT
		inc XL
		lds tmp, TX_SLOT				; Get current TX_SLOT value
		rcall eeprom_save				; Save it in EEPROM

		; Store TX_TAIL
		inc XL
		lds tmp, TX_TAIL				; Get current TX_TAIL value
		rcall eeprom_save				; Save it in EEPROM

		; Skip FULL_DUP
		inc XL

		; Store DCD_THR
		inc XL
		lds tmp, DCD_THR				; Get current DCD_THR value

k2P_eep:
		rcall eeprom_save				; Store tmp value in EEPROM address pointed by X
		rjmp k2p_exit

k2p_pop:
		pop cnt

k2p_exit:
		sts KISSRA, cnt					; Store KISSRA

k2p_ret:
		ret

;---------------------------------------------------------
;		TX_TASK
;
;	Input:	TXSR, TX_BYTE
;	Output: TXSR
;	Used:	tmp, cnt, CRC16
;---------------------------------------------------------
tx_task:
		lds tmp, TXSR				; Get TX Status Register
		mov cnt, tmp
		andi tmp, 3					; Mask 2 low bits
		sbrc cnt, KISS_READY		; Check for KISS_READY bit
		rjmp txt_1					; Jump if KISS_READY is set

		cpi tmp, $03				; Check for 'tx_tail' status
		breq txt_dec
		cpi tmp, 2					; Check for 'data' status
		breq txt_end
		ret

txt_dec:
		lds cnt, TX_CNT				; Get TX_CNT
		dec cnt						; Decrement TX_CNT
		breq txt_tail_1				; Branch if there are no more cycles pending

		sts TX_CNT, cnt				; Store TX_CNT
		rcall hdlc_sendflag			; Send HDLC flag symbol
		ret

txt_tail_1:
		cpi tmp, $03				; Check if last was 'tx_tail'
		breq txt_start_rx

		; TX Delay was ended
		lds cnt, TX_TAIL			; Preload counter with TX_TAIL value (for the end of frame)
		sts TX_CNT, cnt				; Store TX_CNT
		rjmp txt_next

txt_start_rx:
		; TX Tail was ended
		; Start Demodulator (also stops modulator)
		mov cnt, tmp				; Preserve TXSR
		rcall start_rx				; Start RX
		mov tmp, cnt				; Restore TXSR

txt_next:
		inc tmp						; Go to the next state
		andi tmp, 3					; Wrap around 2 bits
		mov cnt, tmp
		lds tmp, TXSR				; Get TXSR
		andi tmp, $fc				; Mask everything but 2 low bits
		or tmp, cnt					; Add new state to TXSR
		sts TXSR, tmp				; Store TXSR
		ret

txt_end:
		sbrc cnt, SEND_CRC			; Check for SEND_CRC bit
		rjmp txt_end_2				; Jump if it is set

		; Need to send 1'st byte of CRC16
		sbr cnt, (1 << SEND_CRC)	; Set SEND_CRC bit
		sts TXSR, cnt				; Store TXSR
		lds tmp, CRC16				; Get CRC16 low byte
		com tmp
		rcall hdlc_send
		ret

txt_end_2:
		; Need to send 2'nd byte of CRC16
		cbr cnt, (1 << SEND_CRC)	; Clear SEND_CRC bit
		inc cnt						; Go from 'data' to 'tx_tail' state
		sts TXSR, cnt				; Store TXSR
		lds tmp, CRC16 + 1			; Get CRC16 high byte
		com tmp
		rcall hdlc_send

		; Init CRC16
		ser tmp
		sts CRC16, tmp				; Store low byte
		sts CRC16 + 1, tmp			; Store high byte
		ret

txt_1:
		brne txt_cont
		
		; Check DCD bit in RXSR
		lds cnt, RXSR				; Get RXSR
		sbrc cnt, DCD				; Skip if DCD is clear
		ret							; Return if DCD is set

		; True p-Persistence Channel Access method

		lds tmp, TXSR				; Get TXSR
		sbrc tmp, SLOT				; Check for SLOT bit in TXSR
		rjmp txt_slot_1				; Check slot if SLOT bit = 1

		lds tmp, RND_VAL			; Get RND_VAL

		; Randomize RND_VAL
		rol tmp						; RND_VAL = RND_VAL * 2 + C
		in cnt, TCNT2				; Get Timer/Counter2 value
		eor tmp, cnt				; XOR both values
		sts RND_VAL, tmp			; Store new RND_VAL

		; Check persistence
		lds cnt, TX_PERSIST			; Get TX_PERSIST
		cp cnt, tmp					; Compare it with random value
		brlo txt_slot				; Start slot if persist < rnd

		; Start Modulator (also stops demodulator)
		rcall start_tx				; Start TX

		lds cnt, TX_DELAY			; Preload counter with TX_DELAY
		sts TX_CNT, cnt

		clr tmp
		rjmp txt_next				; Go to the next state

txt_slot:
		; Start slot
		lds cnt, TX_SLOT			; Get TX_SLOT
		sts TX_SLOT_CNT, cnt		; Store TX_SLOT_CNT
		lds cnt, TXSR				; Get TXSR
		sbr cnt, (1 << SLOT)		; Set SLOT bit
		sts TXSR, cnt				; Store TXSR
		ret

txt_slot_1:
		; Check slot
		sbrs cnt, RX_TICK			; Check if RX_TICK bit in RXSR is set
		ret							; Return if cleared

		cbr cnt, (1 << RX_TICK)		; Clear RX_TICK bit in RXSR
		sts RXSR, cnt				; Store RXSR

		lds cnt, TX_SLOT_CNT		; Get TX_SLOT_CNT
		dec cnt						; TX_SLOT_CNT = TX_SLOT_CNT - 1
		brne txt_slot_2				; Branch if TX_SLOT_CNT > 0

		; End of slot time
		lds cnt, TX_SLOT			; Preload TX_SLOT_CNT with TX_SLOT value
		cbr tmp, (1 << SLOT)		; Clear SLOT bit in TXSR
		sts TXSR, tmp				; Store TXSR

txt_slot_2:
		; Continue slot time
		sts TX_SLOT_CNT, cnt		; Store TX_SLOT_CNT
		ret

txt_cont:
		cpi tmp, 1					; Check for 'tx_delay' state
		brne txt_2
		rjmp txt_dec

txt_2:
		cpi tmp, 2					; Check for 'data' state
		brne txt_3

		; DATA
		lds tmp, TX_BYTE			; Get TX data byte
		rcall add2crc				; Add data byte to CRC16
		rcall hdlc_send				; Send data byte
		lds tmp, TXSR				; Get TXSR
		cbr tmp, (1 << KISS_READY)	; Clear KISS_READY bit
txt_sr:
		sts TXSR, tmp				; Store TXSR
		ret

txt_3:
		; Init CRC16
		ser tmp
		sts CRC16, tmp				; Store low byte
		sts CRC16 + 1, tmp			; Store high byte

		lds tmp, TXSR				; Get TXSR
		cbr tmp, 1					; Go from 'tail' to 'data' state (new consequetive frame)

		lds cnt, TX_TAIL			; Preload counter with TX_TAIL
		sts TX_CNT, cnt
		rjmp txt_sr

;---------------------------------------------------------
;		HDLC_SENDFLAG - Send contiguous HDLC flag
;
;	Input:	none
;	Output:	none
;	Used:	tmp, cnt, sum1_lo (ones counter),
;			sum1_hi (temporary), T-flag, C-flag,
;			TIMER_STEP
;---------------------------------------------------------
hdlc_sendflag:
		; Prepare
		ldi tmp, HDLC_FLAG	; Set byte to send
		ldi cnt, 8			; Set bits counter

		; Check maybe bit stuffing waiting
		dec sum1_lo			; Decrement ones counter
		brne hsf_start		; Branch if no bit stuffing waiting

		; Add stuffed bit (0)
		inc cnt				; Do not count this bit
		lsl tmp				; Place zero at least bit position

hsf_start:
		push tmp			; Preserve byte
hsf_wait:
		; Wait for a new bit period
		rcall uart_rx		; Run UART RX task when waiting for a new bit period
		brtc hsf_wait
		clt					; Clear T-flag
		pop tmp				; Restore byte

		ror tmp				; Get next bit (in C-flag)
		brcs hsf_one		; ONE

		; ZERO
		mov sum1_hi, tmp	; Copy tmp to temporary
		lds tmp, TIMER_STEP	; Get TIMER_STEP value
		cpi tmp, TX_MARK	; Compare with MARK value
		breq hsf_space

		; MARK
		ldi tmp, TX_MARK	; Next symbol is MARK
		rjmp hsf_next

hsf_space:
		; Reset ones counter
		ldi tmp, 5
		mov sum1_lo, tmp
		ldi tmp, TX_SPACE	; Next symbol is SPACE

hsf_next:
		sts TIMER_STEP, tmp	; New timer step value
		mov tmp, sum1_hi	; Restore tmp

hsf_one:
		dec cnt				; More bits?
		brne hsf_start

		inc sum1_lo			; Need for ones counter stay unchanged
		ret

;---------------------------------------------------------
;		HDLC_SEND - Send byte using HDLC protocol
;
;	Input:	tmp (byte), sum1_lo (ones counter)
;	Output:	none
;	Used:	tmp, cnt, sum1_hi (temporary), TIMER_STEP,
;			T-flag, C-flag
;---------------------------------------------------------
hdlc_send:
		; Prepare
		ldi cnt, 8			; Set bits counter

hs_start:
		push tmp			; Preserve byte
hs_wait:
		; Wait for a new bit period
		rcall uart_rx		; Run UART RX task when waiting for a new bit period
		brtc hs_wait
		clt					; Clear T-flag
		pop tmp				; Restore byte

		dec sum1_lo			; Bit stuffing?
		brne hs_shift		; Branch if none

		inc cnt				; Do not count stuffed bit
		rjmp hs_zero

hs_shift:
		ror tmp				; Get next bit (in C-flag)
		brcs hs_next		; ONE

		; ZERO
hs_zero:
		mov sum1_hi, tmp	; Copy tmp to temporary
		lds tmp, TIMER_STEP	; Get TIMER_STEP value
		cpi tmp, TX_MARK	; Compare with MARK value
		breq hs_space

		ldi tmp, TX_MARK	; Next symbol is MARK
		rjmp hs_reset

hs_space:
		ldi tmp, TX_SPACE	; Next symbol is SPACE

hs_reset:
		sts TIMER_STEP, tmp	; New timer step value
		ldi tmp, 6
		mov sum1_lo, tmp	; Reset ones counter (used for bit stuffing)
		mov tmp, sum1_hi	; Restore tmp

hs_next:
		dec cnt				; More bits?
		brne hs_start 

		ret
