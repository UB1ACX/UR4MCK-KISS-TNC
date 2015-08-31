;************************************************************************
;			AFSK MODEM & KISS TNC										*
;				Version 0.0.4											*
;			   (c) 2006-2007 UR4MCK										*
;																		*
;		Changes:														*
;				28.04.07: add2crc was fixed to not allow ZH:ZL			*
;						  to change in T1_OVF							*
;																		*
;																		*
;************************************************************************

.include "m8def.inc"

//#define TESTING					; Uncomment this if you want to enable some of general testing routines
//#define TEST_ADC_BITS				; Uncomment this for ADC bits output enable (only for tests)
//#define TEST_ADC_SAMPLE			; Uncomment this for ADC sample output enable (only for tests)

; PINs definitions
.equ MODE_PIN		= PD5			; Used for select mode
.equ DCD_PIN		= PD6			; Used for 'DCD' LED
.equ PTT_PIN		= PD7			; Used for key up transmitter
.equ PWM_PIN		= PB1			; Used as modulator's ADC
#ifdef TESTING
.equ TEST_PIN		= PB0			; Just for TEST purposes
#endif
.equ SPI_SS_PIN		= PB2			; Used by SPI driver as '/SS' signal
.equ SPI_MOSI_PIN	= PB3			; Used by SPI driver as 'MOSI' signal
.equ SPI_MISO_PIN	= PB4			; Used by SPI driver as 'MISO' signal
.equ SPI_SCK_PIN	= PB5			; Used by SPI driver as 'SCK' signal

; Common definitions
.equ SYSTEM_CLK		= 16000000		; Oscillator frequency in Hz
.equ CRC_TAB_ADDR	= $0800			; HDLC CRC16 table
.equ HDLC_FLAG		= 0b01111110	; Special HDLC frame delimiter
.equ FRAME_MIN_LEN	= 17			; Minimal ax.25 frame length
.equ DEVICE_VER		= 3				; Current device version

; Buffer sizes definition
.equ TXB_SIZE		= 8192			; TX buffer size

; FRAM opcodes
.equ FRAM_READ_OP	= 0b00000011
.equ FRAM_WRITE_OP	= 0b00000010
.equ FRAM_WREN_OP	= 0b00000110

; KISS special symbols
.equ KISS_FEND		= $c0
.equ KISS_FESC		= $db
.equ KISS_TFEND		= $dc
.equ KISS_TFESC		= $dd

; KISS command types
.equ KISS_CMD_DATA	= $00
.equ KISS_CMD_DELAY	= $01
.equ KISS_CMD_P		= $02
.equ KISS_CMD_SLOT	= $03
.equ KISS_CMD_TAIL	= $04
.equ KISS_CMD_DUPLX	= $05
.equ KISS_CMD_HARDW	= $06

; KISS SET_HARDWARE command addresses
.equ KISS_HW_ADDR_UBRL	= $80
.equ KISS_HW_ADDR_UBRH	= $81
.equ KISS_HW_ADDR_L1	= $90

; Bits in TXSR
.equ FRAM_RECV		= 2
.equ FRAM_READY		= 3
.equ KISS_READY		= 4
.equ SEND_CRC		= 5
.equ SLOT			= 6

; Bits in RXSR
.equ LAST_S			= 7
.equ RX_TICK		= 6
.equ RX_BIT			= 5
.equ BIT_READY		= 4
.equ RX_STATE		= 3
.equ DCD			= 2
.equ RX_ACTIVE		= 0

; Bits in KISSRA/B
.equ KF_HW			= 3
.equ KF_CRC			= 4
.equ KF_TYPE		= 5
.equ KF_FESC		= 6
.equ KF_FEND		= 7

; AX.25 L1 defaults
.equ DEF_TX_DELAY	= 80
.equ DEF_TX_PERSIST	= 63
.equ DEF_TX_SLOT	= 10
.equ DEF_TX_TAIL	= 8
.equ DEF_DCD_THR	= (FRAME_MIN_LEN * 8)	; CHECK THIS
;.equ DEF_DCD_THR	= (FRAME_MIN_LEN * 14) ; TEST

; Default UART rate
.equ DEF_UART_RATE	= 57600

; Demodulator params
.equ SAMPLE_RATE	= $68			; ADC sample rate is 19200 sps
.equ METRIC_TAB_ADDR= $0900			; Metric table start address in FLASH
.equ COS_TAB_ADDR	= $0980			; Cosine table start address in FLASH
.equ RXB_ADDR		= $0100			; RX Buffer start address
.equ RXB_SIZE		= 768			; RX Buffer size in bytes
.equ RX_FILTER_LEN	= 16			; RX matched filter length
.equ RX_PHASE_INC	= 16			; RX phase increment steps
.equ RX_TICK_LEN	= (RX_FILTER_LEN * 12)

