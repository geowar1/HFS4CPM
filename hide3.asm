;    -*- tab-width:	8; -*-

TITLE	'CPM3 MODULE FOR IDE/CF.'

;	12/28/2009	Corrected high/low byte R/W of data to sectors
;	03/15/2011	Single reset pulse to IDE board
;	03/11/2016	Added 'no holes' LBA translation
;	05/28/2021	Replaced BANKED with 'maclib config'

	maclib config	;define TRUE, FALSE, BANKED, NUMDSK

BELL	EQU	07H
CR	EQU	0DH
LF	EQU	0AH

;Ports for 8255 chip. Change these to specify where the 8255 is addressed,
;and which of the 8255's ports are connected to which IDE signals.
;The first three control which 8255 ports have the control signals,
;upper and lower data bytes.  The last one is for mode setting for the
;8255 to configure its ports, which must correspond to the way that
;the first three lines define which ports are connected.

IDEportA	EQU	030H		;lower 8 bits of IDE interface
IDEportB	EQU	031H		;upper 8 bits of IDE interface
IDEportC	EQU	032H		;control lines for IDE interface
IDEportCtrl	EQU	033H		;8255 configuration port

READcfg8255	EQU	10010010b	;Set 8255 IDEportC out, IDEportA/B input
WRITEcfg8255	EQU	10000000b	;Set all three 8255 ports output

;IDE control lines for use with IDEportC.  Change these 8
;constants to reflect where each signal of the 8255 each of the
;IDE control signals is connected.  All the control signals must
;be on the same port, but these 8 lines let you connect them to
;whichever pins on that port.

IDEa0line	EQU	01H	;direct from 8255 to IDE interface
IDEa1line	EQU	02H	;direct from 8255 to IDE interface
IDEa2line	EQU	04H	;direct from 8255 to IDE interface
IDEcs0line	EQU	08H	;inverter between 8255 and IDE interface
IDEcs1line	EQU	10H	;inverter between 8255 and IDE interface
IDEwrline	EQU	20H	;inverter between 8255 and IDE interface
IDErdline	EQU	40H	;inverter between 8255 and IDE interface
IDErstline	EQU	80H	;inverter between 8255 and IDE interface
;
;Symbolic constants for the IDE Drive registers, which makes the
;code more readable than always specifying the address pins

REGdata		EQU	IDEcs0line
REGerr		EQU	IDEcs0line + IDEa0line
REGseccnt	EQU	IDEcs0line + IDEa1line
REGsector	EQU	IDEcs0line + IDEa1line + IDEa0line
REGcylinderLSB	EQU	IDEcs0line + IDEa2line
REGcylinderMSB	EQU	IDEcs0line + IDEa2line + IDEa0line
REGshd		EQU	IDEcs0line + IDEa2line + IDEa1line		;(0EH)
REGcommand	EQU	IDEcs0line + IDEa2line + IDEa1line + IDEa0line	;(0FH)
REGstatus	EQU	IDEcs0line + IDEa2line + IDEa1line + IDEa0line
REGcontrol	EQU	IDEcs1line + IDEa2line + IDEa1line
REGastatus	EQU	IDEcs1line + IDEa2line + IDEa1line + IDEa0line

;IDE Command Constants.	 These should never change.

COMMANDrecal	EQU	10H
COMMANDread	EQU	20H
COMMANDwrite	EQU	30H
COMMANDinit	EQU	91H
COMMANDid	EQU	0ECH
COMMANDspindown EQU	0E0H
COMMANDspinup	EQU	0E1H
;
MAXSEC		EQU	40H	;Sectors per track for CF my Memory drive, Kingston CF 8G. (CPM format, 0-3D)
;				;Note this will also work with a Seagate 6531 IDE drive
;
; IDE Status Register:
;  bit 7: Busy	1=busy, 0=not busy
;  bit 6: Ready 1=ready for command, 0=not ready yet
;  bit 5: DF	1=fault occured insIDE drive
;  bit 4: DSC	1=seek complete
;  bit 3: DRQ	1=data request ready, 0=not ready to xfer yet
;  bit 2: CORR	1=correctable error occured
;  bit 1: IDX	vendor specific
;  bit 0: ERR	1=error occured
;
	; DEFINE PUBLIC LABELS:

