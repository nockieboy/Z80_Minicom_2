; I²C LIBRARY for Z80 Minicom II
; For PIO-implemented I²C bus (bit-banging)
;
; nockieboy@gmail.com
;
; The following high-level routines are standalone - they include I²C bus management:
;
; I2C_GETHL8 - Read a word of data into HL via I²C using 8-bit addressing
; I2C_GETHL16- Read a word of data into HL via I²C using 16-bit addressing
; I2C_RD_D8  - Read block of data from device via I²C that uses 8-bit addressing
; I2C_RD_D16 - Read block of data from device via I²C that uses 16-bit addressing
; I2C_WR_D8  - Transmit block of data to device via I²C that uses 8-bit addressing
; I2C_WR_D16 - Transmit block of data to device via I²C that uses 16-bit addressing
;
; Low-level functions (further functions are internal to these):
;
; I2C_RST    - I²C bus reset
; I2C_START  - Initiates I²C bus transfer
; I2C_STOP   - Stops I²C bus transfer during WRITE operation
; I2C_STOP_RD- Stops I²C bus transfer during READ operation
; I2C_TX     - Transmit 1 byte via I²C
; I2C_RX     - Receive 1 byte via I²C
; I2C_ACK    - Transmit ACK

;------------------------------------------------------------------------------
; I²C BUS SCANNER
; Prints addresses for any devices on the I²C bus.
; Requires minicom.asm for support routines (char printing)
; Modifies:
;------------------------------------------------------------------------------
I2C_SCAN:
				POP			HL					; Dump CLI pointer
				LD			B,7Eh				; Iterate through addresses from 126 -> 0
				; Select device address:
I2C_SCNLP:		CALL		I2C_START
				LD 			A,B
				LD			(I2C_BUFF),A		; Buffer B
				AND			%11111110			; Clear the LSB for writes
				CALL		I2C_TX				; Write the address of the device
				JP			NC,I2C_NOPRT		; Don't print anything if no ACK (no device)
				; Device has responded
				CALL		CRLF				; Newline
				LD			HL,FNDMSG			; Load the found message
				CALL		MPRINT				; Print it
				LD			A,(I2C_BUFF)		; Copy the address into A ready to print
				CALL		PHEX				; Append the address
I2C_NOPRT:		LD			A,(I2C_BUFF)		; Restore B
				LD			B,A					; 
				DEC			B					; Skip odd addresses to halve search space
				CALL		I2C_STOP			; Free the I²C bus
				DJNZ		I2C_SCNLP			; Decrement B and loop
				JP			COMMAND				; Return to CLI

FNDMSG			.BYTE		"Found IIC device at: ",EOS
CHKMSG			.BYTE		"Checking **",EOS

;------------------------------------------------------------------------------
; I²C BUS TESTER
; Sends a START and STOP condition to the I²C bus to display a pattern trace
; on the SDA/SCL bus via oscilloscope.
; Permanent loop. Locks up computer if run until reset.
;------------------------------------------------------------------------------
I2C_TEST:
				CALL		I2C_START
				NOP
				CALL		I2C_STOP
				JP			I2C_TEST

;------------------------------------------------------------------------------
; I²C BUS RESET
; Modifies A, B, D
; Leaves SDA high and SCL high
;------------------------------------------------------------------------------
I2C_RST:
				LD			B,0Ah				; Do 10 SCL cycles while SDA is high
I_77:			CALL		SCL_CYCLE
				DJNZ		I_77
				CALL		SCL_HIGH
				RET

;------------------------------------------------------------------------------
; I²C BUS START & STOP
;------------------------------------------------------------------------------
I2C_START:		; Starts I²C bus
				CALL		SDA_LOW				; START defined by H-L on SDA with SCL H
				CALL		SCL_LOW
				RET
				
I2C_STOP:		; Stops I²C bus during WRITE
				CALL		SDA_LOW				; Make sure SDA is LOW initially.
				CALL		SCL_HIGH			; STOP is defined by the SDA
				CALL		SDA_HIGH			; transitioning to HIGH whilst SCL
				RET								; is HIGH.
				
I2C_STOP_RD:	; Stops I²C bus during READ
				CALL		SCL_LOW
				CALL		SDA_LOW
				CALL		I2C_STOP
				RET