; Modulator params
.equ ADC_ZERO		= $7f			; Used for unsigned to signed convertion (usual values are: 0x81, 0x80, 0x7f, 0x7e)
.equ SINE_TAB_LEN	= 24			; Length of sine table used by modulator
.equ SINE_TAB_ADDR	= $0990			; Sine table start address in FLASH
.equ TX_RATE		= $76			; Bitrate is 1200 bps
.equ TX_MARK		= $76			; MARK frequency is 1200 Hz
.equ TX_SPACE		= $d8			; SPACE frequency is 2200 Hz

; EEPROM params
.equ EEPROM_ADDR	= $0010			; Start address of EEPROM parametrs map

; Register aliases
.def mul_lo			= r0
.def mul_hi			= r1
.def sum1_lo		= r2
.def sum1_hi		= r3
.def sum2_lo		= r4
.def sum2_hi		= r5

.def ss				= r15			; SREG save register
.def tmp			= r16			; Temporary register
.def cnt			= r17			; General counter register
.def itmp			= r18			; Temporary in IRQ handlers
.def sample			= r19			; A sample from ADC (RX), cycles counter (TX)

; Memory map in SRAM
.dseg

; Demodulator variables
RX_C1:				.byte RX_FILTER_LEN
RX_C2:				.byte RX_FILTER_LEN
RX_MEM:				.byte RX_FILTER_LEN
RX_D1:				.byte (RX_FILTER_LEN / 2)
RX_D2:				.byte (RX_FILTER_LEN / 4)
RX_MEMIDX:			.byte 1
RX_D1IDX:			.byte 1
RX_D2IDX:			.byte 1
RX_BITSTREAM:		.byte 1
RX_BITBUFF:			.byte 1
DCD_CNT:			.byte 1
DCD_THR:			.byte 1
SINE_TAB:			.byte SINE_TAB_LEN
RX_SHREG:			.byte 1			; RX Shift Register
RX_PHASE:			.byte 1			; RX Phase Register
RX_TICK_CNT:		.byte 1			; RX time ticks counter

; Modulator variables
TIMER_STEP:			.byte 1			; Timer step value used by modulator

; TX circular buffer params
TXB_LEN:			.byte 2			; Data length
TXB_WRPTR:			.byte 2			; Write pointer
TXB_RDPTR:			.byte 2			; Read pointer

; RX circular buffer params
RXB_LEN:			.byte 2
RXB_FRLEN:			.byte 2
UTXB_LEN:			.byte 2
UTXB_CNT:			.byte 2
RXB_WRPTR:			.byte 2
RXB_RDPTR:			.byte 2

; Status Registers
TXSR:				.byte 1			; TX Status Register
RXSR:				.byte 1			; RX Status Register
KISSRA:				.byte 1			; KISS Status Register A
KISSRB:				.byte 1			; KISS Status Register B

; AX.25 L1 params
TX_BYTE:			.byte 1			; Byte to transmit
TX_DELAY:			.byte 1			; TX Delay param
TX_PERSIST:			.byte 1			; p-Persistence param
TX_SLOT:			.byte 1			; Slot time param
TX_TAIL:			.byte 1			; TX Tail param
TX_CNT:				.byte 1			; Counter for DELAY and TAIL
TX_SLOT_CNT:		.byte 1			; Slot time counter

; Other variables
CRC16:				.byte 2			; Runtime CRC16 value
RND_VAL:			.byte 1			; Pseudo Random value
KISS_HW_ADDR:		.byte 1			; KISS 'Set Hardware' address value

.org RXB_ADDR
RXB_DATA:			.byte RXB_SIZE	; RX Buffer

.cseg
.org 0	; Interrupt handlers
		rjmp RESET					; Power on reset
		rjmp RESET					; External Interrupt0
		rjmp RESET					; External Interrupt1
		rjmp T2_COMP				; Timer/Counter2 Compare Match
		rjmp RESET					; Timer/Counter2 Overflow
		rjmp RESET					; Timer/Counter1 Capture Event
		rjmp RESET					; Timer/Counter1 Compare Match A
		rjmp RESET					; Timer/Counter1 Compare Match B
		rjmp T1_OVF					; Timer/Counter1 Overflow
		rjmp RESET					; Timer/Counter0 Overflow
		rjmp RESET					; Serial Transfer Complete
		rjmp RESET					; USART, Rx Complete
		rjmp RESET					; USART Data Register Empty
		rjmp RESET					; USART, Tx Complete
		rjmp RESET					; ADC Conversion Complete
		rjmp RESET					; EEPROM Ready
		rjmp RESET					; Analog Comparator
		rjmp RESET					; 2-wire Serial Interface
		rjmp RESET					; Store Program Memory Ready

