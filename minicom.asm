;==================================================================================
; Contents of this file are copyright Jonathan Nock
;
; http://10103.co.uk
; eMail: nockieboy@gmail.com
;
; Serial IO, basic ROM routines and CPM routines copyright Grant Searle.
; HEX routines from Joel Owens.
;
; http://searle.hostei.com/grant/index.html
; eMail: home.micros01@btinternet.com
;
;==================================================================================

;------------------------------------------------------------------------------
;
; Z80 Minicom II - Monitor Rom v1.3 (PIO & I2C)
;
; 1.3 - PIO & I2C
; 1.2 - CTC Routines
; 1.1 - PSG Routines
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; General Equates
;------------------------------------------------------------------------------
MCLS            .EQU     	0CH             ; Clear screen
EOS         	.EQU    	$0            	; End of string
CR            	.EQU     	0DH				; Carriage Return
LF              .EQU     	0AH				; Line Feed
CS              .EQU     	0CH            	; Clear screen

;------------------------------------------------------------------------------
; PIO Addresses & Equates
;------------------------------------------------------------------------------
PIO_A_D			.EQU		20H				; A Channel Data
PIO_A_C			.EQU		22H				; A Channel Commands
PIO_B_D			.EQU		21H				; B Channel Data
PIO_B_C			.EQU		23H				; B Channel Commands

;------------------------------------------------------------------------------
; CTC Channel Addresses
;------------------------------------------------------------------------------
CTC_0			.EQU		18H
CTC_1			.EQU		19H
CTC_2			.EQU		1AH
CTC_3			.EQU		1BH

;------------------------------------------------------------------------------
; Support Module (ATmega168) Addresses
;------------------------------------------------------------------------------
SM_C			.EQU		28H				; IO port for the ATmega168 (TEST)

;------------------------------------------------------------------------------
; AY-3-8912 PSG IN/OUT addresses for commands
;------------------------------------------------------------------------------
AY_IO_ADDR		.EQU		0EH				; AY-3-8912 IOA address
AY_WRITE		.EQU		09H				; AY-3-8912 OUT write address
AY_READ			.EQU		08H				; AY-3-8912 IN read address
AY_LATCH		.EQU		08H				; AY-3-8912 OUT latch address
AY_OUTPUT		.EQU		40H				; Value to set IO to OUTPUT

;------------------------------------------------------------------------------
; CF registers
;------------------------------------------------------------------------------
CF_DATA			.EQU		$10
CF_FEATURES		.EQU		$11
CF_ERROR		.EQU		$11
CF_SECCOUNT		.EQU		$12
CF_SECTOR		.EQU		$13
CF_CYL_LOW		.EQU		$14
CF_CYL_HI		.EQU		$15
CF_HEAD			.EQU		$16
CF_STATUS		.EQU		$17
CF_COMMAND		.EQU		$17
CF_LBA0			.EQU		$13
CF_LBA1			.EQU		$14
CF_LBA2			.EQU		$15
CF_LBA3			.EQU		$16

;------------------------------------------------------------------------------
;CF Features
;------------------------------------------------------------------------------
CF_8BIT			.EQU		1
CF_NOCACHE		.EQU		082H

;------------------------------------------------------------------------------
;CF Commands
;------------------------------------------------------------------------------
CF_READ_SEC		.EQU		020H
CF_WRITE_SEC	.EQU		030H
CF_SET_FEAT		.EQU 		0EFH


loadAddr		.EQU		0D000h				; CP/M load address
numSecs			.EQU		24					; Number of 512 sectors to be loaded

;------------------------------------------------------------------------------
;BASIC cold and warm entry points
;------------------------------------------------------------------------------
BASCLD			.EQU		$2000
BASWRM			.EQU		$2003

SER_BUFSIZE		.EQU		40H
SER_FULLSIZE	.EQU		30H
SER_EMPTYSIZE	.EQU		5

RTS_HIGH		.EQU		0E8H
RTS_LOW			.EQU		0EAH

SIOA_D			.EQU		$00
SIOA_C			.EQU		$02
SIOB_D			.EQU		$01
SIOB_C			.EQU		$03

		.ORG	$4000
;------------------------------------------------------------------------------
serABuf			.ds			SER_BUFSIZE
serAInPtr		.ds			2
serARdPtr		.ds			2
serABufUsed		.ds			1
;------------------------------------------------------------------------------
serBBuf			.ds			SER_BUFSIZE
serBInPtr		.ds			2
serBRdPtr		.ds			2
serBBufUsed		.ds			1
;------------------------------------------------------------------------------
basicStarted	.ds			1
IO_ADDR  		.ds    		1		; 1-byte space to store IO port for IO command
CHRBUF			.ds			2		; PHEX character buffer
CLKMEM			.ds			2		; Seconds-since-boot memory location
LZ_FLAG			.ds			1		; Flag to determine whether zeros should be shown in DECHL
;------------------------------------------------------------------------------
PIO_A_MODE		.ds			1		; Holds current PIO A mode
PIO_A_IO_CONF	.ds			1		; Holds current IO config for PIO A
PIO_B_MODE		.ds			1		; Holds current PIO B mode
PIO_B_IO_CONF	.ds			1		; Holds current IO config for PIO B
;------------------------------------------------------------------------------
I2C_BUFF		.ds			1		; Holds counter for iterations with I2C
;------------------------------------------------------------------------------
primaryIO		.ds			1
secNo			.ds			1
dmaAddr			.ds			2
;------------------------------------------------------------------------------
stackSpace		.ds			64
MSTACK   		.EQU    	$					; Stack top
;------------------------------------------------------------------------------
;                         START OF MONITOR ROM
;------------------------------------------------------------------------------
MON		.ORG	$0000							; MONITOR ROM RESET VECTOR
;------------------------------------------------------------------------------
; Reset
;------------------------------------------------------------------------------
RST00			DI								;Disable INTerrupts
				JP			MINIT				;Initialize Hardware and go
				NOP
				NOP
				NOP
				NOP
;------------------------------------------------------------------------------
; TX a character over serial, wait for TXDONE first.
;------------------------------------------------------------------------------
RST08			JP			conout
				NOP
				NOP
				NOP
				NOP
				NOP
;------------------------------------------------------------------------------
; RX a character from buffer wait until char ready.
;------------------------------------------------------------------------------
RST10			JP			conin
				NOP
				NOP
				NOP
				NOP
				NOP
;------------------------------------------------------------------------------
; Check input buffer status
;------------------------------------------------------------------------------
RST18			JP			CKINCHAR

;------------------------------------------------------------------------------
; CTC Interrupt vector table starting at Vector 58
;------------------------------------------------------------------------------
 		.ORG	$0058
		.DW		CTC_Int					; CTC channel 0 Vector in table
		.DW		CTC_Int					; CTC channel 1 Vector in table
		.DW		CTC_Int					; CTC channel 2 Vector in table
		.DW		CTC_CLK					; CTC channel 3 Vector in table

;------------------------------------------------------------------------------
; SIO Vector = 0x60
;------------------------------------------------------------------------------
		.DW		serialInt
		
;------------------------------------------------------------------------------
; Start of NMI interrupt
;------------------------------------------------------------------------------
		;.ORG 	$0066

		;.ORG 	$0070

;------------------------------------------------------------------------------
; Serial interrupt handlers
; Same interrupt called if either of the inputs receives a character
; so need to check the status of each SIO input.
;------------------------------------------------------------------------------
serialInt:		PUSH		AF
				PUSH		HL
				; Check if there is a char in channel A
				; If not, there is a char in channel B
				SUB			A
				OUT 		(SIOA_C),A
				IN			A,(SIOA_C)			; Status byte D2=TX Buff Empty, D0=RX char ready	
				RRCA							; Rotates RX status into Carry Flag,	
				JR			NC,serialIntB
; Serial Port A - Character received
serialIntA:		LD			HL,(serAInPtr)
				INC			HL
				LD			A,L
				CP			(serABuf+SER_BUFSIZE) & $FF
				JR			NZ,notAWrap
				LD			HL,serABuf
notAWrap:		LD			(serAInPtr),HL
				IN			A,(SIOA_D)
				LD			(HL),A
				LD			A,(serABufUsed)
				INC			A
				LD			(serABufUsed),A
				CP			SER_FULLSIZE
				JR			C,rtsA0
				LD			A,$05
				OUT  		(SIOA_C),A
				LD			A,RTS_HIGH
				OUT  		(SIOA_C),A
rtsA0:			POP			HL
				POP			AF
				EI
				RETI
				
; Serial Port B - Character received
serialIntB:		LD			HL,(serBInPtr)
				INC			HL
				LD			A,L
				CP			(serBBuf+SER_BUFSIZE) & $FF
				JR			NZ,notBWrap
				LD			HL,serBBuf
notBWrap:		LD			(serBInPtr),HL
				IN			A,(SIOB_D)				; Get char from Port B
				LD			(HL),A					; Load it into the serial buffer
				LD			A,(serBBufUsed)			; Get serial buffer size
				INC			A						; Increment it
				LD			(serBBufUsed),A			; Update with incremented value
				CP			SER_FULLSIZE			; Check if buffer is full
				JR			C,rtsB0					; No, go to exit
				LD			A,$05					; Yes, hold RTS HIGH
				OUT  		(SIOB_C),A
				LD			A,RTS_HIGH
				OUT  		(SIOB_C),A
rtsB0:			POP			HL
				POP			AF
				EI
				RETI

;------------------------------------------------------------------------------
; CTC Null Interrupt Handler
; This is called when an unhandled interrupt from the CTC is triggered
;------------------------------------------------------------------------------
CTC_Int:		PUSH		AF
				PUSH		HL
				
				LD			HL,INTERR
				CALL		MPRINT
				
				POP			HL
				POP			AF
				EI
				RETI
				