;DISK PARAMETER HEADERS
if NUMDSK GE 1
	PUBLIC	DPH0
endif
if NUMDSK GE 2
	PUBLIC	DPH1
endif
if NUMDSK GE 3
	PUBLIC	DPH2
endif
if NUMDSK GE 4
	PUBLIC	DPH3
endif
if NUMDSK GT 4
	.printx 'ERROR: UNSUPPORTED NUMDSK (>4)!'
endif

	; DEFINE EXTERNAL LABELS:
	EXTRN	@ADRV,@RDRV
	EXTRN	@DMA,@TRK,@SECT
	EXTRN	@CBNK
	EXTRN	@DBNK			;BANK FOR DMA OPERATION
	EXTRN	@ERMDE			;BDOS ERROR MODE
	EXTRN	?WBOOT			;WARM BOOT VECTOR
	EXTRN	?PMSG			;PRINT MESSAGE @<HL> UP TO 00, SAVES
					; [BC] AND [DE]
	EXTRN	?PDERR			;PRINT BIOS DISK ERROR HEADER
	EXTRN	?CONIN,?CONO		;CONSOLE IN AND OUT
	EXTRN	?CONST			;CONSOLE STATUS
	EXTRN	?BNKSL		;SELECT PROCESSOR MEMORY BANK

	; INCLUDE CP/M 3.0 DISK DEFINITION MACROS:
	MACLIB	CPM3

	; INCLUDE Z-80 MACRO LIBRARY:
	MACLIB	Z80

IF BANKED
	DSEG		;PUT IN OP SYS BANK IF BANKING
ELSE
	CSEG
ENDIF

hdtype	equ	10h		; Media type for Hard Disk

	; EXTENDED DISK PARAMETER HEADER FOR DRIVE 0:
	DW	HDWRT		;HARD DISK WRITE ROUTINE
	DW	HDRD		;HARD DISK READ ROUTINE
	DW	HDLOGIN		;HARD DISK LOGIN PROCEDURE
	DW	HDINIT		;HARD DISK DRIVE INITIALIZATION ROUTINE
	DB	0		;RELATIVE DRIVE 0 ON THIS CONTROLLER
	DB	hdtype		;MEDIA TYPE:
				;  HI BIT SET : DRIVE NEEDS RECALIBRATING

DPH0:	DPH	0,DPB0,0,

if NUMDSK GE 2

	; EXTENDED DISK PARAMETER HEADER FOR DRIVE 1:
	DW	HDWRT		;HARD DISK WRITE ROUTINE
	DW	HDRD		;HARD DISK READ ROUTINE
	DW	HDLOGIN		;HARD DISK LOGIN PROCEDURE
	DW	HDINIT		;HARD DISK DRIVE INITIALIZATION ROUTINE
	DB	0		;RELATIVE DRIVE 0 ON THIS CONTROLLER
	DB	hdtype		;MEDIA TYPE:
				;  HI BIT SET : DRIVE NEEDS RECALIBRATING

DPH1:	DPH	0,DPB1,0,

endif	;NUMDSK GE 2
if NUMDSK GE 3

	; EXTENDED DISK PARAMETER HEADER FOR DRIVE 2:
	DW	HDWRT		;HARD DISK WRITE ROUTINE
	DW	HDRD		;HARD DISK READ ROUTINE
	DW	HDLOGIN		;HARD DISK LOGIN PROCEDURE
	DW	HDINIT		;HARD DISK DRIVE INITIALIZATION ROUTINE
	DB	0		;RELATIVE DRIVE 0 ON THIS CONTROLLER
	DB	hdtype		;MEDIA TYPE:
				;  HI BIT SET : DRIVE NEEDS RECALIBRATING

DPH2:	DPH	0,DPB2,0,

endif	;NUMDSK GE 3
if NUMDSK GE 4

	; EXTENDED DISK PARAMETER HEADER FOR DRIVE 3:
	DW	HDWRT		;HARD DISK WRITE ROUTINE
	DW	HDRD		;HARD DISK READ ROUTINE
	DW	HDLOGIN		;HARD DISK LOGIN PROCEDURE
	DW	HDINIT		;HARD DISK DRIVE INITIALIZATION ROUTINE
	DB	0		;RELATIVE DRIVE 0 ON THIS CONTROLLER
	DB	hdtype		;MEDIA TYPE:
				;  HI BIT SET : DRIVE NEEDS RECALIBRATING