;------------------------------------------------------------------------------
; I²C TX
; Writes a byte to the I²C bus and reads an acknowledgment.
; Byte to send in A
; Returns with carry cleared if ackn bit not found
; Modifies A,B,C,D,HL
;------------------------------------------------------------------------------
I2C_TX:
				CALL		I2C_SEND_BYTE
				BIT			1,D					; Test D register for acknowledge bit
				SCF
				RET			Z					; Return if ACK bit low with carry set
				
				; When ACK error - stop bus
				CALL		I2C_STOP
				SCF
				CCF
				RET								; Return if ACK bit high with carry cleared

;------------------------------------------------------------------------------
; I²C RX
; Returns with slave data byte in A
; Leaves SCL low and SDA high
; Modifies A,B,D
;------------------------------------------------------------------------------
I2C_RX:
				LD			B,8h
I_66:			IN			A,(PIO_B_D)
				SCF
				BIT			1,A
				JP			NZ,H_FOUND
L_FOUND:		CCF
H_FOUND:		RL			C
				CALL		SCL_CYCLE
				DJNZ		I_66
				CALL		SCL_CYCLE			; Send ACK to slave
												; Slave byte ready in C
				LD			A,C					; So switch byte to A
				RET

;------------------------------------------------------------------------------
; I²C READ 8-BIT DATA
; Reads a block of data to an I²C-bus device that uses 8-bit addressing.
; Pre:
;   B  = Amount of data to read.
;   C  = Address of device on I²C bus.
;   E  = Address to read data from on device.
;   HL = Pointer to location to store received data.
; Post:
;   Carry = set on error.
;   All other flags are undefined; A is destroyed.
;------------------------------------------------------------------------------

I2C_RD_D8:
				CALL		I2C_START	
				; Select device address:
				LD 			A,C
				AND			%11111110			; Clear the LSB for writes
				CALL		I2C_TX				; Write the address of the device
				JP			C,I2C_STOP_RD		; Stop if no ACK
				; Register address (8-bit):
				LD			A,E
				CALL		I2C_TX
				JP			C,I2C_STOP_RD		; Stop if no ACK
				; Restart I²C bus
				CALL		I2C_STOP
				CALL		I2C_START
				; Device address:
				LD			A,C
				OR			%00000001			; Set the LSB for reads
				CALL		I2C_TX
				JP			C,I2C_STOP_RD		; Stop if no ACK	
I2C_RDD8LP:		CALL		I2C_RX				; Get byte from I²C bus into A
				INC			DE
				LD			(HL),A				; Load the byte into memory
				INC			HL
				LD			A,B
				CP			1
				CALL		NZ,I2C_ACK			; Write ACKnowledge to I²C bus
				DJNZ		I2C_RDD8LP			; Loop ^
				OR			A
				JP			I2C_STOP_RD

;------------------------------------------------------------------------------
; I²C READ 16-BIT DATA
; Reads a block of data to an I²C-bus device that uses 16-bit addressing.
; Pre:
;   B   = Amount of data to read.
;   C   = Address of device on I²C bus.
;   DE  = Address to read data from on device.
;   HL  = Pointer to location to store received data.
; Post:
;   Carry = set on error.
;   All other flags are undefined; A is destroyed.
;------------------------------------------------------------------------------

I2C_RD_D16:
				CALL		I2C_START	
				; Select device address in C:
				LD 			A,C
				AND			%11111110			; Clear the LSB for writes
				CALL		I2C_TX				; Write the address of the device
				JP			C,I2C_STOP_RD		; Stop if no ACK
				; Register address (16-bit) in DE:
				LD			A,D
				CALL		I2C_TX
				RET			C					; Stop if no ACK
				LD			A,E
				CALL		I2C_TX
				JP			C,I2C_STOP_RD		; Stop if no ACK
				; Restart I²C bus
				CALL		I2C_STOP
				CALL		I2C_START
				; Device address:
				LD			A,C
				OR			%00000001			; Set the LSB for reads
				CALL		I2C_TX
				JP			C,I2C_STOP_RD		; Stop if no ACK	
I2C_RDD16LP:	CALL		I2C_RX				; Get byte from I²C bus into A
				INC			DE
				LD			(HL),A				; Load the byte into memory
				INC			HL
				LD			A,B
				CP			1
				CALL		NZ,I2C_ACK			; Write ACKnowledge to I²C bus
				DJNZ		I2C_RDD16LP			; Loop ^
				OR			A
				JP			I2C_STOP_RD