;------------------------------------------------------------------------------
; CTC CLOCK Interrupt Handler
; This is called every second and increments a 16-bit value in (MEMCLK)
;------------------------------------------------------------------------------
CTC_CLK:		PUSH		AF
				PUSH		HL
				
				LD			HL,(CLKMEM)			; Load 16-bit value into HL
				INC			HL					; Increment by 1
				LD			(CLKMEM),HL			; Write the result back
				
				POP			HL
				POP			AF
				EI
				RETI

;------------------------------------------------------------------------------
; Console input routine
; Check port contents to determine which input port to monitor.
;------------------------------------------------------------------------------
RXA:
conin:			PUSH		HL
				; Check if there is a char in channel A
				; or channel B - keep looping til one is found
waitForChar:	LD			A,(serABufUsed)
				CP			$00
				JR			NZ,gotCharA
				LD			A,(serBBufUsed)
				CP			$00
				JR			NZ,gotCharB
				JR			waitForChar
coninA:
waitForCharA:	LD			A,(serABufUsed)
				CP			$00
				JR			Z, waitForCharA
gotCharA:		LD			HL,(serARdPtr)
				INC			HL
				LD			A,L
				CP			(serABuf+SER_BUFSIZE) & $FF
				JR			NZ, notRdWrapA
				LD			HL,serABuf

notRdWrapA:		DI
				LD			(serARdPtr),HL
				LD			A,(serABufUsed)
				DEC			A
				LD			(serABufUsed),A
				CP			SER_EMPTYSIZE
				JR			NC,rtsA1
				LD   		A,$05
				OUT  		(SIOA_C),A
				LD   		A,RTS_LOW
				OUT  		(SIOA_C),A

rtsA1:			LD			A,(HL)
				EI
				POP			HL
				RET												; Char ready in A

RXB:
coninB:
waitForCharB:	LD			A,(serBBufUsed)
				CP			$00
				JR			Z, waitForCharB
gotCharB:		LD			HL,(serBRdPtr)
				INC			HL
				LD			A,L
				CP			(serBBuf+SER_BUFSIZE) & $FF
				JR			NZ, notRdWrapB
				LD			HL,serBBuf

notRdWrapB:		DI
				LD			(serBRdPtr),HL
				LD			A,(serBBufUsed)
				DEC			A
				LD			(serBBufUsed),A
				CP			SER_EMPTYSIZE
				JR			NC,rtsB1
				LD   		A,$05
				OUT  		(SIOB_C),A
				LD   		A,RTS_LOW
				OUT  		(SIOB_C),A

rtsB1:			LD			A,(HL)
				EI
				POP			HL
				RET												; Char ready in A

;------------------------------------------------------------------------------
; Console output routine
; Use the "primaryIO" flag to determine which output port to send a character.
;------------------------------------------------------------------------------
TXA:
conout:			PUSH		AF						; Store character
				LD			A,(primaryIO)
				CP			0
				JR			NZ,conoutB1
				JR			conoutA1

conoutA:		PUSH		AF
conoutA1:		CALL		CKSIOA					; See if SIO channel A is finished transmitting
				JR			Z,conoutA1				; Loop until SIO flag signals ready
				POP			AF						; RETrieve character
				OUT			(SIOA_D),A				; OUTput the character
				RET

TXB:
conoutB:		PUSH		AF
conoutB1:		CALL		CKSIOB					; See if SIO channel B is finished transmitting
				JR			Z,conoutB1				; Loop until SIO flag signals ready
				POP			AF						; RETrieve character
				OUT			(SIOB_D),A				; OUTput the character
				RET

;------------------------------------------------------------------------------
; I/O status check routine
; Use the "primaryIO" flag to determine which port to check.
;------------------------------------------------------------------------------
CKSIOA:
				SUB			A
				OUT 		(SIOA_C),A
				IN		   	A,(SIOA_C)				; Status byte D2=TX Buff Empty, D0=RX char ready	
				RRCA								; Rotates RX status into Carry Flag,	
				BIT		  	1,A						; Set Zero flag if still transmitting character	
				RET

CKSIOB:
				SUB			A
				OUT 		(SIOB_C),A
				IN   		A,(SIOB_C)				; Status byte D2=TX Buff Empty, D0=RX char ready	
				RRCA								; Rotates RX status into Carry Flag,	
				BIT  		1,A						; Set Zero flag if still transmitting character	
				RET

;------------------------------------------------------------------------------
; Check if there is a character in the input buffer
; Use the "primaryIO" flag to determine which port to check.
;------------------------------------------------------------------------------
CKINCHAR:
				LD			A,(primaryIO)
				CP			0
				JR			NZ,ckincharB
ckincharA:		LD			A,(serABufUsed)
				CP			$0
				RET
ckincharB:
				LD			A,(serBBufUsed)
				CP			$0
				RET

;------------------------------------------------------------------------------
; Filtered Character I/O
;------------------------------------------------------------------------------
RDCHR:
				RST			10H
				CP			LF
				JR			Z,RDCHR						; Ignore LF
				CP			ESC
				JR			NZ,RDCHR1
				LD			A,CTRLC						; Change ESC to CTRL-C
RDCHR1:			RET

WRCHR:
				CP			CR
				JR			Z,WRCRLF					; When CR, write CRLF
				CP			MCLS
				JR			Z,WR						; Allow write of "MCLS"
				CP			' '							; Don't write out any other control codes
				JR			C,NOWR						; ie. < space
WR:				RST			08H
NOWR:			RET

WRCRLF:
				LD			A,CR
				RST			08H
				LD			A,LF
				RST			08H
				LD			A,CR
				RET

;------------------------------------------------------------------------------
; Initialise hardware and start main loop
;------------------------------------------------------------------------------
MINIT:
				LD   		SP,MSTACK					; Set the Stack Pointer
				LD			HL,serABuf
				LD			(serAInPtr),HL
				LD			(serARdPtr),HL
				LD			HL,serBBuf
				LD			(serBInPtr),HL
				LD			(serBRdPtr),HL
				XOR			A							;0 to accumulator
				LD			(serABufUsed),A
				LD			(serBBufUsed),A
				CALL		INIT_CTC
				JP			INIT_PIO
				
;------------------------------------------------------------------------------
;   Initialise CTC with all channels on hold
;------------------------------------------------------------------------------
INIT_CTC:
				LD			A,00000011b			; int off, timer on, prescaler=16, don't care
												; ext. TRG edge, start timer on loading constant,
												; no time constant follows, sw-rst active, this
												; is a control command
				OUT			(CTC_0),A			; Channel 0 is on hold now
				OUT			(CTC_1),A			; Channel 1 is on hold now
				OUT			(CTC_2),A			; Channel 2 is on hold now
				OUT			(CTC_3),A			; Channel 3 is on hold now
				
				RET

;------------------------------------------------------------------------------
;	Initialise PIO Port B for I2C
;------------------------------------------------------------------------------
INIT_PIO:
				LD			A,0CFh				; Set PIO B to bit mode
				LD			(PIO_B_MODE),A		; Update global PIO B mode status variable
				OUT			(PIO_B_C),A
				
				LD			A,0FFh				; Set D7-D0 to input mode
				LD			(PIO_B_IO_CONF),A	; Update global PIO B IO status variable
				OUT			(PIO_B_C),A			; Write IO configuration into PIO B
				
				LD			A,0FCh				; If direction of B1 or B0 changes to output
												; the pin will drive L
				OUT			(PIO_B_D),A			; Load PIO B output register

;------------------------------------------------------------------------------
;	Initialise SIO - Port A
;------------------------------------------------------------------------------
INIT_SIO:
				LD			A,$00
				OUT			(SIOA_C),A
				LD			A,$18			; Write into WR0: channel reset
				OUT			(SIOA_C),A

				LD			A,$04			; Select Write Register 4
				OUT			(SIOA_C),A
				LD			A,$C4			; CLK/64, 1 stop bit, no parity
				OUT			(SIOA_C),A

				LD			A,$01			; Select Write Register 1
				OUT			(SIOA_C),A
				LD			A,$18			; Interrupt on all Rx chars
				OUT			(SIOA_C),A

				LD			A,$03			; Select Write Register 3
				OUT			(SIOA_C),A
				LD			A,$E1			; Rx 8 bits/char, Rx enable
				OUT			(SIOA_C),A

				LD			A,$05			; Select Write Register 5
				OUT			(SIOA_C),A
				LD			A,RTS_LOW		; DTR, Tx 8 bits/char, Tx enable
				OUT			(SIOA_C),A

;------------------------------------------------------------------------------
; Initialise SIO - Port B
;------------------------------------------------------------------------------
				LD			A,$00			; Select Write Register 0
				OUT			(SIOB_C),A		;
				LD			A,$18			; Channel reset
				OUT			(SIOB_C),A		;

				LD			A,$04			; Select Write Register 4
				OUT			(SIOB_C),A		;
				LD			A,$C4			; CLK/64, 1 stop bit, no parity
				OUT			(SIOB_C),A		;

				LD			A,$01			; Select Write Register 1
				OUT			(SIOB_C),A		;
				LD			A,$18			; Interrupt on all Rx chars
				OUT			(SIOB_C),A		;

				LD			A,$02			; Select Write Register 2
				OUT			(SIOB_C),A		;
				LD			A,$60			; INTERRUPT VECTOR
				OUT			(SIOB_C),A		;
	
				LD			A,$03			; Select Write Register 3
				OUT			(SIOB_C),A		;
				LD			A,$E1			; Rx 8 bits/char, Rx enable
				OUT			(SIOB_C),A		;

				LD			A,$05			; Select Write Register 5
				OUT			(SIOB_C),A		;
				LD			A,RTS_LOW		; DTR, Tx 8 bits/char, Tx enable
				OUT			(SIOB_C),A		;