RESET:
		; Set stack pointer
		ldi tmp, low(RAMEND)
		out SPL, tmp
		ldi tmp, high(RAMEND)
		out SPH, tmp

		rcall init					; Global initialization

		; Check mode
		sbi PORTD, MODE_PIN			; Activate pull-up resistor at MODE_PIN
		nop							; 1 cycle delay
		nop							; 1 cycle delay
		nop							; 1 cycle delay
		nop							; 1 cycle delay
		sbis PIND, MODE_PIN			; Skip to normal mode if 'TEST' jumper is not set

		rjmp test_mode				; Jump to test mode
		cbi PORTD,	MODE_PIN		; Deactivate pull-up at MODE_PIN

		rcall start_rx				; Start Receiver
main_loop:
		rcall receive_task			; Do receive task
		rcall transmit_task			; Do transmit task
		rjmp main_loop

;---------------------------------------------------------
;		Init
;
;	Input:	none
;	Output:	TXSR, KISSRA, SINE_TAB, TXB, TX_DELAY,
;			TX_PERSIST, TX_SLOT, TX_TAIL, Port D, Port B,
;			UART, SPI
;	Used:	tmp, cnt, X, Z
;---------------------------------------------------------
init:
		rcall eeprom_check				; Check and load some settings from EEPROM

		; Copy filter coefficients to RX_C1, RX_C2
		ldi ZH, high(COS_TAB_ADDR << 1)
		ldi ZL, low(COS_TAB_ADDR << 1)
		ldi XH, high(RX_C1)
		ldi XL, low(RX_C1)
		ldi cnt, (2 * RX_FILTER_LEN)
init_c:
		lpm tmp, Z+
		st X+, tmp
		dec cnt
		brne init_c

		; Init delay lines (RX_MEM, RX_D1, RX_D2)
		clr tmp
		ldi cnt, (7 * RX_FILTER_LEN / 4)
init_mem:
		st X+, tmp						; Set to zero
		dec cnt
		brne init_mem

		; Init TX buffer params
		ldi XH, high(TXB_LEN)			; Get start address of TXB params high byte
		ldi XL, low(TXB_LEN)			; Get start address of TXB params low byte
		ldi cnt, 6						; Total TXB params length
init_zero:
		st X+, tmp						; Store zero
		dec cnt							; Decrease counter
		brne init_zero

		; Init KISS Status Register A
		sts KISSRA, tmp

		; Set inital RND_VAL
		sts RND_VAL, tmp

		; Set RX_BITSTREAM = 0
		sts RX_BITSTREAM, tmp

		; Set RX_BITBUFF = 0
		sts RX_BITBUFF, tmp

		; Set DCD_CNT = 0
		sts DCD_CNT, tmp

		; Set KISS_HW_ADDR = 0
		sts KISS_HW_ADDR, tmp

		; Set RX_MEMIDX
		ldi tmp, low(RX_MEM)
		sts RX_MEMIDX, tmp

		; Set RX_D1IDX
		ldi tmp, low(RX_D1)
		sts RX_D1IDX, tmp

		; Set RX_D2IDX
		ldi tmp, low(RX_D2)
		sts RX_D2IDX, tmp

		; Copy sine data from FLASH to SINE_TAB
		ldi ZH, high(SINE_TAB_ADDR << 1); Get SINE address in FLASH high byte
		ldi ZL, low(SINE_TAB_ADDR << 1)	; Get SINE address in FLASH low byte
		ldi XH, high(SINE_TAB)
		ldi XL, low(SINE_TAB)
		ldi cnt, SINE_TAB_LEN
init_sine:
		lpm tmp, Z+						; Get byte from FLASH
		st X+, tmp						; Store it in SRAM
		dec cnt							; Decrease counter
		brne init_sine

		; Init TX Status Register
		ldi tmp, (1 << FRAM_READY)
		sts TXSR, tmp

		; Init Port D
		ldi tmp, (1 << PTT_PIN | 1 << DCD_PIN)
		out DDRD, tmp

		; Init Port B