DPH3:	DPH	0,DPB3,0,

endif	;NUMDSK GE 4

	; MAKE SURE DPB'S ARE IN COMMON MEMORY:
	CSEG
;
; Disk Layout
;
;	CompactFlash Drive
;
;	Sector size 512 bytes
;	Each track is 64 (512 byte) Sectors = 32 Kb
;	Partition size is 8192 Kb = 256 Tracks
;
;	Partition 0 256 Tracks		Track 0 (boot), 1..255 (CP/M)
;	Partition 1 256 Tracks		Track 256..511 (CP/M)
;	Partition 2 256 Tracks		Track 512..767 (CP/M)
;	Partition 3 256 Tracks		Track 768..1023 (CP/M)
;
asdf	equ	0			; this is false
hstsiz	equ	512			; CF Sector size
spt	equ	64			; # of Sectors per track
numtrks equ	256			; # of tracks per drive
blksiz	equ	2048			; Blocksize
spb	equ	blksiz/hstsiz		; Sectors per block
drm	equ	1024			; # of directory entries (also see DPB)
dsm	equ	numtrks*(spt/spb)	; # of blocks per drive
dsm0	equ	(numtrks-1)*(spt/spb)	; For boot drive we have 1 reserved track
bsh	equ	4			; Block shift factor
blm	equ	00001111b		; Block mask for bsh bits
exm	equ	0			; Extent mask
al0	equ	11111111b		; First two bytes of allocation vector
al1	equ	11111111b		; (reserve 16 groups for directory)
psh	equ	2			; Physical record shift factor
phm	equ	00000011b		; Block mask for psh bits

	if	hstsiz ne 512
		; Block address calculations depend on this!
		.printx "Error: IDE sector size must be 512 bytes"
	endif

DPB0:
    if use$disk$macros
	DPB	hstsiz,spt,numtrks,blksiz,drm,1,8000H
    else
	dw	(hstsiz/128)*spt	; Logical 128-byte sectors per track
	db	bsh, blm		; Block shift and mask
	db	exm			; Extent mask
	dw	dsm0-1			; Maximum block number - 1
	dw	drm-1			; Number of directory entries - 1
	db	al0,al1			; Allocation for directory
	dw	8000h			; Permanently mounted drive
	dw	1			; 1 reserved track
	db	psh,phm			; Physical record shift factor and mask
    endif ;use$disk$macros
	db	'hfs+'			; Partition signature
	dw	0			; Partition #

if NUMDSK GE 2
DPB1:
  if use$disk$macros
	DPB	hstsiz,spt,numtrks,blksiz,drm,0,8000H
  else
	dw	(hstsiz/128)*spt	; Logical 128-byte sectors per track
	db	bsh, blm		; Block shift and mask
	db	exm			; Extent mask
	dw	dsm-1			; Maximum block number - 1
	dw	drm-1			; Number of directory entries - 1
	db	al0,al1			; Allocation for directory
	dw	8000h			; Permanently mounted drive
	dw	0			; reserved tracks
	db	psh,phm			; Physical record shift factor and mask
  endif
	db	'hfs+'			; Partition signature
	dw	1			; Partition #
endif	;NUMDSK GE 2
if NUMDSK GE 3
DPB2:
  if use$disk$macros
	DPB	hstsiz,spt,numtrks,blksiz,drm,0,8000H
  else
	dw	(hstsiz/128)*spt	; Logical 128-byte sectors per track
	db	bsh, blm		; Block shift and mask
	db	exm			; Extent mask
	dw	dsm-1			; Maximum block number - 1
	dw	drm-1			; Number of directory entries - 1
	db	al0,al1			; Allocation for directory
	dw	8000h			; Permanently mounted drive
	dw	0			; reserved tracks
	db	psh,phm			; Physical record shift factor and mask
  endif
	db	'hfs+'			; Partition signature
	dw	2			; Partition #