;------------------------------------------------------------------------------
;	Set up the CPU to run in Interrupt Mode 2
;------------------------------------------------------------------------------
				LD			A,$00
				LD			I,A							; Load I reg with zero
				IM			2							; Set int mode 2
				EI										; Enable interrupt

				CALL		CTCCLK						; Initialise the seconds-since-boot
														; counter

;------------------------------------------------------------------------------
; Display the "Press space to start" message on both consoles and wait for input
;------------------------------------------------------------------------------
				LD			A,$00
				LD			(primaryIO),A				; Set Port A as primary IO
				;LD   		HL,MINITTXTA
				;CALL 		MPRINT
				;LD			A,$01
				;LD			(primaryIO),A
				;LD   		HL,MINITTXTB
				;CALL 		MPRINT
				; Wait until space is in one of the buffers to determine the active console
waitForSpace:	;CALL 		ckincharA
				;JR			Z,notInA
				;LD			A,$00
				;LD			(primaryIO),A
				;CALL		conin
				;CP			' '
				;JP			NZ, waitForSpace
				;JR			spacePressed

notInA:			;CALL		ckincharB
				;JR			Z,waitForSpace
				;LD			A,$01
				;LD			(primaryIO),A
				;CALL		conin
				;CP			' '
				;JP			NZ, waitForSpace
				;JR			spacePressed

spacePressed:
				; Clear message on both consoles
				;LD			A,MCLS
				;CALL		conoutA
				;CALL		conoutB

				; primaryIO is now set to the channel where SPACE was pressed
				;CALL 		TXCRLF						; TXCRLF

;------------------------------------------------------------------------------
; Command interpreter for Direct Mode
;------------------------------------------------------------------------------
COMMANDINIT:
				LD			HL,SIGNON1      ; Sign-on message again
				CALL		MPRINT          ; Output string
				LD			HL,DMMSG		; Direct Mode message
				CALL		MPRINT			; Print it
				CALL		CRLF
COMMAND:
				LD			HL,CPROMPT		; Show the prompt
CMD2:			CALL		MPRINT
				LD			A,'>'			; Load A register with the command prompt character
				CALL		TXA				; Print the character in the A register
				LD			HL,BUFFER		; Point to buffer
				CALL		CINPUT			; Get a command
				JP			CFNDWRD			; Parse input for commands

SHORTPROMPT:
				LD			HL,CSHTPRT		; Load the OK prompt without extra CRLF
				JP			CMD2
;------------------------------------------------------------------------------
SHOWERR:
				LD			HL,ERMSG		; Load error message
				CALL		MPRINT			; Print the message
				JP			COMMAND			; Return to command line
				
;------------------------------------------------------------------------------
CRLF:
				PUSH		AF
				LD			A,CR					; Print CR and LF control codes.
				CALL		TXA
				LD			A,LF
				CALL		TXA
				POP			AF
				RET

;------------------------------------------------------------------------------
CGETCHR:
				INC     	HL              		; Point to next character
        		LD      	A,(HL)          		; Get next code string byte
        		CP      	':'             		; Z if ':'
        		RET     	NC              		; NC if > "9"
        		CP      	' '
        		JP      	Z,CGETCHR      	; Skip over spaces
        		CP      	'0'
        		CCF                     				; NC if < '0'
        		INC     	A               		; Test for zero - Leave carry
        		DEC     	A               		; Z if Null
        		RET

;------------------------------------------------------------------------------
; Decode input string to find commands and call appropriate routine
;------------------------------------------------------------------------------
CFNDWRD:
				LD      	DE,CWORDS-1      	; Point to table
        		LD      	B,DBASIC-1        	; First token value -1
        		LD      	A,(HL)          	; Get byte
        		CP      	'a'             	; Less than 'a' ?
        		JP      	C,CSEARCH        	; Yes - search for words
        		CP      	'z'+1           	; Greater than 'z' ?
        		JP      	NC,CSEARCH       	; Yes - search for words
        		AND     	01011111B       	; Force upper case
        		LD      	(HL),A          	; Replace char with uppercase version
CSEARCH:
				LD      	C,(HL)       		; Search for a word
        		EX      	DE,HL
CGETNXT:
				INC     	HL              	; Get next reserved word
        		OR			(HL)            	; Start of word?
        		JP      	P,CGETNXT        	; No - move on
        		INC     	B               	; Increment token value
        		LD      	A, (HL)				; Get byte from table
        		AND     	01111111B       	; Strip bit 7
        		JP	     	Z,SHOWSYERR			; Syntax Error if end of list
        		CP      	C               	; Same character as in buffer?
        		JP      	NZ,CGETNXT       	; No - get next word
        		EX     		DE,HL
        		PUSH    	HL              	; Save start of word
CNXTBYT:
				INC     	DE              	; Look through rest of word
        		LD      	A,(DE)          	; Get byte from table
        		OR      	A               	; End of word ?
        		JP      	M,CMATCH         	; Yes - Match found
        		LD      	C,A             	; Save it
        		LD      	A,B             	; Get token value
        		CP      	DDUMP           	; Is it "DUMP" token ?
        		JP      	NZ,CNOSPC        	; No - Don't allow spaces
        		CALL    	CGETCHR          	; Get next character
        		DEC     	HL              	; Cancel increment from CGETCHR
CNOSPC: 
				INC     	HL              	; Next byte
        		LD      	A,(HL)          	; Get byte
        		CP      	'a'             	; Less than 'a' ?
				JP     		C,CNOCHNG        	; Yes - don't change
        		AND     	01011111B       	; Make upper case
CNOCHNG:
				CP     		C               	; Same as in buffer ?
        		JP     		Z,CNXTBYT        	; Yes - keep testing
        		POP			HL              	; Get back start of word
        		JP     		CSEARCH          	; Look at next word
CMATCH:
				INC			SP					; Increment stack pointer, effectively
				INC			SP					; erasing last PUSH (with HL value in it)
				POP			IX
				LD     		C,B             	; Word found - Save token value
				INC			HL					; Next char after command
				PUSH		HL					; Save code string address
        		EX     		DE,HL				; Swap HL back and go into EXECUTE
EXECUTE:
				LD			A,C					; Load saved token into A
				SUB			DBASIC            	; Is it a token?
        		JP			C,SHOWSYERR    		; No - Syntax Error
        		CP			DXEST+1-DBASIC    	; Is it between BASIC and last command inclusive?
        		JP			NC,SHOWSYERR       	; No, not a key word - Syntax Error
        		RLCA                    		; Double it
        		LD			C,A             	; BC = Offset into table
        		LD			B,0
        		LD			HL,CWORDTB       	; Keyword address table
        		ADD     	HL,BC           	; Point to routine address
				LD			E,(HL)          	; Get LSB of routine address
				INC			HL
				LD			D,(HL)          	; Get MSB of routine address
				EX			DE,HL
				JP			(HL)
				
;------------------------------------------------------------------------------
; Print string of characters to Serial Port until byte=$00 (EOS)
;------------------------------------------------------------------------------
MPRINT:			PUSH		AF
MPR:			LD   		A,(HL)				; Get character
				CP   		EOS					; Is it $00 ?
				JR  		Z,MPEX				; Then RETurn on terminator
				RST  		08H					; Print it
				INC  		HL					; Next Character
				JP   		MPR					; Continue until $00
				
MPEX:			POP			AF
				RET

TXCRLF:
				LD   		A,CR					; 
				RST  		08H					; Print character 
				LD   		A,LF					; 
				RST  		08H					; Print character
				RET
				
;------------------------------------------------------------------------------
; Print string of characters to Serial Port B until byte=$00 (EOS)
;------------------------------------------------------------------------------
BPRINT:			PUSH		AF
BPR:			LD   		A,(HL)				; Get character
				CP   		EOS					; Is it $00 ?
				JR  		Z,BPEX				; Then RETurn on terminator
				CALL  		TXB					; Print it to serial port B
				INC  		HL					; Next Character
				JP   		BPR					; Continue until $00
				
BPEX:			POP			AF
				RET

TXBCRLF:
				LD   		A,CR				; 
				CALL  		TXB					; Print character 
				LD   		A,LF				; 
				CALL  		TXB					; Print character
				RET

;------------------------------------------------------------------------------
; Take a line of text as input, handle special characters
;------------------------------------------------------------------------------
CINPUT:
				PUSH		HL					; Push the contents of HL (whatever they are) onto the stack
NOBS:
				LD			A,0					; Input a string to (HL), interpreting control characters.
				LD			(HL),A				; Clear any previous commands
				LD			B,A					; Character count stored in B - reset to 0
INPUTL:
				CALL		RXA					; Get a character from the ACIA
				CP			BKSP				; Backspace? (Set in basic.asm)
				JP			Z,INBS				; Go to backspace function
				CP			DEL					; Delete? (Set in basic.asm)
				JP			Z,INBS				; Go to backspace function
				CP			13					; Return
				JP			Z,INPUTX
				LD			(HL),A
				INC			HL
				INC			B
				CALL		TXA					; Echo character
				JP			INPUTL

INBS:
				DEC			B					; Command length by 1
				JP			M,NOBS				; If negative, no further backspace allowed
				PUSH		AF					; Store A contents on stack
				CALL		DOBKSP				; Backspace
				POP			AF					; Restore A
				DEC			HL					; Move the buffer point back one
				JP			INPUTL				

INPUTX:
				CALL		CRLF				; Print new line
				POP			HL					; Restore the contents of HL from the stack (buffer location)
				RET								; Return to the COMMAND routine

;------------------------------------------------------------------------------
; BACKSPACE
; Destroys A
;------------------------------------------------------------------------------				
DOBKSP:			LD			A,8					; Backspace
				CALL		TXA					; Transmit the backspace
				LD			A,' '				; Rubout
				CALL		TXA					; Rubout the previous character
				LD			A,8					; Backspace
				CALL		TXA					; Transmit the backspace again
				RET
				