#ifdef TESTING
		ldi tmp, (1 << TEST_PIN | 1 << PWM_PIN | 1 << SPI_MOSI_PIN | 1 << SPI_SCK_PIN | 1 << SPI_SS_PIN)
#else
		ldi tmp, (1 << PWM_PIN | 1 << SPI_MOSI_PIN | 1 << SPI_SCK_PIN | 1 << SPI_SS_PIN)
#endif
		out DDRB, tmp
		sbi PORTB, SPI_SS_PIN			; Disable FRAM chip

		; Init UART. TODO: use settings from EEPROM
		ldi tmp, (1 << TXEN | 1 << RXEN); Enable TX & RX
		out UCSRB, tmp

		; Init SPI: Master mode, CLK/4
		ldi tmp, (1 << SPE | 1 << MSTR)
		out SPCR, tmp

		sei								; Enable interrupts
		ret

;---------------------------------------------------------
;		ADD2CRC - Calculate HDLC CRC16 for incoming byte
;		Also used crc value for pseudo-random number
;		calculation
;
;	Input:	tmp, CRC16
;	Output:	CRC16
;	Used:	Z, tmp, cnt
;---------------------------------------------------------
add2crc:
		push tmp

		; Construct index
		lds cnt, CRC16				; Get CRC16 low byte
		eor tmp, cnt				; XOR it with input byte

		cli							; Disable interrupts because T1_OVF can change ZH:ZL
		push ZH						; Here I am tried to minimize cli - sei distance
		push ZL						; but nevertheless there are possible some of jitter in output signal

		ldi ZH, high(CRC_TAB_ADDR)	; Preload with CRC table high byte
		ldi ZL, low(CRC_TAB_ADDR)	; Preload with CRC table low byte
		add ZL, tmp					; Add index in table
		lsl ZL						; Needed because table in FLASH
		rol ZH						; // -- //

		; Calculate CRC
		lpm tmp, Z+					; Get low byte from table
		lds cnt, CRC16 + 1			; Get CRC16 high byte
		eor tmp, cnt				; XOR it with byte from table
		sts CRC16, tmp				; Store CRC16 low byte
		mov cnt, tmp
		lpm tmp, Z					; Get high byte from table

		pop ZL
		pop ZH
		sei							; Enable interrupts. T1_OVF now can work

		sts CRC16 + 1, tmp			; Store CRC16 high byte

		; Calculate pseudo-random value
		eor cnt, tmp				; XOR low and high bytes of CRC16 together
		lds tmp, RND_VAL			; Get previous RND_VAL
		eor tmp, cnt				; XOR it with xor'ed CRC16 bytes
		sts RND_VAL, tmp			; Store new RND_VAL

		pop tmp
		ret

;---------------------------------------------------------
;		EEPROM_SAVE - Save byte in internal EEPROM
;
;	Input:	tmp (byte), X (address)
;	Output:	none
;	Used:	none
;---------------------------------------------------------
eeprom_save:

		; Wait for EEPROM ready
		sbic EECR, EEWE
		rjmp eeprom_save

		; Set address
		out EEARH, XH
		out EEARL, XL

		; Write byte
		out EEDR, tmp

		cli				; Disable interrupts

		; Enable write
		sbi EECR, EEMWE

		; Start write
		sbi EECR, EEWE

		sei				; Enable interrupts
		ret

;---------------------------------------------------------
;		EEPROM_LOAD - Load byte from internal EEPROM
;
;	Input:	X (address)
;	Output:	tmp (byte)
;	Used:	none
;---------------------------------------------------------
eeprom_load:

		; Wait for EEPROM ready
		sbic EECR, EEWE
		rjmp eeprom_load

		; Set address
		out EEARH, XH
		out EEARL, XL

		; Read byte
		sbi EECR, EERE
		in tmp, EEDR
		ret