endif	;NUMDSK GE 3
if NUMDSK GE 4

DPB3:
  if use$disk$macros
	DPB	hstsiz,spt,numtrks,blksiz,drm,0,8000H
  else
	dw	(hstsiz/128)*spt	; Logical 128-byte sectors per track
	db	bsh, blm		; Block shift and mask
	db	exm			; Extent mask
	dw	dsm-1			; Maximum block number - 1
	dw	drm-1			; Number of directory entries - 1
	db	al0,al1			; Allocation for directory
	dw	8000h			; Permanently mounted drive
	dw	0			; reserved tracks
	db	psh,phm			; Physical record shift factor and mask
  endif
	db	'hfs+'			; Partition signature
	dw	3			; Partition #
endif	;NUMDSK GE 4

IF BANKED
	DSEG			;CAN SET BACK TO BANKED SEGMENT IF BANKING
ENDIF

	;;;;; HDINIT:
HDINIT: ;;CALL	dumpregs
	RET			;DO NOT INITILIZE HARD DISK YET
;


	;;;;; HDLOGIN
;-----------------INITILIZE THE IDE HARD DISK  -----------------------------------------

HDLOGIN:;;CALL	dumpregs
					;Initilze the 8255 and drive then do a hard reset on the drive,
	MVI	A,READcfg8255		;Config 8255 chip (10010010B), read mode on return
	OUT	IDEportCtrl		;Config 8255 chip, READ mode

					;Hard reset the disk drive
					;For some reason some CF cards need to the RESET line
					;pulsed very carefully. You may need to play around
	MVI	A,IDErstline		;with the pulse length. Symptoms are: incorrect data comming
	OUT	IDEportC		;back from a sector read (often due to the wrong sector being read)
					;I have a (negative)pulse of 2.7uSec. (10Mz Z80, two IO wait states).
	MVI	B,20H			;Which seem to work for the 5 different CF cards I have.
ResetDelay:
	DCR	B
	JNZ	ResetDelay		;Delay (reset pulse width)

	XRA	A
	OUT	IDEportC		;No IDE control lines asserted (just bit 7 of port C)
	CALL	DELAY$32

	;****** A. Bingham inserted code from D.Fry - 16/03/2018 *****
	CALL	IDEwaitnotbusy	;Make sure CF drive is ready to
	JC	SetErrorFlag	;accept CMD - If problem abort
	;*************************************************************

	MVI	D,11100000b		;Data for IDE SDH reg (512bytes, LBA mode,single drive,head 0000)
					;For Trk,Sec,head (non LBA) use 10100000
					;Note. Cannot get LBA mode to work with an old Seagate Medalist 6531 drive.
					;have to use the non-LBA mode. (Common for old hard disks).

	MVI	E,REGshd		;00001110,(0EH) for CS0,A2,A1,
	CALL	IDEwr8D			;Write byte to select the MASTER device

;
	MVI	B,0FFH		;<<< May need to adjust delay time
WaitInit:
	MVI	E,REGstatus	;Get status after initilization
	CALL	IDErd8D		;Check Status (info in [D])
	BIT	7,D
	JZ	DoneInit	;Return if ready bit is zero
;				;Delay to allow drive to get up to speed
	PUSH	B
	LXI	B,0FFFFH
DELAY2: MVI	D,2		;May need to adjust delay time to allow cold drive to
DELAY1: DCR	D		;to speed
	JNZ	DELAY1
	DCX	B
	MOV	A,C
	ORA	B
	JNZ	DELAY2
	POP	B

	DJNZ	WaitInit
	CALL	SetErrorFlag	;Ret with NZ flag set if error (probably no drive)
	LXI	H,MSG$INIT$ERR	;RESTORE FAILED
	CALL	?PMSG
	ORI	1
	RET
DoneInit:
	XRA	A		;RETURN WITH NO ERROR
	RET
;
;
;------------------- SECTOR WRITE ROUTINE ----------------------------
	; ROUTINE WRITES 1 SECTOR TO THE DISK:
;
HDWRT:	CALL	wrlba		;Send to drive the sector we want to read. Converting
				;CPM TRK/SEC info to Drive TRK/SEC/Head
				;send before error check so info is updated
	CALL	IDEwaitnotbusy	;make sure drive is ready
	JC	SetErrorFlag

	MVI	D,COMMANDwrite
	MVI	E,REGcommand
	CALL	IDEwr8D		;Send sec write command to drive.
	CALL	IDEwaitdrq	;wait unit it wants the data
	JC	SetErrorFlag	;If problem abort

	LHLD	@DMA		;DMA address

	IF BANKED
		JMP	ADJBNNN

		CSEG

		ADJBNNN:
			LDA	@CBNK
			PUSH	PSW
			LDA	@DBNK
			CALL	?BNKSL
	ENDIF

	MVI	A,WRITEcfg8255
	OUT	IDEportCtrl

	MVI	B,0		;256X2 bytes
WRSEC1: MOV	A,M
	INX	H
	OUT	IDEportA	;LOW byte on A first
	MOV	A,M
	INX	H
	OUT	IDEportB	;then HIGH byte on B
	MVI	A,REGdata
	PUSH	PSW
	OUT	IDEportC	;Send write command
	ORI	IDEwrline	;Send WR pulse
	OUT	IDEportC
	POP	PSW
	OUT	IDEportC
	DJNZ	WRSEC1

	MVI	A,READcfg8255	;Set 8255 back to read mode
	OUT	IDEportCtrl

	IF	BANKED
		POP	PSW
		CALL	?BNKSL
		JMP	CHECK$RW

		DSEG
	ENDIF

CHECK$RW:
	MVI	E,REGstatus	;Check R/W status when done
	CALL	IDErd8D
	MOV	A,D
	ANI	01H
	STA	ERFLG		;Ret Z if All OK
	RZ
SetErrorFlag:			;For now just return with error flag set
	XRA	A
	DCR	A
	STA	ERFLG		;Ret NZ if problem
	RET
;
;
;------------------- SECTOR READ ROUTINE ----------------------------
	; ROUTINE READS 1 PHYSICAL SECTOR FROM THE DRIVE:
;
HDRD:	CALL	wrlba		;Send to drive the sector we want to read. Converting
				;CPM TRK/SEC info to Drive TRK/SEC/Head
				;Send before error check so info is updated
	CALL	IDEwaitnotbusy	;make sure drive is ready
	JC	SetErrorFlag	;Returned with NZ set if error

	MVI	D,COMMANDread
	MVI	E,REGcommand
	CALL	IDEwr8D		;Send sec read command to drive.
	CALL	IDEwaitdrq	;Wait until it's got the data
	JC	SetErrorFlag	;If problem abort

	LHLD	@DMA		;DMA address

	IF BANKED
		JMP	ADJBNKS

		CSEG

		ADJBNKS:
			LDA	@CBNK
			PUSH	PSW
			LDA	@DBNK	;MUST HAVE THIS CODE IN COMMON
			CALL	?BNKSL	;NOW DMA ADDRESS IS AT THE CORRECT BANK
	ENDIF

	MVI	B,0

MoreRD16:
	MVI	A,REGdata	;REG regsiter address
	OUT	IDEportC

	ORI	IDErdline	;08H+40H, Pulse RD line
	OUT	IDEportC

	IN	IDEportA	;READ  the LOW byte first
	MOV	M,A
	INX	H
	IN	IDEportB	;THEN the HIGH byte
	MOV	M,A
	INX	H

	MVI	A,REGdata	;Deassert RD line
	OUT	IDEportC

	DJNZ	MoreRD16

	IF BANKED
		POP	PSW
		CALL	?BNKSL
	ENDIF

	JMP	CHECK$RW

	IF BANKED
		DSEG
	ENDIF
;      ----- SUPPORT ROUTINES --------------
;
;  Convert CP/M Track and Sector requests to LBA and write to drive registers
;
wrlba:	;;CALL	DUMPINFO
;
	XRA	A			;CLEAR ERROR FLAG
	STA	ERFLG
;
;GET THE RELATIVE DRIVE #
;
	LXI	H,12			;add offset to address of DPB
	DAD	D			;to address of XDPH