;------------------------------------------------------------------------------
; Custom code can go here, otherwise default to cold start
;------------------------------------------------------------------------------
USRCODE:
				POP			HL						; Dump command input from stack
				LD			A,'U'
				CALL		TXA
				LD			A,'S'
				CALL		TXA
				LD			A,'R'
				CALL		TXA
				CALL		CRLF
				JP			COMMAND

;------------------------------------------------------------------------------
; Cold-start BASIC
;------------------------------------------------------------------------------
COLDSTART:
				POP			HL						; Dump command input from stack
				LD        	A,'B'           		; Set the BASIC STARTED flag
				LD        	(basicStarted),A
				JP        	BASCLD					; Start BASIC COLD

;------------------------------------------------------------------------------
; Print the welcome message again
;------------------------------------------------------------------------------
VER:
				POP			HL						; Dump command input from stack
				LD			HL,SIGNON1
				CALL		MPRINT
				LD			HL,DMMSG
				CALL		MPRINT
				JP			COMMAND

;------------------------------------------------------------------------------
; PSG test commands - takes an address from the command line and writes it to
; the PSG IO port, or reads the IO port value
;------------------------------------------------------------------------------
CPSGOUT:
				POP			HL						; Get command line pointer
				CALL		GETBYTE					; Get 1-byte value from command line
				LD			HL,AYPWRITE				; Display the port write text
				CALL		MPRINT
				LD			A,E						; Load value into A
				CALL		PHEX					; Display it...
				LD			A,'h'					; ...with an 'H' on the end
				CALL		TXA
				
				; Set IOA to OUTPUT
				LD			A,$07					; Select address R7 (select ENABLE register)
				OUT			(AY_LATCH),A			; Latch address R7
				LD			A,AY_OUTPUT				; 
				OUT			(AY_WRITE),A			; Set R7 to 40H (IOA set to output)
				
				; Set value in IOA
				LD			A,AY_IO_ADDR			; Load A with IOA Register address
				OUT			(AY_LATCH),A			; Latch register in PSG
				LD			A,E						; Load A with value
				OUT			(AY_WRITE),A			; Write value to PSG
				
				JP			COMMAND					; Return to Direct Mode CLI
				
CPSGIN:
				POP			HL						; Dump command line pointer
				LD			HL,AYPREAD				; Display read text
				CALL		MPRINT
				
				; Set IOA to INPUT
				LD			A,$07					; Select address R7 (select ENABLE register)
				OUT			(AY_LATCH),A			; Latch address R7
				LD			A,0
				OUT			(AY_WRITE),A			; Set R7 to 0 (IOA set to input)
				
				; Read IOA
				LD			A,AY_IO_ADDR			; Load A with IOA Register address
				OUT			(AY_LATCH),A			; Latch register in PSG
				IN			A,(AY_READ)				; Read register
				
				CALL		PHEX					; Print the result
				LD			A,'h'					; ...with an 'h' on the end
				CALL		TXA
				
				JP			COMMAND					; Return to Direct Mode CLI
				
CPSGERR:		; There was an error in the IO access (this routine not used)
				LD			HL,IOERR
				CALL		MPRINT
				JP			COMMAND

