# Z80 Minicom Project 2017

## Building an 8-bit computer of my own design from scratch!

This is a hardware and software project.  The project is hosted in its entirety on Bitbucket, with this repo being a store primarily for main ROM code for the Z80-side of the SBC.

## Specifications:

The Z80 Minicom is a Z80-based 8-bit computer running at 7.3268 MHz.  The base specifications are liable to change as the project matures, but currently the Z80 Minicom consists of the following specs:

	* 8-bit Zilog Z80 Microprocessor (overclocked) @ 7.3268 MHz
	* 16K ROM with serial interface monitor program and Microsoft BASIC v4.7b interpreter
	* 64K static-RAM (48K usable due to ROM shadowing)
	* USB serial interface (overclocked) @ 115200 bps
	* Hardware IO for real-world interface applications
	* Improved BASIC with additional custom-written commands & custom bootstrap interpreter

The Z80 Minicom II is a redesigned and improved version of the Z80 Minicom with the ability to use the entire 64K RAM space by switching the ROM out and with the addition of a CompactFlash card it has permanent storage, allowing it to run CP/M 2.2  It also uses an ATmega168 microcontroller to drastically enhance its IO potential:

Features as Z80 Minicom except as below:

	* 4 or 8 MHz clockspeed, user selectable in software via the Arduino Nano Serial Support Module (SSM)
	* Compact breadboard layout
	* Z80 SIO/2 providing two serial interfaces, with interrupt-driven Rx channels to prevent unnecessary polling of the Rx buffer when not in use
	* Memory management facilitates disabling ROM to allow full 64K RAM access
	* CompactFlash adapter with 64MB CF card providing 8x8MB drives for file storage
	* OS - custom ROM monitor providing NASCOM BASIC, memory and Intel HEX file input utilities & CP/M 2.2
	* CP/M 2.2 with BBC BASIC and Microsoft BASIC-80 5.29, amongst other software for assembly etc
	* Able to play Zork I, II & III
	* FT232RL interface on-board allowing for stable connection via normal USB lead to host computer
	* IO mapping improved from original design to only trigger IO ports on appropriate IORQ and M1 transactions
	* Fully-expandable interrupt system implemented
	* CTC added for clock/timer functions and user-programmable triggerable interrupts
	* PIO added for 2-channel parallel IO (Channel B to be used for I<sup>2</sup>C interface)
	
## Planned future specifications:

The Z80 Minicomp II is in the early stages of development at the moment and will expand as more features are created and added.  The following list of features is more of a wish-list at the moment.

	* Sound capabilities via AY-3-891x PSG
	* SPI bus for future expansion
	* I<sup>2</sup>C bus for future expansion
	* Direct Memory Access for Microcontroller
	* Reset & Interrupt integration for Microcontroller
	* SD card reader to allow for additional/alternative file storage (via SPI bus)
	* Fully-buffered control, address and data buses for expansion
	* Efficient memory management to allow paging of 16K SRAM blocks (the Z80 Minicom II has a 128K SRAM chip, but uses only 64K due to the limitations of the Z80's 16-bit address bus)
	* ROM paging to allow for multiple monitor software versions (again, the Z80 Minicom has a 128K EEPROM, which can hold much more than just the base 16K)
	* Keyboard & video interface for standalone use
	
## Current Memory & IO Map:

**Memory Map**

* 0000-3FFF   16K ROM
    * 0000-1FFF - Bootstrap area (with room to expand)
    * 2000-3FFF - BASIC area
* 4000-FFFF   RAM (48K)

**Memory Map in CP/M mode**

* 0000-0100	  Low storage & interrupt vectors
* 0100-0D00   TPA (Transient Program Area)
* 0D00-E5FF   CP/M
* E600-FFFF   BIOS

**I/O Map for (Z80 Minicom II only)**

* 00-07     SIO/2 dual-port serial interface
* 08-0F   	AY-3-891x Programmable Sound Generator
* 10-17   	Compactflash interface
* 18-1F  	CTC 4-channel programmable clock/timer
* 20-27     PIO 2-channel parallel & I�C interface
* 28-2F     Reserved for SPI interface
* 30-37     Unused
* 38-3F     Unused

**I/O Map for (Z80 Minicom)**

* 00H       I/O - 1-bit input, 8-bit output
* 01-7F   	Free (128 input and 128 output ports)
* 80-81   	SERIAL INTERFACE (//minimally decoded, actually covers locations 80 to BF//)
* C0-FF  	Free (64 input and 64 output ports)

** Software Routine Map**

The following routines are available via the Minicom's bootstrap code:

* 00C0H - RXA - Receives a character to A register from the serial terminal (and waits until one is received)
* 0124H - TXA - Transmits a character from A register to serial terminal
* 025DH - COMMAND - Main loop for the Direct Mode bootstrap terminal
* 027AH - CRLF - Print new line
* 034AH - USRCODE - Spare routine for user code in the ROM to be called
* 035FH - COLDSTART - Cold-start BASIC interpreter
* 04D7H - PHEX - Print hex digit from A register
