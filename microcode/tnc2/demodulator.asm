;************************************************************************
;			AFSK VHF 1200 baud demodulator routine						*
;				   Version 0.0.4										*
;			      (c) 2006-2007 UR4MCK									*
;																		*
;		Changes:														*
;				29.04.07: Receiving anti-noise threshold was added		*
;						  at adc_task									*
;																		*
;************************************************************************

;---------------------------------------------------------
;		START_RX - Prepare demodulator for receiving
;
;	Input:	none
;	Output:	RXSR, RX_PHASE, RX_SHREG, RXB_RDPTR,
;			RXB_WRPTR, RXB_LEN, RXB_FRLEN
;	Used:	tmp
;---------------------------------------------------------
start_rx:
		cli

		cbi PORTD, PTT_PIN				; Turn off PTT

		; Set variables
		clr tmp
		sts RX_SHREG, tmp				; Init RX_SHREG
		sts RX_PHASE, tmp				; Init RX_PHASE
		sts RXB_LEN, tmp				; RXB_LEN (low) = 0
		sts RXB_LEN + 1, tmp			; RXB_LEN (high) = 0
		sts RXB_FRLEN, tmp				; RXB_FRLEN (low) = 0
		sts RXB_FRLEN + 1, tmp			; RXB_FRLEN (high) = 0
		sts UTXB_LEN, tmp				; UTXB_LEN (low) = 0
		sts UTXB_LEN + 1, tmp			; UTXB_LEN (high) = 0
		sts UTXB_CNT, tmp				; UTXB_CNT (low) = 0
		sts UTXB_CNT + 1, tmp			; UTXB_CNT (high) = 0
		sts KISSRB, tmp					; Init KISS Status Register B

		out TCCR1B, tmp					; Disable Timer/Counter1

		; Init RXSR
		ldi tmp, (1 << RX_ACTIVE)		; Activate RX Tasks
		sts RXSR, tmp

		; Init RAM buffer pointers
		ldi tmp, low(RXB_ADDR)
		sts RXB_RDPTR, tmp				; Store RXB_RDPTR low byte
		sts RXB_WRPTR, tmp				; Store RXB_WRPTR low byte
		ldi tmp, high(RXB_ADDR)
		sts RXB_RDPTR + 1, tmp			; Store RXB_RDPTR high byte
		sts RXB_WRPTR + 1, tmp			; Store RXB_WRPTR high byte

		; Init RX_TICK_CNT
		ldi tmp, RX_TICK_LEN
		sts RX_TICK_CNT, tmp

		; Setup ADC
		ldi tmp, 0b01100000				; Vref = AVCC, Left adjusted, ADC0 used
		out ADMUX, tmp
		ldi tmp, 0b11000100				; ADC enabled, initial conversion started, CLK/8
		out ADCSRA, tmp

		; Setup Timer/Counter2
		ldi tmp, SAMPLE_RATE
		out OCR2, tmp
		ldi tmp, 2						; CLK/8
		out TCCR2, tmp
		ldi tmp, (1 << OCIE2)
		out TIMSK, tmp

		sei
		ret

;---------------------------------------------------------
;		RECEIVE_TASK
;
;	Input:	none
;	Output:	none
;	Used:	tmp
;---------------------------------------------------------
receive_task:
		rcall adc_task			; Do ADC (demodulation) task
		rcall rx_task			; Do RX (HDLC) task
		rcall uart_tx			; Do KISS & UART TX tasks
		ret

;---------------------------------------------------------
;		ADC_TASK - ADC Task routine
;
;	Input:	sample
;	Output:	RXSR
;	Used:	tmp, cnt, X, Y, Z, sum1_lo, sum1_hi, sum2_lo,
;			sum2_hi, mul_lo, mul_hi, RX_SHREG, RX_PHASE,
;			RXSR, RX_TICK_CNT, RX_TICK_LRN
;---------------------------------------------------------
adc_task:
#ifdef TESTING
		sbi PORTB, TEST_PIN
#endif

		brts adc_start				; Branch if sample ready
		rjmp adc_ret