;------------------------------------------------------------------------------
; CTC CLOCK Interrupt Setup - Should fire every second (depends on system clock frequency)
; Because of the way the clock division works (CPU_CLOCK/(TO2 output)^2), a value of 200
; had to be chosen for TO2, as 200^2 = 40000, so the first division results in 100, making
; the second division easy (100/100 = 1 interrupt per second, pretty much precisely.)
;------------------------------------------------------------------------------
CTCCLK:
				LD			A,$00
				LD			(CLKMEM),A				; Initialise memory location used to
				LD			(CLKMEM+1),A			; store the 16-bit seconds counter
				
				; init CH2, which divides CPU CLK by 65536 providing a clock signal
				; at TO2. TO2 should be connected to TRG3.
				LD			A,00100111b				; int off, timer on, prescaler=256, no ext. start,
													; start upon loading time constant, time constant
													; follows, sw reset, this is a ctrl cmd
				OUT			(CTC_2),A
				LD			A,0C8h					; Time constant 200 defined
				OUT			(CTC_2),A				; and loaded into channel 2 (where it's squared)
													; TO2 outputs f=CPU_CLK (4 MHz)/ 40000 = 100
				
				; init CH3 - input TRG of CH3 is supplied by clock signal from TO2
				; CH3 divides TO2 clock by AFh
				; CH3 interrupts CPU appr. every 2 secs to service int routine CTC_Int
				LD			A,11000111b				; int on, counter on, prescaler don't care, edge
													; don't care, time trigger don't care, time
													; constant follows, sw reset, this is ctrl cmd
				OUT			(CTC_3),A
				LD			A,064h					; Time constant 64h defined
				OUT			(CTC_3),A				; and loaded into channel 3
													; This will divide TO2 by 100 for one
													; interrupt per minute
				
				LD			A,58h					; Int vector defined in bit 7-3, bit 2-1 don't care,
													; bit 0 = 0 (for vector)
				OUT			(CTC_0),A				; and loaded into channel 0
				
				RET

;------------------------------------------------------------------------------				 
; Test serial Tx to the Support Module
; Destroys A
;------------------------------------------------------------------------------
SM_TX:
				POP			HL						; Dump command line pointer
				LD			HL,BTSTMSG				; Transmit a single 'X'
				CALL		BPRINT					; to Port B
				JP			COMMAND
				
;------------------------------------------------------------------------------				 
; Display 256 bytes of memory starting at 16-bit pointer (HL)
; Destroys DE, HL
;------------------------------------------------------------------------------
MEMD:
				POP			HL						; Get command input
				CALL		GETD					; Get memory address
				EX			DE,HL					; Swap it into HL
				CALL		MEMV					; Display 256 bytes
				JP			COMMAND					; Return to command interpreter
				
;------------------------------------------------------------------------------				 
; MEMX - Memory Editor
;------------------------------------------------------------------------------
MEMX:
				POP			HL						; Get command input to display
				CALL		GETD					; the first 256 bytes from the
				EX			DE,HL					; address provided after the command
PRMEMX:
				LD			A,MCLS					; Clear screen
				CALL		TXA
				PUSH		HL						; Store the current address on the stack
				CALL		MEMV					; Display 256 bytes
				CALL		CRLF
				LD			HL,MEMXMNU			; Load the MEMX command list string
				CALL		MPRINT					; Print it
				POP			HL						; Restore the current memory page address
MEMXIL:
				CALL		RXA						; Get input char
				CP			','
				JP			Z,BKMEMX				; Display previous 256 bytes
				CP			'.'
				JP			Z,NXMEMX				; Display next 256 bytes
				CP			'X'
				JP			Z,COMMAND			; Return to command interpreter
				CP			'x'
				JP			Z,COMMAND			; Return to command interpreter
				CP			'P'
				JP			Z,MEMXPK				; Poke a value into memory
				CP			'p'
				JP			Z,MEMXPK				; Poke a value into memory
				CP			'G'
				JP			Z,MEMXGO2			; Jump to address location
				CP			'g'
				JP			Z,MEMXGO2			; Jump to address location
				; No commands recognised
				JP			MEMXIL					; Default behaviour for unrecognized commands - loop

RTCLOOP:
				POP			DE						; Restore DE contents
				CALL		CRLF						; New line
				JP			PRMEMX				; Display memory location in HL
				
BKMEMX:
				PUSH		DE						; Preserve contents of DE registers
				LD			DE,$0100				; Load value 256 into DE register
				AND			A							; Clear carry flag
				SBC			HL,DE					; Subtract DE from HL as a 16-bit op
				JP			NC,RTCLOOP			; No carry, display the new memory location
				LD			HL,$FF00				; Trying to go past start of RAM, so
															; set the address to the top ($FF00H)
				JP			RTCLOOP				; Display the new memory location

NXMEMX:
				PUSH		DE						; Preserve contents of DE registers
				LD			DE,$0100				; Load value 256 into DE register
				AND			A							; Clear carry flag
				ADC			HL,DE					; Subtract DE from HL as a 16-bit op
				JP			NC,RTCLOOP			; No carry, display the new memory location
				LD			HL,$0000				; Trying to go past end of RAM, so
															; set the address to the bottom ($0000H)
				JP			RTCLOOP				; Display the new memory location

;------------------------------------------------------------------------------
; MEMX - GOTO a memory address
;------------------------------------------------------------------------------
MEMXGO2:
				LD			A,CR						; Reset cursor on line to overwrite the 'MEMX:' prompt
				CALL		TXA
				LD			HL,MEMXEAI			; Point to address entry text
				CALL		MPRINT					; Print it
				CALL		GETHL					; Get 4 hex chars from console and pop into HL
				CALL		CRLF						; New line
				JP			PRMEMX				; Display memory location in HL
				
;------------------------------------------------------------------------------
; MEMX - POKE a value into RAM
;------------------------------------------------------------------------------
MEMXPK:
				PUSH		HL
				LD			A,CR						; Reset cursor on line to overwrite the 'MEMX:' prompt
				CALL		TXA
				LD			HL,MEMXEAI			; Display address entry instruction
				CALL		MPRINT					; Print it
				CALL		GETHL					; Get 4 hex chars from console and pop into HL
				PUSH		HL						; Save POKE memory location
				LD			HL,MEMXEDI			; Display value entry instruction
				CALL		MPRINT					; Print it
				CALL		GET2A					; Get two hex chars and convert to byte in A
				POP			HL						; Restore HL (POKE memory address)
				LD			(HL),A					; Set address (HL) to A
				CALL		CRLF
				POP			HL						; Restore current memory page address
				JP			PRMEMX				; Display current memory location in HL

;------------------------------------------------------------------------------
; Displays 256 bytes of memory starting at 16-bit pointer (HL)
;------------------------------------------------------------------------------
MEMV:
				LD			B,16				; Row register
				; Display column address headers
				LD			B,5					; Number of spaces to print to get to first column
MEMH:
				LD			A,' '				; Print that many spaces
				CALL		TXA
				DEC			B
				JP			NZ,MEMH
				PUSH		HL					; Save the start address on the stack
				; Print column address headers
				LD			B,16				; Number of headers
MEMAH:
				LD			A,L					; Load LSB of address into A
				CALL		PHEX
				LD			A,' '
				CALL		TXA
				INC			HL
				DEC			B
				JP			NZ,MEMAH		
				; Display the memory rows
				CALL		CRLF				; New line ready for data
				POP			HL					; Reset HL back to start memory address
				LD			B,16				; Reset row register
				; Print the address of this line
MEMD1:			PUSH		HL					; Store start address for this line
				PUSH		BC					; Store MSB count (B register)
				LD			A,H
				CALL		PHEX
				LD			A,L
				CALL		PHEX
				LD			A,' '
				CALL		TXA
				LD			B,16				; 16 digits to print
				; Print the 16 memory addresses for this line in hex
MEMD2:			LD			A,(HL)
				CALL		PHEX
				LD			A,' '
				CALL		TXA
				INC			HL
				DEC			B
				JP			NZ,MEMD2
				LD			A,' '				; Print a space before the ASCII
				CALL		TXA
				POP			BC					; Pop off stack to get to HL below it
				POP			HL					; Restore HL to start of address line
				PUSH		BC					; Store BC again
				LD 			B,16				; Reset row register
				; Print the ASCII version of the line
MEMASC2:		LD			A,(HL)
				CALL		PASCII
				INC			HL
				DEC			B
				JP			NZ,MEMASC2
				CALL		CRLF
				POP			BC
				DEC			B
				JP			NZ,MEMD1
				RET
				
;------------------------------------------------------------------------------
; Prints the value in the A register as an ASCII character if it is valid,
; otherwise a full-stop if not
;------------------------------------------------------------------------------
PASCII:
				CP			$20					; Is it a space?
				JP			Z,PSPC				; Yes - print a space
				CP      	'!'             	; Less than '!' ?
        		JP      	C,PDOT	        	; Yes - print a full stop
        		CP      	'~'+1           	; Greater than '~' ?
        		JP      	NC,PDOT		   		; Yes - print a full stop
        		CALL		TXA					; Is ASCII, print it
				RET

PDOT:
				LD			A,'.'
				CALL		TXA
				RET
				
PSPC:
				LD			A,' '
				CALL		TXA
				RET

;------------------------------------------------------------------------------
; Display 16-bit value in (HL) as human-readable time
; HL points to memory location of 16-bit word, which is treated as seconds count
;------------------------------------------------------------------------------
HL_TO_HRT:		; Divide HL by 3600 for hours
				; Divide remainder by 60 for minutes
				; Remainder is seconds
				
				PUSH		AF
				PUSH		BC
				PUSH		HL
				PUSH		DE

				PUSH		HL				; Load seconds count into BC
				POP			BC				;
				
				LD			DE,0E10h		; Load divisor into DE (3,600)
				CALL		Div16			; Divide BC by DE
				; BC is the number of hours, HL is the remainder
				
				CALL		DECBC			; Print content of BC
				LD			A,':'			; Print separator
				CALL		TXA
				
				PUSH		HL				; Swap the remainder into BC
				POP			BC				;
				LD			DE,03Ch			; 60
				CALL		Div16
				; BC is now number of minutes, HL is the remainder
				
				CALL		DECBC			; Print content of BC
				LD			A,':'			; Print separator
				CALL		TXA
				
				PUSH		HL				; Swap the remainder into BC
				POP			BC				;
				; BC is now number of seconds
				
				CALL		DECBC			; Print content of BC

				POP			DE
				POP			HL
				POP			BC
				POP			AF
				
				RET
				
;------------------------------------------------------------------------------
; Divide BC by DE, storing the result in BC, remainder in HL
;------------------------------------------------------------------------------				
Div16:
				ld 			hl,0
				ld 			a,b
				ld 			b,8
Div16_Loop1:
				rla
				adc 		hl,hl
				sbc 		hl,de
				jr 			nc,Div16_NoAdd1
				add 		hl,de
Div16_NoAdd1:
				djnz 		Div16_Loop1
				rla
				cpl
				ld 			b,a
				ld 			a,c
				ld 			c,b
				ld 			b,8
Div16_Loop2:
				rla
				adc 		hl,hl
				sbc 		hl,de
				jr 			nc,Div16_NoAdd2
				add 		hl,de
Div16_NoAdd2:
				djnz 		Div16_Loop2
				rla
				cpl
				ld 			b,c
				ld 			c,a
				ret

;------------------------------------------------------------------------------
; Display 8-bit value in C as 2-digit decimal ASCII
;------------------------------------------------------------------------------
DECBC:
				PUSH		AF
				PUSH		BC
				PUSH		HL
				PUSH		DE
				
				LD			A,0				; Set LZ_FLAG to zero so leading zeros
				LD			(LZ_FLAG),A		; are not printed out
				
				PUSH		BC				; Swap BC into HL
				POP			HL
				
				; Display leading zero if L is less than 10
				LD			A,L
				CP			10
				JP			NC,DBC0
				LD			A,'0'
				CALL		TXA
				
DBC0:			LD			BC,-100
				CALL		DBC1
				LD			C,-10
				CALL		DBC1
				JP			DBC3
				
DBC1:			LD			A,'0'-1
DBC2:			INC			A
				ADD			HL,BC
				JR			C,DBC2
				SBC			HL,BC
				CP			'0'				; Check for a zero
				JP			NZ,DBCX			; Display if it's not a zero
				LD			A,(LZ_FLAG)		; Is a zero, so check LZ_FLAG to see if we
				CP			0FFh			; are not in leading zeros any more
				RET			NZ				; We are, so don't print the zero
				LD			A,'0'			; We're not, so print the zero
				CALL		TXA
				RET
				
DBCX:			CALL 		TXA				; Print the number
				LD			A,0FFh			; Set the flag value
				LD			(LZ_FLAG),A		; And set the flag so further non-leading
				RET							; zeros can be printed
				
DBC3:			LD			C,-1
				LD			A,'0'-1
DBC4:			INC			A
				ADD			HL,BC
				JR			C,DBC4
				SBC			HL,BC
				CALL 		TXA
				
				POP			DE
				POP			HL
				POP			BC
				POP			AF
				
				RET 
				
;------------------------------------------------------------------------------
; Display 16-bit value in HL as decimal ASCII without leading zeros
;------------------------------------------------------------------------------
DECHL:
				PUSH		AF
				PUSH		BC
				PUSH		HL
				PUSH		DE
				
				LD			A,0				; Set LZ_FLAG to zero so leading zeros
				LD			(LZ_FLAG),A		; are not printed out
				
				LD			BC,-10000
				CALL		NUM1
				LD			BC,-1000
				CALL		NUM1
				LD			BC,-100
				CALL		NUM1
				LD			C,-10
				CALL		NUM1
				JP			NUM3
				
NUM1:			LD			A,'0'-1
NUM2:			INC			A
				ADD			HL,BC
				JR			C,NUM2
				SBC			HL,BC
				CP			'0'				; Check for a zero
				JP			NZ,NUMX			; Display if it's not a zero
				LD			A,(LZ_FLAG)		; Is a zero, so check LZ_FLAG to see if we
				CP			0FFh			; are not in leading zeros any more
				RET			NZ				; We are, so don't print the zero
				LD			A,'0'			; We're not, so print the zero
				CALL		TXA
				RET
				
NUMX:			CALL 		TXA				; Print the number
				LD			A,0FFh			; Set the flag value
				LD			(LZ_FLAG),A		; And set the flag so further non-leading
				RET							; zeros can be printed
				
NUM3:			LD			C,-1
				LD			A,'0'-1
NUM4:			INC			A
				ADD			HL,BC
				JR			C,NUM4
				SBC			HL,BC
				CALL 		TXA
				
				POP			DE
				POP			HL
				POP			BC
				POP			AF
				
				RET 

;------------------------------------------------------------------------------
; Get four ASCII hex digits from (HL), convert to a 16-bit word in DE
;------------------------------------------------------------------------------
GETD:
				CALL		GETHX
				LD			D,A
				CALL		GETHX
				LD			E,A
				RET
				
;------------------------------------------------------------------------------
; Get 2 ASCII hex digits from (HL), convert to an 8-bit byte in E
;------------------------------------------------------------------------------
GETBYTE:
				CALL		GETHX
				LD			E,A
				RET

;------------------------------------------------------------------------------
; Get 2 ASCII hex digits pointed to by (HL), convert to a byte in A
;------------------------------------------------------------------------------
GETHX:
				LD			B,0
				CALL		GETH1
				RLCA
				RLCA
				RLCA
				RLCA
				LD			B,A
GETH1:
				LD			A,(HL)
				CP			' '						; If first char is a space, ignore it
				JP			NZ,GETH11		; Not a space, carry on
				INC			HL					; Is a space, skip past it
				LD			A,(HL)
GETH11:											; Convert the value in A to an ASCII HEX char
				AND			070h
				CP			040h
				JP			C,GETH2
				LD			A,(HL)
				AND			00Fh
				ADD			A,9
				JP			GETH3
GETH2:
				LD			A,(HL)
				AND			00Fh
GETH3:
				INC			HL
				OR 			B
				RET
				
;------------------------------------------------------------------------------
; Print content of A as an ASCII hex number
;------------------------------------------------------------------------------
PHEX:
				LD			(CHRBUF),A			; Preserve content of A register
				AND			0F0h
				RRCA
				RRCA
				RRCA
				RRCA
				CALL		PHEX1
PHEX1:
				AND			00Fh
				CP			00Ah
				JP			C,PHEX2
				SUB			009h
				OR			040h
				JP			PHEX3
PHEX2:
				OR			030h
PHEX3:
				CALL		TXA
				LD			A,(CHRBUF)			; Restore content of A register
				RET

;------------------------------------------------------------------------------
; Load an Intel Hex stream pasted into the console. Terminated by record type 1.
;------------------------------------------------------------------------------
RHEX:
				POP			HL					; Discard command address
				LD			HL,RHXMSG			; Load the instruction string
				CALL		MPRINT				; Print it
				CALL		CRLF				; Newline ready for progress output
RHEXA:			; Initial loop takes first few bytes of input line and stores the
				; start address so it can be printed out at the end
				CALL		RXA					; Get next character
				CP			ESC
				JP			Z,COMMAND			; ESC cancels operation
				CP			':'					; Start of record?
				JP			NZ,RHEXA			; If not, wait until it is
				CALL		INHEX				; Record length
				LD			D,A					; Length counter
				CALL		INHEX				; Get target address high
				LD			H,A					; Load it into H register
				CALL		INHEX				; Get target address low
				LD			L,A					; Load it into L register
				PUSH		HL					; Store start address of code
				CALL		INHEX				; Get record type
				CP			1					; End of record?
				JP			Z,ENDRHEX
				JP			RHEXL
RHEXI:			; This is the main loop - essentially a duplicate of RHEXA above,
				; but this one doesn't overwrite the memory address on the stack
				; and prevents the last memory address being displayed at the end
				; instead of the first memory address
				CALL		RXA					; Get next character
				CP			ESC
				JP			Z,COMMAND			; ESC cancels operation
				CP			':'					; Start of record?
				JP			NZ,RHEXI			; If not, wait until it is
				CALL		INHEX				; Record length
				LD			D,A					; Length counter
				CALL		INHEX				; Get target address high
				LD			H,A					; Load it into H register
				CALL		INHEX				; Get target address low
				LD			L,A					; Load it into L register
				CALL		INHEX				; Get record type
				CP			1					; End of record?
				JP			Z,ENDRHEX
				CALL		CRLF				; Newline for next line of data
				
RHEXL:			; This loop loads in the data in the current line, before returning
				; to RHEXI above to input the next line if there is one
				CALL		INHEX
				LD			(HL),A				; Load the value into the current memory address
				LD			A,'.'				; Display a . for each byte entered
				CALL		TXA					;
				INC			HL					; Increment to next memory address
				DEC			D					; Decrement record length counter
				JP			NZ,RHEXL
				JP			RHEXI				; Continue reading records

ENDRHEX:		; Reached the end of the pasted code - nothing is done with the
				; checksum currently, but a final success message is printed out
				; displaying the start address of the loaded code
				CALL		INHEX					; Get checksum
				CALL		CRLF
				LD			HL,RHXFMSG				; Load completed message
				CALL		MPRINT					; Print it
				POP			HL						; Print the start address it was loaded at
				LD			A,H
				CALL		PHEX
				LD			A,L
				CALL		PHEX
				LD			A,'H'					; with an 'H' on the end as it's hexadecimal
				CALL		TXA
				JP			COMMAND					; Return to command prompt
INHEX:
				LD			B,0						; Input an ASCII hex digit to A from console
				CALL		INH1
				RLCA
				RLCA
				RLCA
				RLCA
				LD			B,A
INH1:
				CALL		RXA
				LD			C,A						; Copy A into C as the next instructions change A
				AND			070h
				CP			040h
				JP			C,INH2
				LD			A,C						; Restore A to original value
				AND			00Fh
				ADD			A,9
				JP			INH3
INH2:
				LD			A,C						; Restore A to original value
				AND			00Fh
INH3:
				OR			B
				RET

;------------------------------------------------------------------------------
; Basic IO commands - CPOUT outputs nnH (0-255) to port ppH (O pp,nn)
;					- CPIN prints the value at port ppH (IN pp)
;------------------------------------------------------------------------------
CPOUT:
				POP			HL
				CALL    	CSETIO				; Set up port number
				PUSH		AF					; Push the data to send onto the stack
				LD			A,(IO_ADDR)			; Get port address into A
				LD			C,A					; Load the IO port into C
				POP			AF					; Pop the data to send off the stack
				OUT			(C),A				; Output data to port specified in C and return
				JP			SHORTPROMPT
				
CSETIO:
				CALL    	GETBYTE        		; Get 2 hex digits from 0-FF into E
				LD			A,E					; Load port number into A
				LD			(IO_ADDR),A			; Load IO port into IO_ADDR location
				LD			A,(HL)				; Make sure ',' follows
				CP			','					; Check next char is a comma
				JP			NZ,SHOWSYERR		; No - Error
				INC			HL
				CALL    	GETBYTE	          	; Get 2 hex digits from 0 to FF
				LD      	A,E					; Get LSB of number
				RET

;------------------------------------------------------------------------------
CPIN:
				POP			HL
				CALL    	CSETIN           	; Set up port number
				LD			A,(IO_ADDR)			; Get port address into A
				LD			C,A					; Load the IO port into C
				IN			A,(C)				; Output data to port specified in C and return
				LD			C,A					; Copy the data to C
				LD			HL,CINMSG			; Load the result string
				CALL		MPRINT				; Print it
				LD			A,C					; Copy the port value into A
				CALL		PHEX				; Print it as a hex value
				JP			COMMAND				; returning to input
				
CSETIN: 
				CALL    	GETBYTE        		; Get 2 hex digits from 0-FF into E
				LD			A,E					; Load port number into A
				LD			(IO_ADDR),A			; Load IO port into IO_ADDR location
				RET
				
;------------------------------------------------------------------------------
SHOWIOERR:
				LD			HL,ERMSG			; Load error message
				CALL		MPRINT				; Print the message
				JP			COMMAND				; Return to command line

;------------------------------------------------------------------------------
SHOWSYERR:
				LD			HL,SYERR			; Load error message
				CALL		MPRINT				; Print the message
				JP			COMMAND				; Return to command line

;------------------------------------------------------------------------------
; POKE command - write an 8-bit value to memory address nnnn - POKE nnnnH,ddH
;------------------------------------------------------------------------------
CPOKE:
				POP			HL
				CALL    	GETD        		; Get target address into DE
				PUSH		DE					; Save it on the stack
				LD			A,(HL)          	; Make sure ',' follows
				CP			','					; Check next char is a comma
				JP			NZ,SHOWSYERR		; No - Error
				INC			HL					; Next char should be data byte
				CALL    	GETBYTE	          	; Get 2 hex digits from 0 to FF
				LD      	A,E           		; Get data byte into A
				POP			HL					; Pop target address off stack into HL
				LD			(HL),A				; Write data into target memory location
				JP			SHORTPROMPT

;------------------------------------------------------------------------------
; PEEK command - read an 8-bit value at memory address nnnn - PEEK nnnnH
;------------------------------------------------------------------------------
CPEEK:
				POP			HL
				CALL		GETD				; Get target address
				LD			HL,CINMSG			
				CALL		MPRINT
				LD			A,(DE)				; Load byte into A
				CALL		PHEX				; Print it as hex
				LD			A,'h'
				CALL		TXA
				JP			COMMAND				; to main loop

;------------------------------------------------------------------------------
; TIME command - read an 16-bit value at memory address CLKMEM as seconds and
; display as a human-readable time in the CLI
;------------------------------------------------------------------------------
CTIME:
				LD			HL,(CLKMEM)			; Load seconds-since-boot
				CALL		HL_TO_HRT			; Display HL as time
				LD			HL,SECSMSG
				CALL		MPRINT

				JP			COMMAND

;------------------------------------------------------------------------------
; Show HELP text - list of commands
; Registers used : HL,A
;------------------------------------------------------------------------------
HELP:
				POP			HL					; Dump HL off the stack
				LD			HL,CMDLIST			; Load the help command list string
				CALL		MPRINT				; You know the rest
				JP			COMMAND

;------------------------------------------------------------------------------
; CALL address specified by user in CALL $nnnn command
; Registers used: HL,DE
;------------------------------------------------------------------------------
CCALL:
				POP			HL
				CALL		GETD				; Get a double ASCII word (16-bit)
				EX			DE, HL
				JP			(HL)				; CALL the code at that address

;------------------------------------------------------------------------------				 
; CLRMEM nnnn,dddd - Set ddddH bytes to zero from address nnnnH
; Registers used: AF,BC,DE,HL
;------------------------------------------------------------------------------
CLEARM:
				POP			HL
				CALL		GETD				; Get address to start from
				PUSH		DE					; Save it on the stack
				LD			A,(HL)				; Make sure ',' follows
				CP			','					; Check next char is a comma
				JP			NZ,SHOWSYERR		; No - Error
				INC			HL					; Next char
				CALL		GETD				; Get length to clear
				PUSH		DE					; Swap area size into BC
				POP			BC
				POP			HL					; Load start address into HL		
				LD			A,0					; Set value to write
				CALL		MFILL
				JP			SHORTPROMPT			; Return to main loop, minus CRLF
				
MFILL:
				LD			(HL),A				; Fill first byte with value
				LD			D,H					; Destination ptr = source ptr + 1
				LD			E,L
				INC			DE
				DEC			BC					; Eliminate first byte from count
				LD			A,B					; Are there more bytes to fill?
				OR			C
				RET			Z					; No, return - size was 1
				LDIR							; Yes, use block move to fill rest
												; by moving value ahead 1 byte
				RET

;------------------------------------------------------------------------------				 
; BASIC 'C/OLD' - Transfer to the BASIC interpreter after working out if a cold or 
; warm start is needed, or a cold start is forced with optional C or COLD parameter
;------------------------------------------------------------------------------
CBASIC:
				LD			A,(basicStarted)		; Check the BASIC STARTED flag
				CP			'B'             			; to see if this is power-up
				JP			NZ,COLDSTART    	; If not BASIC started then always do cold start
				POP			HL						; Get pointer to input string
				INC			HL						; Skip the space
				LD			A,(HL)          			; See if keyword follows
				AND     	01011111B    	   	; Force upper case
				CP			'C'						; Check next char is a C
				JP			NZ,BASWRM  		; Otherwise go to warm start
				JP			COLDSTART			; Cold start selected
				
;------------------------------------------------------------------------------
; Get a character from the console, must be $20-$7F to be valid (no control characters)
; <Ctrl-c> and <SPACE> breaks with the Zero Flag set
;------------------------------------------------------------------------------	
MGETCHR:
				CALL 		RDCHR					; RX a Character
				CP			$03						; <ctrl-c> User break?
				RET  		Z			
				CP			$20						; <space> or better?
				JR			C,MGETCHR			; Do it again until we get something usable
				RET

;------------------------------------------------------------------------------
; Gets two ASCII characters from the console (assuming them to be HEX 0-9 A-F)
; Moves them into B and C, converts them into a byte value in A
;------------------------------------------------------------------------------
GET2A:
				CALL 		MGETCHR					; Get us a valid character to work with
				CALL		TXA
				LD			B,A						; Load it in B
				CALL 		MGETCHR					; Get us another character
				CALL		TXA
				LD			C,A						; load it in C
				CALL 		BCTOA					; Convert ASCII to byte
				RET
				
;------------------------------------------------------------------------------
; Gets two ASCII characters from the console (assuming them to be HEX 0-9 A-F)
; Moves them into B and C, converts them into a byte value in A and updates a
; Checksum value in E
;------------------------------------------------------------------------------
GET2:
				CALL 		MGETCHR					; Get us a valid character to work with
				LD			B,A						; Load it in B
				CALL 		MGETCHR					; Get us another character
				LD			C,A						; load it in C
				CALL 		BCTOA					; Convert ASCII to byte
				LD			C,A						; Build the checksum
				LD			A,E
				SUB  		C						; The checksum should always equal zero when checked
				LD			E,A						; Save the checksum back where it came from
				LD			A,C						; Retrieve the byte and go back
				RET
				
;------------------------------------------------------------------------------
; Gets four Hex characters from the console, converts them to values in HL
;------------------------------------------------------------------------------
GETHL:
				LD			HL,$0000				; Gets xxxx but sets Carry Flag on any Terminator
				CALL 		ECHO					; RX a Character
				CP			CR						; <CR>?
				JR			NZ,GETX2				; other key		
SETCY:
				SCF									; Set Carry Flag
				RET             					; and Return to main program		
				
;------------------------------------------------------------------------------
; This routine converts last four hex characters (0-9 A-F) user types into a value in HL
; Rotates the old out and replaces with the new until the user hits a terminating character
;------------------------------------------------------------------------------
GETX:
				LD			HL,$0000			; CLEAR HL
GETX1:
				CALL 		ECHO				; RX a character from the console
				CP			CR					; <CR>
				RET  		Z					; quit
				CP			$2C					; <,> can be used to safely quit for multiple entries
				RET  		Z					; (Like filling both DE and HL from the user)
GETX2:
				CP			$03					; Likewise, a <ctrl-C> will terminate clean, too, but
				JR			Z,SETCY				; It also sets the Carry Flag for testing later.
				ADD  		HL,HL				; Otherwise, rotate the previous low nibble to high
				ADD  		HL,HL				; rather slowly
				ADD  		HL,HL				; until we get to the top
				ADD  		HL,HL				; and then we can continue on.
				SUB  		$30					; Convert ASCII to byte	value
				CP			$0A					; Are we in the 0-9 range?
				JR			C,GETX3				; Then we just need to sub $30, but if it is A-F
				SUB  		$07					; We need to take off 7 more to get the value down to
GETX3:
				AND  		$0F					; to the right hex value
				ADD  		A,L					; Add the high nibble to the low
				LD			L,A					; Move the byte back to A
				JR			GETX1				; and go back for next character until he terminates

;------------------------------------------------------------------------------
; Convert ASCII characters in B C registers to a byte value in A
;------------------------------------------------------------------------------
BCTOA:
		LD   A,B	; Move the hi order byte to A
		SUB  $30	; Take it down from Ascii
		CP   $0A	; Are we in the 0-9 range here?
		JR   C,BCTOA1	; If so, get the next nybble
		SUB  $07	; But if A-F, take it down some more
BCTOA1:
		RLCA		; Rotate the nybble from low to high
		RLCA		; One bit at a time
		RLCA		; Until we
		RLCA		; Get there with it
		LD   B,A	; Save the converted high nybble
		LD   A,C	; Now get the low order byte
		SUB  $30	; Convert it down from Ascii
		CP   $0A	; 0-9 at this point?
		JR   C,BCTOA2	; Good enough then, but
		SUB  $07	; Take off 7 more if it's A-F
BCTOA2:
		ADD  A,B	; Add in the high order nybble
		RET

;------------------------------------------------------------------------------
; HLDivC - Divide 16-bit HL by 8-bit C and put remainder in A
; Inputs:
;     HL - numerator
;     C  - denominator
; Outputs:
;     A  - remainder
;     B  - 0
;     C  - unchanged
;     DE - unchanged
;     HL - quotient
;------------------------------------------------------------------------------
HLDivC:
				LD			B,16
				XOR			A
				ADD			HL,HL
				RLA
				CP			C
				JR			C,$+4
				INC			L
				SUB			C
				DJNZ		$-7
				RET

;------------------------------------------------------------------------------
; Get a character and echo it back to the user
;------------------------------------------------------------------------------
ECHO:
				CALL		RDCHR
				CALL		WRCHR
				RET

;------------------------------------------------------------------------------
; MGOTO command
;------------------------------------------------------------------------------
MGOTO:
				CALL 		GETHL			; ENTRY POINT FOR <G>oto addr. Get XXXX from user.
				RET  		C				; Return if invalid       	
				PUSH 		HL
				RET							; Jump to HL address value

;------------------------------------------------------------------------------
; Start BASIC command
;------------------------------------------------------------------------------
BASIC:
				LD 			HL,BASICTXT
				CALL 		MPRINT
				CALL 		MGETCHR
				RET 		Z				; Cancel if CTRL-C
				AND  		$5F 			; uppercase
				CP 			'C'
				JP  		Z,BASCLD
				CP 			'W'
				JP  		Z,BASWRM
				RET

;------------------------------------------------------------------------------
; CP/M load command
;------------------------------------------------------------------------------
CPMLOAD:
				LD 			HL,CPMTXT
				CALL 		MPRINT
				CALL 		MGETCHR
				RET 		Z				; Cancel if CTRL-C
				AND  		$5F 			; uppercase
				CP 			'Y'
				JP  		Z,CPMLOAD2
				RET

CPMLOAD2:
				CALL		INIT_CTC		; Shut down all CTC interrupts
				LD 			HL,CPMTXT2
				CALL 		MPRINT

				CALL		cfWait
				LD 			A,CF_8BIT		; Set IDE to be 8bit
				OUT			(CF_FEATURES),A
				LD			A,CF_SET_FEAT
				OUT			(CF_COMMAND),A


				CALL		cfWait
				LD 			A,CF_NOCACHE	; No write cache
				OUT			(CF_FEATURES),A
				LD			A,CF_SET_FEAT
				OUT			(CF_COMMAND),A

				LD			B,numSecs

				LD			A,0
				LD			(secNo),A
				LD			HL,loadAddr
				LD			(dmaAddr),HL
processSectors:
				CALL		cfWait

				LD			A,(secNo)
				OUT 		(CF_LBA0),A
				LD			A,0
				OUT 		(CF_LBA1),A
				OUT 		(CF_LBA2),A
				LD			A,0E0H
				OUT 		(CF_LBA3),A
				LD 			A,1
				OUT 		(CF_SECCOUNT),A

				CALL		read

				LD			DE,0200H
				LD			HL,(dmaAddr)
				ADD			HL,DE
				LD			(dmaAddr),HL
				LD			A,(secNo)
				INC			A
				LD			(secNo),A

				DJNZ		processSectors

; Start CP/M using entry at top of BIOS
; The current active console stream ID is pushed onto the stack
; to allow the CBIOS to pick it up
; 0 = SIO A, 1 = SIO B
				LD			A,(primaryIO)
				PUSH		AF
				LD			HL,($FFFE)
				JP			(HL)

;------------------------------------------------------------------------------
; Read physical sector from host
;------------------------------------------------------------------------------
read:
		PUSH 	AF
		PUSH 	BC
		PUSH 	HL

		CALL 	cfWait

		LD 	A,CF_READ_SEC
		OUT 	(CF_COMMAND),A

		CALL 	cfWait

		LD 	c,4
		LD 	HL,(dmaAddr)
rd4secs:
		LD 	b,128
rdByte:
		nop
		nop
		in 	A,(CF_DATA)
		LD 	(HL),A
		iNC 	HL
		dec 	b
		JR 	NZ, rdByte
		dec 	c
		JR 	NZ,rd4secs

		POP 	HL
		POP 	BC
		POP 	AF

		RET


; Wait for disk to be ready (busy=0,ready=1)
cfWait:
		PUSH 	AF
cfWait1:
		in 	A,(CF_STATUS)
		AND 	080H
		cp 	080H
		JR	Z,cfWait1
		POP 	AF
		RET

;------------------------------------------------------------------------------
; COMMAND LIST - Direct Mode commands.  Position in table relates to 
; routine called in Keyword Address Table below
;------------------------------------------------------------------------------
CWORDS:  
			.BYTE	'B'+80H,"ASIC"
        	.BYTE	'U'+80H,"SER"
        	.BYTE	'D'+80H,"UMP"
			.BYTE	'R'+80H,"HEX"
        	.BYTE	'V'+80H,"ERSION"
        	.BYTE	'H'+80H,"ELP"
			.BYTE	'C'+80H,"ALL"
        	.BYTE	'O'+80H,"UT"
			.BYTE	'I'+80H,"N"
			.BYTE	'P'+80H,"OKE"
			.BYTE	'P'+80H,"EEK"
			.BYTE	'C'+80H,"LRMEM"
			.BYTE	'M'+80H,"EMX"
			.BYTE	'R'+80H,"ESET"
			.BYTE	'C'+80H,"PM"
			.BYTE	'S'+80H,"ETIO"
			.BYTE	'G'+80H,"ETIO"
			.BYTE	'T'+80H,"IME"
			.BYTE	'S'+80H,"CAN"
			.BYTE	'S'+80H,"UPPORT"
			.BYTE	'X'+80H,"EST"

;------------------------------------------------------------------------------
; KEYWORD ADDRESS TABLE - LINKS KEYWORDS TO SUBROUTINES
;------------------------------------------------------------------------------
CWORDTB: 
			.WORD	CBASIC			; BASIC
        	.WORD	USRCODE			; USER
        	.WORD	MEMD			; DUMP
			.WORD	RHEX			; RHEX
			.WORD	VER				; VERSION
        	.WORD	HELP			; HELP
			.WORD	CCALL			; CALL
        	.WORD	CPOUT			; OUT
			.WORD	CPIN			; IN
			.WORD	CPOKE			; POKE
			.WORD	CPEEK			; PEEK
			.WORD	CLEARM			; CLEARMEM
			.WORD	MEMX			; MEMX
			.WORD	RST00			; RESET
			.WORD	CPMLOAD			; CPM
			.WORD	CPSGOUT			; PSG IO TESTING
			.WORD	CPSGIN			; PSG IO TESTING
			.WORD	CTIME			; TIME SINCE BOOT
			.WORD	I2C_SCAN		; I²C BUS SCANNER
			.WORD	SM_TX			; TRANSMIT TO SUPPORT MODULE TESTER
			.WORD	VER				; FIX FOR LAST ENTRY NOT WORKING

;------------------------------------------------------------------------------
; RESERVED WORD TOKEN VALUES
; Don't actually think these are needed - it's likely these are the tokens
; that BASIC uses to replace commands in the stored BASIC programs
;------------------------------------------------------------------------------
DBASIC  	.EQU    	080H        ; BASIC
DUSER   	.EQU    	081H        ; USRCODE
DDUMP		.EQU		082H        ; DUMP
DRHEX		.EQU		083H		; RHEX
DVER		.EQU		084H		; VERSION
DHELP   	.EQU    	085H        ; HELP
DCALL		.EQU		086H		; CALL
DOUT   		.EQU    	087H        ; OUT
DIN			.EQU		088H		; IN
DPOKE		.EQU		089H		; POKE
DPEEK		.EQU		08AH		; PEEK
DCLEARM		.EQU		08BH		; CLRMEM
DMEMX		.EQU		08CH		; MEMX
DRESET		.EQU		08DH		; RESET
DCPM		.EQU		08EH		; CPM
DCPSGOUT	.EQU		08FH		; PSG IO WRITE
DCPSGIN		.EQU		090H		; PSG IO READ
DTIME		.EQU		091H		; TIME SINCE BOOT
DSCAN		.EQU		092H		; I²C BUS SCANNER
DSMSEL		.EQU		093H		; SUPPORT MODULE TESTER
DXEST		.EQU		094H		; FIX FOR LAST ENTRY NOT WORKING

;------------------------------------------------------------------------------
; STRING VALUES
;------------------------------------------------------------------------------
SIGNON1       	
		.BYTE   MCLS
		.BYTE	"Z80 Minicom II 64K Computer "
		.BYTE	"@ 3.6864 MHz"
		.BYTE	CR,LF
		.BYTE	"  Boot ROM v1.3",CR,LF
		.BYTE	"    Copyright ",40,"C",41," 2017 "
		.BYTE  	"Jonathan Nock",CR,LF
		.BYTE	CR,LF,EOS
		
BASICTXT
		.BYTE	CR,LF
		.TEXT	"Cold or Warm ?"
		.BYTE	CR,LF,EOS

CKSUMERR
		.BYTE	"Checksum error"
		.BYTE	CR,LF,EOS

MINITTXTA
		.BYTE	MCLS
		.TEXT	"Z80 Minicom II 64K Computer "
		.BYTE	CR,LF
		.TEXT	"PORT A: Press [SPACE] to activate console"
		.BYTE	CR,LF,EOS

MINITTXTB
		.BYTE	MCLS
		.TEXT	"Z80 Minicom II 64K Computer "
		.BYTE	CR,LF
		.TEXT	"PORT B: Press [SPACE] to activate console"
		.BYTE	CR,LF,EOS
		
CPROMPT
		.BYTE	CR,LF
		
CSHTPRT
		.BYTE	"OK",CR,LF,EOS

CINMSG
		.BYTE	"VALUE: ",EOS
		
CPMTXT:
		.BYTE	CR,LF
		.TEXT	"Boot CP/M?"
		.BYTE	EOS

CPMTXT2:
		.BYTE	CR,LF
		.TEXT	"CTC interrupts reset..."
		.BYTE	CR,LF
		.TEXT	"Loading CP/M..."
		.BYTE	CR,LF,EOS
		
ERMSG
		.BYTE	"Unrecognised command",EOS
		
INTERR
		.BYTE	"Unhandled Interrupt Error",EOS

IOERR
		.BYTE	"IO Error",EOS

SYERR
		.BYTE	"Syntax Error",EOS

DMMSG
		.BYTE	"Direct Mode Interpreter - "
		.BYTE	"Type 'HELP' for commands"
		.BYTE	EOS

RHXMSG
		.BYTE	"Paste your Intel Hex code "
		.BYTE	"now or press ESC to "
		.BYTE	"cancel..."
		.BYTE	EOS
		
SECSMSG
		.BYTE	" since last boot.",EOS
		
BTSTMSG
		.BYTE	"This is a message from "
		.BYTE	"the Z80!",EOS

RHXFMSG
		.BYTE	"Data loaded at address ",EOS

MEMXMNU
		.BYTE	"(,) Prev page "
		.BYTE	"(.) Next page "
		.BYTE	"(G) Go to addr "
		.BYTE	"(P) Poke "
		.BYTE	"(X) Exit editor",CR,LF
		.BYTE	"MEMX: ",EOS
				
MEMXEAI
		.BYTE	"Enter address (xxxx):",EOS

MEMXEDI
		.BYTE	"Enter data to poke (xx):",EOS
		
AYPREAD
		.BYTE	"PSG IO Port Value: ",EOS
		
AYPWRITE
		.BYTE	"PSG IO Port Write: ",EOS

CMDLIST
		.BYTE	"Direct Mode command list:",CR,LF
		.BYTE	"-------------------------",CR,LF
		.BYTE	"BASIC (C/OLD)  - "
		.BYTE	"Go to BASIC interpreter - "
		.BYTE	"force cold start with C "
		.BYTE	"or COLD",CR,LF
		.BYTE	"CPM            - "
		.BYTE	"Boot CP/M (load $D000-$FFFF "
		.BYTE	"from disk)",CR,LF
		.BYTE	"RESET          - "
		.BYTE	"Reset the computer",CR,LF
		.BYTE	"USER           - "
		.BYTE	"Call user assembly routine",CR,LF
		.BYTE	"DUMP $nnnn     - "
		.BYTE	"Dump a 256-byte segment of "
		.BYTE	"memory from location $nnnn",CR,LF
		.BYTE	"MEMX           - "
		.BYTE	"Opens the memory editor tool",CR,LF
		.BYTE	"RHEX           - "
		.BYTE	"Listen for Intel Hex stream "
		.BYTE	"and load into memory",CR,LF
		.BYTE	"VERSION        - "
		.BYTE	"Show the system version "
		.BYTE	"numbers",CR,LF
		.BYTE	"OUT $pp,$nn    - "
		.BYTE	"Write the hex $nn to port "
		.BYTE	"$pp",CR,LF
		.BYTE	"IN $pp         - "
		.BYTE	"Print the value at port "
		.BYTE	"$pp",CR,LF
		.BYTE	"CALL $nnnn     - "
		.BYTE	"Call a subroutine at address"
		.BYTE	" $nnnn",CR,LF
		.BYTE	"PEEK $nnnn     - "
		.BYTE	"Read a value from address $nnnn"
		.BYTE	CR,LF
		.BYTE	"POKE $nnnn,$dd - "
		.BYTE	"Write value $dd to address "
		.BYTE	"$nnnn",CR,LF
		.BYTE	"CLRMEM $nnnn,$dddd - "
		.BYTE	"Set area size $dddd to 0 from "
		.BYTE	"memory address $nnnn",CR,LF
		.BYTE	"SETIO $nn      - "
		.BYTE	"Write hex $nn to PSG IO port"
		.BYTE	CR,LF
		.BYTE	"GETIO          - "
		.BYTE	"Read a byte from IO port",CR,LF
		.BYTE	"TIME           - "
		.BYTE	"Show time since boot"
		.BYTE	CR,LF
		.BYTE	"SCAN           - "
		.BYTE	"Scan the IIC bus for devices"
		.BYTE	CR,LF
		.BYTE	"SUPPORT        - "
		.BYTE   "Transmit single character "
		.BYTE	"to the Support Module"
		.BYTE	CR,LF
		.BYTE	"HELP           - "
		.BYTE	"Show this help text",EOS

;------------------------------------------------------------------------------
#INCLUDE	"i2c_lib.asm"
#INCLUDE	"basic.asm"

FINIS		.END