;
	MOV	E,M			;get LSByte of DPB
	INX	H			;bump pointer
	MOV	D,M			;get MSByte of DPB
;
	LXI	H,17+4			;add offset to address of partition #
	DAD	D
;
	MOV	E,M			;get LSByte of partition #
	INX	H			;bump pointer
	MOV	A,M			;get MSByte of partition #
;
;Now we want to build our LBA as PPPPPPPP PPTTTTTT TTSSSSSS in DHL
;First we load the track (0-255) and partition # (0-1023) into AHL
;and then multiply it by 64 (six shifts left) and put the high byte into D
;and then OR the sector # (0-63) into the LSByte
;
	LHLD	@TRK			;get CPM requested Track (0-255)
	MOV	H,E			;get LSByte of partition #
;
	MVI	B,06H			;shift AHL 6 places to left (*64)
lbatrk: DAD	H			;shift HL left one bit
	RAL				;rotate overflow into Acc
	DJNZ	lbatrk			;loop around 6 times i.e x 64
;
	MOV	D,A			;get MSByte of LBA
;
	LDA	@SECT			;Get CPM requested sector
	ORA	L			;Add value in L to sector info in A
	MOV	L,A			;copy LSByte of LBA to L
;
;DHL should now contain correct LBA value
;
	MVI	E,REGcylinderMSB
	CALL	IDEwr8D			;Send info to drive

	MOV	D,H			;load lba high byte to D from H
	MVI	E,REGcylinderLSB
	CALL	IDEwr8D			;Send info to drive

	MOV	D,L			;load lba low byte to D from L
	MVI	E,REGsector
	CALL	IDEwr8D			;Send info to drive

	MVI	D,1			;For now, one sector at a time
	MVI	E,REGseccnt
	JP	IDEwr8D
;
IDEwaitnotbusy:			;Drive READY if 01000000
	MVI	B,0FFH
	MVI	C,0FFH		;Delay, must be above 80H for 4MHz Z80. Leave longer for slower drives
MoreWait:
	MVI	E,REGstatus	;wait for RDY bit to be set
	CALL	IDErd8D
	MOV	A,D
	ANI	11000000B
	XRI	01000000B
	JZ	DoneNotbusy
	DJNZ	MoreWait
	DCR	C
	JNZ	MoreWait
	STC			;Set carry to indicqate an error
	ret
DoneNotBusy:
	ORA	A		;Clear carry it indicate no error
	RET
				;Wait for the drive to be ready to transfer data.
				;Returns the drive's status in Acc
IDEwaitdrq:
	MVI	B,0FFH
	MVI	C,0FFH		;Delay, must be above 80H for 4MHz Z80. Leave longer for slower drives
MoreDRQ:
	MVI	E,REGstatus	;wait for DRQ bit to be set
	CALL	IDErd8D
	MOV	A,D
	ANI	10001000B
	CPI	00001000B
	JZ	DoneDRQ
	DJNZ	MoreDRQ
	DCR	C
	JNZ	MoreDRQ
	STC			;Set carry to indicate error
	RET
DoneDRQ:
	ORA	A		;Clear carry
	RET


DELAY$32: MVI	A,40			;DELAY ~32 MS (DOES NOT SEEM TO BE CRITICAL)
DELAY3: MVI	B,0
M0:	DJNZ	M0
	DCR	A
	JNZ	DELAY3
	RET

;------------------------------------------------------------------
; Low Level 8 bit R/W to the drive controller.	These are the routines that talk
; directly to the drive controller registers, via the 8255 chip.
; Note the 16 bit I/O to the drive (which is only for SEC R/W) is done directly
; in the routines HDRD & HDWRT for speed reasons.
;
IDErd8D:				;READ 8 bits from IDE register in [E], return info in [D]
	MOV	A,E
	OUT	IDEportC		;drive address onto control lines

	ORI	IDErdline		;RD pulse pin (40H)
	OUT	IDEportC		;assert read pin

	IN	IDEportA
	MOV	D,A			;return with data in [D]

	MOV	A,E			;<---Ken Robbins suggestion
	OUT	IDEportC		;deassert RD pin first

	XRA	A
	OUT	IDEportC		;Zero all port C lines
	ret