adc_start:
		; Check if RX Task is active
		lds tmp, RXSR				; Get RXSR
		sbrs tmp, RX_ACTIVE			; Skip if RX is active
		rjmp adc_ret				; Return otherwise

		clt							; Clear T-flag (sample ready)

		; Make tick
		lds cnt, RX_TICK_CNT		; Get RX_TICK_CNT
		dec cnt						; Decrement tick counter
		brne adc_sub				; Branch if no tick now
		ldi cnt, RX_TICK_LEN		; Preload tick counter
		sbr tmp, (1 << RX_TICK)		; Set RX_TICK bit
		sts RXSR, tmp				; Store RXSR

adc_sub:
		sts RX_TICK_CNT, cnt		; Store RX_TICK_CNT

		subi sample, ADC_ZERO		; Convert sample to signed value

		; Receiving anti-noise threshold
		mov tmp, sample
		subi tmp, -2				; Threshold value
		andi tmp, 0b11111110		; Look at least bit
		brne adc_store
		ldi sample, 0x00			; No signal

adc_store:
#ifdef TEST_ADC_SAMPLE
		; Output ADC sample
#ifdef TESTING
		mov tmp, sample
		rcall printhex
#else
		out UDR, sample
#endif
		rjmp adc_ret
#endif
		; Store sample in the delay line
		ldi XH, high(RX_MEM)
		lds XL, RX_MEMIDX			; Get index
		st X+, sample				; Store sample

		; Wrap index
		andi XL, (low(RX_MEM) | (RX_FILTER_LEN - 1))
		sts RX_MEMIDX, XL			; Store index

		; Prepare for convolution
		clr sum1_lo
		clr sum1_hi
		clr sum2_lo
		clr sum2_hi
		ldi cnt, RX_FILTER_LEN
		ldi YH, high(RX_C1)
		ldi YL, low(RX_C1)
		ldi ZH, high(RX_C2)
		ldi ZL, low(RX_C2)
adc_loop:
		; Convolution cycle
		ld sample, X+				; Get next sample
		ld tmp, Y+					; Get next C1 coefficient
		muls tmp, sample			; Multiply it
		add sum1_lo, mul_lo			; Add low byte
		adc sum1_hi, mul_hi			; Add high byte
		ld tmp, Z+					; Get next C2 coefficient
		muls tmp, sample			; Multiply it
		add sum2_lo, mul_lo			; Add low byte
		adc sum2_hi, mul_hi			; Add high byte

		; Wrap index
		andi XL, (low(RX_MEM) | (RX_FILTER_LEN - 1))
		dec cnt						; Decrement loop counter
		brne adc_loop

		; Get signal #1 energy and store it in delay line
		mov tmp, sum1_hi
		muls tmp, tmp				; Compute x1 = s1 * s1
		lds XL, RX_D1IDX			; Get D1 index
		st X+, mul_lo				; Save x1 (low byte)
		st X+, mul_hi				; Save x1 (high byte)

		; Wrap index
		andi XL, (low(RX_D1) | (RX_FILTER_LEN / 2 - 1))
		ld sum1_lo, X+				; Get delayed value y1 (low byte)
		ld sum1_hi, X				; Get delayed value y1 (high byte)
		dec XL						; Adjust index to point to low byte
		sts RX_D1IDX, XL			; Store new index

		; m1 = y1 + x1
		add sum1_lo, mul_lo
		adc sum1_hi, mul_hi

		; Get signal #2 energy and store it in delay line
		mov tmp, sum2_hi
		muls tmp, tmp				; Compute x2 = s2 * s2
		lds XL, RX_D2IDX			; Get D2 index
		st X+, mul_lo				; Save x2 (low byte)
		st X+, mul_hi				; Save x2 (high byte)

		; Wrap index
		andi XL, (low(RX_D2) | (RX_FILTER_LEN / 4 - 1))
		ld sum2_lo, X+				; Get delayed value y2 (low byte)
		ld sum2_hi, X				; Get delayed value y2 (high byte)
		dec XL						; Adjust index to point to low byte
		sts RX_D2IDX, XL			; Store new index

		; m2 = y2 + x2
		add sum2_lo, mul_lo
		adc sum2_hi, mul_hi

		lds cnt, RX_SHREG			; Get RX_SHREG
		lsl cnt						; Prepare space for a new bit

		; m = m1 - m2
		sub sum1_lo, sum2_lo
		sbc sum1_hi, sum2_hi

		; Decision about symbol
		brmi adc_sync				; In case of branch, symbol = SPACE
		inc cnt						; otherwise, symbol = MARK