;---------------------------------------------------------
;		EEPROM_CHECK - Check and store/load settings from
;					   internal EEPROM
;
;	Input:	none
;	Output:	none
;	Used:	tmp, X (address)
;---------------------------------------------------------
eeprom_check:

		; Load DEV_VER
		ldi XH, high(EEPROM_ADDR)	; Get start of EEPROM map high byte
		ldi XL, low(EEPROM_ADDR)	; Get start of EEPROM map low byte
		rcall eeprom_load			; Load byte from EEPROM

		; Check DEV_VER
		cpi tmp, DEVICE_VER
		breq eec_load				; Load data from EEPROM if data is valid

		; Data in EEPROM is absent or corrupted
		; Rewriting EEPROM with defaults

		; Store DEV_VER
		ldi tmp, DEVICE_VER
		rcall eeprom_save

		; Store UART_RATE
		inc XL
		ldi tmp, low(SYSTEM_CLK / 16 / DEF_UART_RATE)
		rcall eeprom_save
		inc XL
		ldi tmp, high(SYSTEM_CLK / 16 / DEF_UART_RATE)
		rcall eeprom_save

		; Store TX_DELAY
		inc XL
		ldi tmp, DEF_TX_DELAY
		rcall eeprom_save

		; Store PERSISTENCE
		inc XL
		ldi tmp, DEF_TX_PERSIST
		rcall eeprom_save

		; Store SLOT_TIME
		inc XL
		ldi tmp, DEF_TX_SLOT
		rcall eeprom_save

		; Store TX_TAIL
		inc XL
		ldi tmp, DEF_TX_TAIL
		rcall eeprom_save

		; Store FULL_DUP
		inc XL
		clr tmp
		rcall eeprom_save

		; Store DCD_THR
		inc XL
		ldi tmp, DEF_DCD_THR
		rcall eeprom_save

eec_load:
		; Load settings from EEPROM

		ldi XH, high(EEPROM_ADDR + 1)	; Get start of EEPROM map high byte
		ldi XL, low(EEPROM_ADDR + 1)	; Get start of EEPROM map low byte

		; Load UART_RATE (low byte)
		rcall eeprom_load
		out UBRRL, tmp
		
		; Load UART_RATE (high byte)
		inc XL
		rcall eeprom_load
		out UBRRH, tmp

		; Load TX_DELAY
		inc XL
		rcall eeprom_load
		sts TX_DELAY, tmp
		sts TX_CNT, tmp					; Set TX_CNT = TX_DELAY

		; Load PERSISTENCE
		inc XL
		rcall eeprom_load
		sts TX_PERSIST, tmp

		; Load SLOT_TIME
		inc XL
		rcall eeprom_load
		sts TX_SLOT, tmp

		; Load TX_TAIL
		inc XL
		rcall eeprom_load
		sts TX_TAIL, tmp

		; Skip FULL_DUP
		inc XL

		; Load DCD_THR
		inc XL
		rcall eeprom_load
		sts DCD_THR, tmp
		ret

;---------------------------------------------------------
;		FRAM_SAVE - Save one byte in FRAM via SPI
;
;	Input:	tmp (byte), X (address)
;	Output:	none
;	Used:	none
;---------------------------------------------------------
fram_save:
		cbi PORTB, SPI_SS_PIN	; Enable FRAM chip

		push tmp				; Preserve byte

		; Send WRITE ENABLE OPCODE
		ldi tmp, FRAM_WREN_OP
		out SPDR, tmp
		rcall spi_wait

		sbi PORTB, SPI_SS_PIN	; Disable FRAM chip
		nop
		nop
		nop
		nop
		cbi PORTB, SPI_SS_PIN	; Enable FRAM chip

		; Send WRITE OPCODE
		ldi tmp, FRAM_WRITE_OP
		out SPDR, tmp
		rcall spi_wait

		; Send address (high byte)
		out SPDR, XH
		rcall spi_wait

		; Send address (low byte)
		out SPDR, XL
		rcall spi_wait

		; Send byte
		pop tmp
		out SPDR, tmp
		rcall spi_wait

		sbi PORTB, SPI_SS_PIN	; Disable FRAM chip
		ret

;---------------------------------------------------------
;		FRAM_LOAD - Load one byte from FRAM via SPI
;
;	Input:	X
;	Output:	tmp
;	Used:	none
;---------------------------------------------------------
fram_load:
		cbi PORTB, SPI_SS_PIN	; Enable FRAM chip

		; Send READ OPCODE
		ldi tmp, FRAM_READ_OP
		out SPDR, tmp
		rcall spi_wait
				
		; Send address (high byte)
		out SPDR, XH
		rcall spi_wait

		; Send address (low byte)
		out SPDR, XL
		rcall spi_wait

		; Send dummy byte
		out SPDR, tmp
		rcall spi_wait

		; Get byte
		in tmp, SPDR

		sbi PORTB, SPI_SS_PIN	; Disable FRAM chip
		ret

;---------------------------------------------------------
;		SPI_WAIT - Just wait until SPI transer is complete
;
;	Input:	none
;	Output: none
;	Used:	none
;---------------------------------------------------------
spi_wait:
		sbis SPSR, SPIF
		rjmp spi_wait
		ret

; *** Include other modules ***
.include "modulator.asm"
.include "demodulator.asm"
.include "testmode.asm"
.include "irqs.asm"
.include "tabs.asm"
