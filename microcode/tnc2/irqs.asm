;************************************************************************
;		 		Interrupt handlers										*
;				  Version 0.0.3											*
;			     (c) 2006-2007 UR4MCK									*
;																		*
;************************************************************************

;---------------------------------------------------------
;		Timer/Counter2 Compare Match A handler
;
;	Input:	ADC
;	Output:	sample, T-flag
;	Used:	itmp, ss
;---------------------------------------------------------
T2_COMP:
#ifdef TESTING
		sbi PORTB, TEST_PIN
#endif

		in ss, SREG				; Save SREG

		in sample, ADCH			; Get ADC value
		sbi ADCSRA, ADSC		; Start new conversion

		; Bit-wait counter update
		in itmp, OCR2
		subi itmp, -SAMPLE_RATE
		out OCR2, itmp

		out SREG, ss			; Restore SREG
		set						; Set T-flag (new ADC sample is ready)

#ifdef TESTING
		cbi PORTB, TEST_PIN
#endif
		reti

;--------------------------------------------------------------
;		Timer/Counter1 Overflow handler
;
;	Input:	TIMER_STEP
;	Output:	T-flag
;	Used:	ss, itmp, Z, mul_lo (phase counter),
;			mul_hi (bitrate counter), sample (cycles counter)
;--------------------------------------------------------------
T1_OVF:
#ifdef TESTING
		sbi PORTB, TEST_PIN
#endif

		in ss, SREG				; Save SREG

		; Reload PWM counter
		ld itmp, Z
		out OCR1AL, itmp	

		; Phase increment
		lds itmp, TIMER_STEP
		add mul_lo, itmp
		brcc t1_rate
		inc ZL
		; Wrap around
		cpi ZL, (low(SINE_TAB) + SINE_TAB_LEN)
		brlo t1_rate
		ldi ZL, low(SINE_TAB)

t1_rate:
		; Bitrate counter
		ldi itmp, TX_RATE
		add mul_hi, itmp
		brcc t1_ret
		dec sample
		brne t1_ret

		; New bit period
		ldi sample, SINE_TAB_LEN
		ldi itmp, (1 << SREG_T)	; Set T-flag (new bit period)
		or ss, itmp
t1_ret:
		out SREG, ss			; Restore SREG

#ifdef TESTING
		cbi PORTB, TEST_PIN
#endif
		reti