adc_sync:
		sts RX_SHREG, cnt			; Store RX_SHREG

		; Bit synchronization
		mov sample, cnt
		andi sample, $0f			; Only least nibble is used
		ldi tmp, $03
		eor tmp, sample				; Check for transition like '0011'
		lds tmp, RX_PHASE			; Get RX_PHASE
		breq adc_adjust
		ldi tmp, $0c
		eor tmp, sample				; Check for transition like '1100'
		lds tmp, RX_PHASE			; Get RX_PHASE
		brne adc_phinc

adc_adjust:
		; Adjust phase follover
		cpi tmp, ($80 - 4 * RX_PHASE_INC)
		brlo adc_inc
		subi tmp, (RX_PHASE_INC / 4); Decrease phase
		rjmp adc_phinc

adc_inc:
		subi tmp, -(RX_PHASE_INC / 4); Increase phase

adc_phinc:
		; Calculate next phase
		subi tmp, -RX_PHASE_INC		; RX_PHASE = RX_PHASE + RX_PHASE_INC
		sts RX_PHASE, tmp			; Store RX_PHASE
		brcs adc_ret

		; Time to get a symbol
		; Using soft decision based on metric table
		ldi ZH, high(METRIC_TAB << 1); Load high address
		ldi ZL, low(METRIC_TAB << 1); Load low address
		add ZL, cnt					; Add table offset
		lpm tmp, Z					; Get metric for the current RX_SHREG value

		lds cnt, RXSR				; Get RXSR
		cpi tmp, $80				; Check for a middle of metric table values
		brlo adc_space

		; "MARK"
		sbrc cnt, LAST_S			; Skip if LAST_S = 0
		rjmp adc_1
		sbr cnt, (1 << LAST_S)		; Set LAST_S = 1

adc_0:
#ifdef TEST_ADC_BITS
		ldi tmp, '0'
		rcall print
#endif
		cbr cnt, (1 << RX_BIT)		; Set RX_BIT = 0
		rjmp adc_done

adc_1:
#ifdef TEST_ADC_BITS
		ldi tmp, '1'
		rcall print
#endif
		sbr cnt, (1 << RX_BIT)		; Set RX_BIT = 1
		rjmp adc_done

adc_space:
		; "SPACE"
		sbrs cnt, LAST_S			; Skip if LAST_S = 1
		rjmp adc_1
		cbr cnt, (1 << LAST_S)		; Set LAST_S = 0
		rjmp adc_0

adc_done:
		sbr cnt, (1 << BIT_READY)	; Set BIT_READY flag
		sts RXSR, cnt				; Store RXSR

adc_ret:
#ifdef TESTING
		cbi PORTB, TEST_PIN
#endif
		ret

;---------------------------------------------------------
;		RX_TASK - HDLC RX Task routine
;
;	Input:	RXSR
;	Output:	RXB_LEN, RXB_WRPTR, DCD_CNT
;	Used:	tmp, cnt, X, Y, RX_BITSTREAM, CRC16, RXB_FRLEN
;---------------------------------------------------------
rx_task:
#ifdef TESTING
		sbi PORTB, TEST_PIN
#endif

		lds tmp, RXSR				; Get RXSR
		sbrs tmp, BIT_READY			; Check for BIT_READY
		rjmp rxt_ret

		cbr tmp, (1 << BIT_READY)	; Clear BIT_READY

		lds cnt, RX_BITSTREAM		; Get RX_BITSREAM
		lsl cnt						; Make space for a new bit
		sbrc tmp, RX_BIT			; Skip if RX_BIT = 0
		inc cnt						; Add one bit
		sts RX_BITSTREAM, cnt		; Store RX_BITSTREAM
		sts RXSR, tmp				; Store RXSR

		cpi cnt, HDLC_FLAG			; Check for HDLC flag
		breq rxt_flag
		rjmp rxt_data