;------------------------------------------------------------------------------
; I²C READ WORD INTO HL USING 8-BIT ADDRESSING
; Reads a word of data (2 bytes) from an I²C-bus device that uses 8-bit addressing.
; Pre:
;   C   = Address of device on I²C bus.
;   E   = Address to read data from on device.
; Post:
;   Carry = set on error.
;   HL  = word of data returned from I²C bus.
;   All other flags are undefined; A is destroyed.
;------------------------------------------------------------------------------

I2C_GETHL8:
				CALL		I2C_START	
				; Select device address in C:
				LD 			A,C
				AND			%11111110			; Clear the LSB for writes
				CALL		I2C_TX				; Write the address of the device
				JP			C,I2C_STOP_RD		; Stop if no ACK
				; Register address (8-bit) in DE:
				LD			A,E
				CALL		I2C_TX
				JP			C,I2C_STOP_RD		; Stop if no ACK
				; Restart I²C bus
I2CxRT:			CALL		I2C_STOP			; 16-bit routine also runs from here
				CALL		I2C_START
				; Device address:
				LD			A,C
				OR			%00000001			; Set the LSB for reads
				CALL		I2C_TX
				JP			C,I2C_STOP_RD		; Stop if no ACK	
				; Get 2 bytes
				CALL		I2C_RX				; Get byte from I²C bus into A
				JP			C,I2C_STOP_RD		; Stop if no ACK	
				LD			L,A
				CALL		I2C_ACK
				CALL		I2C_RX
				JP			C,I2C_STOP_RD		; Stop if no ACK	
				LD			H,A
				; Free up I²C-bus and return
				OR			A
				JP			I2C_STOP_RD

;------------------------------------------------------------------------------
; I²C READ WORD INTO HL USING 16-BIT ADDRESSING
; Reads a word of data (2 bytes) from an I²C-bus device that uses 16-bit addressing.
; Pre:
;   C   = Address of device on I²C bus.
;   DE  = Address to read data from on device.
; Post:
;   Carry = set on error.
;   HL  = word of data returned from I²C bus.
;   All other flags are undefined; A is destroyed.
;------------------------------------------------------------------------------

I2C_GETHL16:
				CALL		I2C_START	
				; Select device address in C:
				LD 			A,C
				AND			%11111110			; Clear the LSB for writes
				CALL		I2C_TX				; Write the address of the device
				JP			C,I2C_STOP_RD		; Stop if no ACK
				; Register address (16-bit) in DE:
				LD			A,D
				CALL		I2C_TX
				RET			C					; Stop if no ACK
				LD			A,E
				CALL		I2C_TX
				JP			C,I2C_STOP_RD		; Stop if no ACK
				JP			I2CxRT				; Re-use the routine above

;------------------------------------------------------------------------------
; I²C WRITE 8-BIT DATA
; Writes a block of data to an I²C-bus device that uses 8-bit addressing.
; Pre:
;   B  = Amount of data to write.
;   C  = Address of device on I²C bus.
;   E  = Address to write data to on device.
;   HL = Pointer to data to write.
; Post:
;   Carry = set if transfer failed, reset if successful.
;   All other flags are undefined; A is destroyed.
;------------------------------------------------------------------------------

I2C_WR_D8:
				CALL 		I2C_START
	
				; Device address:
				LD 			A,C
				AND			%11111110			; Clear the LSB for writes.
				CALL		I2C_TX				; Write the address of the device
				RET			C					; Stop if no ACK
	
				; Register address (8-bit):
				LD			A,E
				CALL		I2C_TX
				RET			C					; Stop if no ACK
				
				; Write B bytes of data, starting at HL
WRT_LOOP:		LD			A,(HL)
				INC			HL
				CALL		I2C_TX
				RET			C					; Stop if no ACK
				INC			DE					; NOT SURE ABOUT THIS - INCREMENTS E
				DJNZ		WRT_LOOP			; Dec B and loop
				OR			A
				JP			I2C_STOP

;------------------------------------------------------------------------------
; I²C WRITE 16-BIT DATA
; Writes a block of data to an I²C-bus device that uses 16-bit addressing.
; Pre:
;   B  = Amount of data to write.
;   C  = Address of device on I²C bus.
;   E  = Address to write data to on device.
;   HL = Pointer to data to write.
; Post:
;   Carry = set if transfer failed, reset if successful.
;   All other flags are undefined; A is destroyed.
;------------------------------------------------------------------------------