;
;
IDEwr8D:				;WRITE Data in [D] to IDE register in [E]
	MVI	A,WRITEcfg8255		;Set 8255 to write mode
	OUT	IDEportCtrl

	MOV	A,D			;Get data put it in 8255 A port
	OUT	IDEportA

	MOV	A,E			;select IDE register
	OUT	IDEportC

	ORI	IDEwrline		;lower WR line
	OUT	IDEportC

	MOV	A,E			;<---Ken Robbins suggestion
	OUT	IDEportC		;deassert WR pin first

	XRA	A			;Deselect all lines including WR line
	OUT	IDEportC

	MVI	A,READcfg8255		;Config 8255 chip, read mode on return
	OUT	IDEportCtrl
	RET
;
MSG$INIT$ERR DB 'Initilization of IDE drive failed.',CR,LF,0
;
ERFLG:	DB	0H
;
IF	0
DUMPINFO:
	LXI	H,INF010
	CALL	?PMSG
	LDA	@RDRV
	CALL	HEXB
;
	LXI	H,INF020
	CALL	?PMSG
	LHLD	@TRK
	CALL	HEXW
;
	LXI	H,INF030
	CALL	?PMSG
	LDA	@SECT
	CALL	HEXB
;
	LXI	H,INF040
	CALL	?PMSG
	LHLD	@DMA
	CALL	HEXW
;
	LXI	H,INF050
	JMP	?PMSG
;
INF010: DB	CR,LF,'REL DSK: ',0
INF020: DB	', TRK: ',0
INF030: DB	', SEC: ',0
INF040: DB	', DMA: ',0
INF050: DB	CR,LF,0
ENDIF
;
IF	0
dumpregs:
	PUSH	PSW
	PUSH	b
	PUSH	d
	PUSH	h
;
	LXI	H,DRM010
	CALL	?PMSG
;
	LXI	h,6
	DAD	SP
	MOV	A,M
	INX	H
	MOV	H,M
	CALL	HEXW
;
	LXI	H,DRM020
	CALL	?PMSG
;
	LXI	h,4
	DAD	SP
	MOV	A,M
	INX	H
	MOV	H,M
	CALL	HEXW
;
	LXI	H,DRM030
	CALL	?PMSG
;
	LXI	h,2
	DAD	SP
	MOV	A,M
	INX	H
	MOV	H,M
	CALL	HEXW
;
	LXI	H,DRM040
	CALL	?PMSG
;
	LXI	h,0
	DAD	SP
	MOV	A,M
	INX	H
	MOV	H,M
	CALL	HEXW
;
	POP	h
	POP	d
	POP	b
	POP	a
	RET
;
DRM010: DB	CR,LF,' AF: ',0
DRM020: DB	', BC: ',0
DRM030: DB	', DE: ',0
DRM040: DB	', HL: ',0
DRM050: DB	CR,LF,0
ENDIF
;
IF	0
;##############################################################################
;output hex word (in hl)
;##############################################################################
;
HEXW:	PUSH	PSW	;save register
	MOV	A,H
	CALL	HEXB	;MSB of word
	MOV	A,L	;LSB of word
	CALL	HEXB	;MSB of word
	POP	PSW
	RET
;
;##############################################################################
;output hex byte (in a)
;##############################################################################
;
HEXB:	PUSH	PSW	;save register
;
	RRC
	RRC
	RRC
	RRC
;
	CALL	HEXN
;
	POP	PSW	;restore acc
;note: fall thru to HEXN
;##############################################################################
;output hex nibble (in a)
;##############################################################################
;
HEXN:	PUSH	PSW	;save register
;
	ORI	0F0h	;convert to ASCII
	DAA
	ADI	0A0h
	ACI	040h
;
	CALL	PUTCHR
;
	POP	PSW	;restore register
	RET
;
;##############################################################################
;write character to console from a
;##############################################################################
;
PUTCHR: ;CALL	pushall		;save all registers (and popall as return address)
	PUSH	PSW
	PUSH	B
	PUSH	D
	PUSH	H
	MOV	C,A		;character to send
	CALL	?CONO		;send character
	POP	H
	POP	D
	POP	B
	POP	PSW
	RET
;
ENDIF
;
	END