rxt_flag:
		; HDLC flag detected
		sbrs tmp, RX_STATE			; Check RX_STATE
		rjmp rxt_set

		; Check for valid frame length
		lds XL, RXB_FRLEN			; Get RXB_FRLEN low byte
		lds XH, (RXB_FRLEN + 1)		; Get RXB_FRLEN high byte
		subi XL, low(FRAME_MIN_LEN)
		sbci XH, high(FRAME_MIN_LEN) 
		brmi rxt_abort				; Branch if frame is too small

		; Check CRC
		lds YL, CRC16				; Get CRC16 low byte
		lds YH, CRC16 + 1			; Get CRC16 high byte
		subi YL, $b8				; Substract CRC16 magic (low byte)
		sbci YH, $f0				; Substract CRC16 magic (high byte)
		brne rxt_abort				; Do not use broken frame

		; RXB_LEN = RXB_LEN + RXB_FRLEN
		lds XL, RXB_FRLEN			; Get RXB_FRLEN low byte
		lds XH, (RXB_FRLEN + 1)		; Get RXB_FRLEN high byte
		lds YL, RXB_LEN				; Get RXB_LEN low byte
		lds YH, (RXB_LEN + 1)		; Get RXB_LEN high byte
		add YL, XL					; Add low byte
		adc YH, XH					; Add high byte
		sts RXB_LEN, YL				; Store RXB_LEN low byte
		sts (RXB_LEN + 1), YH		; Store RXB_LEN high byte
		rjmp rxt_next

rxt_set:
		sbr tmp, (1 << RX_STATE)	; Set RX_STATE = 1
		sts RXSR, tmp				; Store RXSR

rxt_abort:
		; RXB_WRPTR = RXB_WRPTR - RXB_FRLEN
		lds XL, RXB_FRLEN			; Get RXB_FRLEN low byte
		lds XH, (RXB_FRLEN + 1)		; Get RXB_FRLEN high byte
		lds YL, RXB_WRPTR			; Get RXB_WRPTR low byte
		lds YH, (RXB_WRPTR + 1)		; Get RXB_WRPTR high byte
		sub YL, XL					; Substract low byte
		sbc YH, XH					; Substract high byte

		; Bounds checking
		cpi YH, high(RXB_ADDR)
		brsh rxt_store
		ldi YH, high(RXB_ADDR + RXB_SIZE - 1)

rxt_store:
		sts RXB_WRPTR, YL			; Store RXB_WRPTR low byte
		sts (RXB_WRPTR + 1), YH		; Store RXB_WRPTR high byte

rxt_next:
		; Set RXB_FRLEN = 0
		clr cnt
		sts RXB_FRLEN, cnt			; Store RXB_FRLEN low byte
		sts (RXB_FRLEN + 1), cnt	; Store RXB_FRLEN high byte

		; Init CRC
		ser cnt
		sts CRC16, cnt				; Store CRC16 low byte
		sts CRC16 + 1, cnt			; Store CRC16 high byte

		; Increment DCD counter
		lds cnt, DCD_CNT			; Get DCD_CNT
		inc cnt						; DCD_CNT = DCD_CNT + 1
		sts DCD_CNT, cnt			; Store DCD_CNT
		rjmp rxt_buf

rxt_data:
		andi cnt, $7f				; Mask low 7 bits
		cpi cnt, $7f
		brne rxt_data_1				; Branch if data waiting

rxt_reset:
		lds tmp, RXSR				; Get RXSR
		cbr tmp, (1 << RX_STATE)	; Clear RX_STATE bit
		sts RXSR, tmp				; Store RXSR

		; Clear DCD counter (noise)
		clr tmp
		sts DCD_CNT, tmp			; Store DCD_CNT
		rjmp rxt_dcd

rxt_data_1:
		; Increment DCD counter
		push cnt					; Preserve data byte
		lds cnt, DCD_CNT			; Get DCD_CNT
		inc cnt						; DCD_CNT = DCD_CNT + 1
		sts DCD_CNT, cnt			; Store DCD_CNT
		pop cnt						; Restore data byte

		sbrs tmp, RX_STATE			; Check for RX_STATE
		rjmp rxt_dcd

		andi cnt, $3f				; Mask 6 low bits
		cpi cnt, $3e				; Bit stuffing?
		brne rxt_data_2
		rjmp rxt_ret

rxt_data_2:
		lds cnt, RX_BITBUFF			; Get RX_BITBUFF

		clc							; C = 0
		sbrc tmp, RX_BIT			; Check for RX_BIT
		sec							; C = 1
		ror cnt						; C -> RX_BITBUFF >>= 1 -> C
		sts RX_BITBUFF, cnt			; Store RX_BITBUFF
		brcc rxt_dcd

		; Byte is ready
		; Check buffer length
		lds XL, RXB_FRLEN			; Get RXB_FRLEN low byte
		lds XH, (RXB_FRLEN + 1)		; Get RXB_FRLEN high byte
		lds YL, RXB_LEN				; Get RXB_LEN low byte
		lds YH, (RXB_LEN + 1)		; Get RXB_LEN high byte

		; X = RXB_FRLEN + RXB_LEN
		add XL, YL					; Add low byte
		adc XH, YH					; Add high byte

		; X = X - RXB_SIZE
		subi XL, low(RXB_SIZE - FRAME_MIN_LEN)
		sbci XH, high(RXB_SIZE - FRAME_MIN_LEN)
		brsh rxt_reset				; Abort receive if buffer is full

		mov tmp, cnt				; Copy data byte