I2C_WR_D16:
				CALL 		I2C_START
	
				; Device address:
				LD 			A,C
				AND			%11111110			; Clear the LSB for writes.
				CALL		I2C_TX				; Write the address of the device
				RET			C					; Stop if no ACK
	
				; Register address (16-bit):
				LD			A,D
				CALL		I2C_TX
				RET			C					; Stop if no ACK
				LD			A,E
				CALL		I2C_TX
				RET			C					; Stop if no ACK
				
				JP			WRT_LOOP			; Write the 8 bytes

;------------------------------------------------------------------------------
; I²C WRITE ACKnowledge
; Writes an acknowledgement to the currently addressed device.
; Leaves SCL low and SDA high
; Modifies A
;------------------------------------------------------------------------------
I2C_ACK:
				CALL		SDA_LOW
				CALL		SCL_HIGH
				CALL		SCL_LOW
				CALL		SDA_HIGH
				RET

;------------------------------------------------------------------------------
; I²C SCL CYCLE
; Every bit transferred via SDA must be accompanied by a L-H-L sequence on SCL.
; After SCL goes H, SDA is sampled.
; Returns D wherein bit 1 represents status of SDA while SCL was high
; Leaves SCL low
; Modifies A
;------------------------------------------------------------------------------
SCL_CYCLE:
				CALL		SCL_LOW
				CALL		SCL_HIGH
				; Look for ACK bit
				IN			A,(PIO_B_D)
				LD			D,A
				CALL		SCL_LOW
				RET

;------------------------------------------------------------------------------
; I²C SET SDA AS INPUT OR OUTPUT
; Setting direction of B1 determines whether a H or L is driver on SDA.
; Reloads PIO B mode
; Modifies A
;------------------------------------------------------------------------------
SDA_HIGH:
				LD			A,(PIO_B_MODE)
				OUT			(PIO_B_C),A
				; Change direction of SDA to input
				LD			A,(PIO_B_IO_CONF)
				SET			1,A
				OUT			(PIO_B_C),A
				LD			(PIO_B_IO_CONF),A
				RET

SDA_LOW:
				LD			A,(PIO_B_MODE)
				OUT			(PIO_B_C),A
				; Change direction of SDA to output
				LD			A,(PIO_B_IO_CONF)
				RES			1,A
				OUT			(PIO_B_C),A
				LD			(PIO_B_IO_CONF),A
				RET

;------------------------------------------------------------------------------
; I²C SET SCL AS OUTPUT OR INPUT
; Setting direction of B0 determines whether a H or L is driver on SCL.
; Reloads PIO B mode
; Modifies A
;------------------------------------------------------------------------------
SCL_HIGH:
				LD			A,(PIO_B_MODE)
				OUT			(PIO_B_C),A
				; Change direction of SCL to input
				LD			A,(PIO_B_IO_CONF)
				SET			0,A
				OUT			(PIO_B_C),A
				LD			(PIO_B_IO_CONF),A
				RET

SCL_LOW:
				LD			A,(PIO_B_MODE)
				OUT			(PIO_B_C),A
				; Change direction of SCL to output
				LD			A,(PIO_B_IO_CONF)
				RES			0,A
				OUT			(PIO_B_C),A
				LD			(PIO_B_IO_CONF),A
				RET

;------------------------------------------------------------------------------
; I²C SEND BYTE - called by I2C_TX
; Clocks out a data byte in A.
; Returns with bit 1 of D holding status of ACK bit
; Leaves SCL low and SDA high
; Modifies A, B, C, D
;------------------------------------------------------------------------------
I2C_SEND_BYTE:
				LD			B,8h				; 8 bits are to be clocked out
				LD			C,A					; Copy to C reg
I_74:			SLA			C					; Shift MSB of C into carry
				JP			C,SDA_H				; When low
SDA_L:			CALL		SDA_LOW				; Pull SDA low
				JP			I_75
SDA_H:			CALL		SDA_HIGH			; Release SDA to let it go high
I_75:			CALL		SCL_CYCLE			; Do SCL cycle (L-H-L)
				DJNZ		I_74				; Process next bit of C reg
				CALL		SDA_HIGH			; Release SDA to let it go high
				CALL		SCL_CYCLE			; Do SCL cycle (L-H-L), bit 1 of D
				RET								; holds ACK bit

.END