#ifdef TEST_RX_BYTE
		rcall print
#endif
		; Add byte to RAM buffer
		lds XL, RXB_WRPTR			; Get RXB_WRPTR low byte
		lds XH, (RXB_WRPTR + 1)		; Get RXB_WRPTR high byte
		st X+, tmp					; Store byte

		; Wrap RXB_WRPTR around
		andi XH, high(RXB_ADDR + RXB_SIZE - 1)
		brne rxt_crc
		ldi XH, high(RXB_ADDR)

rxt_crc:
		sts RXB_WRPTR, XL			; Store RXB_WRPTR low byte
		sts (RXB_WRPTR + 1), XH		; Store RXB_WRPTR high byte
		rcall add2crc				; Add current byte to CRC

		; Adjust RXB_FRLEN
		lds XL, RXB_FRLEN			; Get RXB_FRLEN low byte
		lds XH, (RXB_FRLEN + 1)		; Get RXB_FRLEN high byte
		adiw XH:XL, 1				; RXB_FRLEN = RXB_FRLEN + 1
		sts RXB_FRLEN, XL			; Store RXB_FRLEN low byte
		sts (RXB_FRLEN + 1), XH		; Store RXB_FRLEN high byte

rxt_buf:
		ldi tmp, $80
		sts RX_BITBUFF, tmp			; RX_BITBUFF = 80H

rxt_dcd:
		; Check DCD counter
		lds tmp, DCD_CNT
		lds cnt, DCD_THR
		cp tmp, cnt
		brlo rxt_dcd_off
		dec tmp						; Do not allow DCD_CNT to overflow
		sts DCD_CNT, tmp

		; Turn DCD on
		sbi PORTD, DCD_PIN			; Turn 'DCD' LED on
		lds tmp, RXSR				; Get RXSR
		sbr tmp, (1 << DCD)			; Set DCD = 1
		rjmp rxt_exit

rxt_dcd_off:
		; Turn DCD off
		cbi PORTD, DCD_PIN			; Turn 'DCD' LED off
		lds tmp, RXSR				; Get RXSR
		cbr tmp, (1 << DCD)			; Set DCD = 0

rxt_exit:
		sts RXSR, tmp				; Store RXSR

rxt_ret:
#ifdef TESTING
		cbi PORTB, TEST_PIN
#endif
		ret

;---------------------------------------------------------
;		UART_TX - UART TX Task and PLAIN2KISS routines
;
;	Input:	UCSRA, RXB_LEN, KISSRB
;	Output:	RXB_LEN, KISSRB
;	Used:	X, Y, Z, tmp, cnt UTXB_LEN, UTXB_CNT
;---------------------------------------------------------
uart_tx:
#ifdef TESTING
		sbi PORTB, TEST_PIN
#endif

		; Check for UART ready
		sbis UCSRA, UDRE
		rjmp utx_return

		; Preserve Z (may be used by modulator)
		push ZH						
		push ZL

		; Check buffer length
		lds ZL, RXB_LEN				; Get RXB_LEN low byte
		lds ZH, RXB_LEN + 1			; Get RXB_LEN high byte
		adiw ZH:ZL, 0
		brne utx_work
		rjmp utx_ret				; Jump if RXB_LEN = 0 (no data yet)

utx_work:
		lds cnt, KISSRB				; Get KISSRB
		sbrc cnt, KF_FEND			; Skip if KISS frame not started yet
		rjmp utx_data				; Jump if data following

		; Check for KF_TYPE bit
		sbrc cnt, KF_TYPE
		rjmp utx_type				; Jump if time to send KISS frame type

		; Start new KISS frame
		sts UTXB_LEN, ZL			; UTXB_LEN = RXB_LEN (low byte)
		sts UTXB_LEN + 1, ZH		; UTXB_LEN = RXB_LEN (high byte)
		sts UTXB_CNT, ZL			; UTXB_CNT = RXB_LEN (low byte)
		sts UTXB_CNT + 1, ZH		; UTXB_CNT = RXB_LEN (high byte)
		sbr cnt, (1 << KF_TYPE)		; Set KF_TYPE bit
		ldi tmp, KISS_FEND			; Will send KISS FEND symbol
		rjmp utx_out

utx_type:
		; Send KISS frame type
		cbr cnt, (1 << KF_TYPE)		; Clear KF_TYPE bit
		sbr cnt, (1 << KF_FEND)		; Set KF_FEND bit (next byte - data)
		mov tmp, cnt				; Copy KISSRB
		andi tmp, 7					; Mask low 3 bits from KISSRB (this is a KISS frame type)
		rjmp utx_out

utx_data:
		; Get UART TX Buffer length
		lds XL, UTXB_CNT			; Get UTXB_CNT low byte
		lds XH, UTXB_CNT + 1		; Get UTXB_CNT high byte

		; Get RX buffer read pointer
		lds YL, RXB_RDPTR			; Get RXB_RDPTR low byte
		lds YH, RXB_RDPTR + 1		; Get RXB_RDPTR high byte

		ld tmp, Y+					; Get data byte

		; KISS symbol stufing if needed
		sbrc cnt, KF_FESC
		rjmp utx_esc				; Go to escaped mode

utx_continue:
		; Check if CRC16 bytes reached
		sbiw XH:XL, 2				; UTXB_CNT = UTXB_CNT - 2
		breq utx_end				; Branch if there are no more data bytes left
		adiw XH:XL, 1				; UTXB_CNT = UTXB_CNT + 1. Compensate previous substraction by 2

		cpi tmp, KISS_FEND			; Check for KISS FEND symbol present in data
		breq utx_escape
		cpi tmp, KISS_FESC			; Check for KISS FESC symbol present in data
		breq utx_escape

utx_len:
		sts UTXB_CNT, XL			; Store UTXB_CNT low byte
		sts UTXB_CNT + 1, XH		; Store UTXB_CNT high byte

		; Wrap RXB_RDPTR around
		andi YH, high(RXB_ADDR + RXB_SIZE - 1)
		cpi YH, high(RXB_ADDR)
		brsh utx_store
		ldi YH, high(RXB_ADDR)		; Preload with start of RX buffer

utx_store:
		sts RXB_RDPTR, YL			; Store RXB_RDPTR low byte
		sts RXB_RDPTR + 1, YH		; Store RXB_RDPTR high byte

utx_out:
		out UDR, tmp				; Send byte to UART
		sts KISSRB, cnt				; Store KISSRB
		rjmp utx_ret

utx_esc:
		; KISS Escaped mode
		cbr cnt, (1 << KF_FESC)		; Clear KF_FESC bit

		cpi tmp, KISS_FEND			; Check for KISS FEND symbol present in data
		breq utx_tfend

		ldi tmp, KISS_TFESC			; Will send KISS TFESC symbol
		rjmp utx_continue

utx_tfend:
		ldi tmp, KISS_TFEND			; Will send KISS TFEND symbol
		rjmp utx_continue

utx_escape:
		sbr cnt, (1 << KF_FESC)		; Set KF_FESC bit
		ldi tmp, KISS_FESC			; Will send KISS FESC symbol
		rjmp utx_out

utx_end:
		adiw YH:YL, 1				; Skip two CRC16 bytes

		lds XL, UTXB_LEN			; Get UTXB_LEN low byte
		lds XH, UTXB_LEN + 1		; Get UTXB_LEN high byte
		sub ZL, XL					; RXB_LEN = RXB_LEN - UTXB_LEN (low byte)
		sbc ZH, XH					; RXB_LEN = RXB_LEN - UTXB_LEN (high byte)

		sts RXB_LEN, ZL				; Store RXB_LEN low byte
		sts RXB_LEN + 1, ZH			; Store RXB_LEN high byte

		cbr cnt, (1 << KF_FEND)		; Clear KF_FEND bit
		ldi tmp, KISS_FEND			; Will send KISS FEND symbol
		rjmp utx_len

utx_ret:
		; Restore Z
		pop ZL
		pop ZH

utx_return:
#ifdef TESTING
		cbi PORTB, TEST_PIN
#endif
		ret
