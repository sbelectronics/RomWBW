; -----------------------------------------------------------------------------
; Z80 SIO/2 Driver
;
; Based on Grant Searle's CPM BIOS
;
; Implements two serial ports for one SIO/2 chip. Uses Z80 IM2 and has an
; interrupt handler to buffer incoming characters.
;
; NOTE: If VFDTERMENABLE is set, then VFD will mirror the output on port A
;
; TODO: Probably should combine the separate code for ports A and B, and use
;       a single dispatch table.
; -----------------------------------------------------------------------------

SER_BUFSIZE	.EQU	150
SER_FULLSIZE	.EQU	140
SER_EMPTYSIZE	.EQU	5

RTS_HIGH	.EQU	0E8H
RTS_LOW		.EQU	0EAH

SIOA_D		.EQU	$80             ; Base address of SIO/2 chip
SIOA_C		.EQU	SIOA_D+2
SIOB_D		.EQU	SIOA_D+1
SIOB_C		.EQU	SIOA_D+3

SIO_IV          .EQU    2               ; Interrupt vector table entry to use

SIO_PREINIT:
        LD      DE,SIO_CFG_A
	LD	BC,SIO_DISPATCH_A	; BC := DISPATCH ADDRESS
	CALL	CIO_ADDENT

        LD      DE,SIO_CFG_B
	LD	BC,SIO_DISPATCH_B	; BC := DISPATCH ADDRESS
	CALL	CIO_ADDENT

;	Initialise SIO
		LD	A,$00
		OUT	(SIOA_C),A
		LD	A,$18
		OUT	(SIOA_C),A

		LD	A,$04
		OUT	(SIOA_C),A
		LD	A,$C4
		OUT	(SIOA_C),A

		LD	A,$01
		OUT	(SIOA_C),A
		LD	A,$18
		OUT	(SIOA_C),A

		LD	A,$03
		OUT	(SIOA_C),A
		LD	A,$C1	; was $E1, switched to $C1 to disable CTS auto enable
		OUT	(SIOA_C),A

		LD	A,$05
		OUT	(SIOA_C),A
		LD	A,RTS_LOW
		OUT	(SIOA_C),A

		LD	A,$00
		OUT	(SIOB_C),A
		LD	A,$18
		OUT	(SIOB_C),A

		LD	A,$04
		OUT	(SIOB_C),A
		LD	A,$C4
		OUT	(SIOB_C),A

		LD	A,$01
		OUT	(SIOB_C),A
		LD	A,$18
		OUT	(SIOB_C),A

		LD	A,$02
		OUT	(SIOB_C),A
		LD	A,SIO_IV		; INTERRUPT VECTOR ADDRESS
		OUT	(SIOB_C),A

		LD	A,$03
		OUT	(SIOB_C),A
		LD	A,$C1  # was $E1, switched to $C1 to disable CTS auto enable
		OUT	(SIOB_C),A

		LD	A,$05
		OUT	(SIOB_C),A
		LD	A,RTS_LOW
		OUT	(SIOB_C),A

                XOR	a

		LD	(serABufUsed),A
		LD	(serBBufUsed),A
		LD	HL,serABuf
		LD	(serAInPtr),HL
		LD	(serARdPtr),HL

		LD	HL,serBBuf
		LD	(serBInPtr),HL
		LD	(serBRdPtr),HL

                LD	HL, INT_SIO             ; Install SIO interrupt handler
                LD	(HBX_IVT + SIO_IV),HL

;		IM	2
;		EI				; Enable interrupts

                RET

SIO_DISPATCH_A
	; DISPATCH TO FUNCTION HANDLER
	PUSH	HL			; SAVE HL FOR NOW
	LD	A,B			; GET FUNCTION
	AND	$0F			; ISOLATE LOW NIBBLE
	RLCA				; X 2 FOR WORD OFFSET INTO FUNCTION TABLE
	LD	HL,SIO_FTBL_A		; START OF FUNC TABLE
	CALL	ADDHLA			; HL := ADDRESS OF ADDRESS OF FUNCTION
	LD	A,(HL)			; DEREF HL
	INC	HL			; ...
	LD	H,(HL)			; ...
	LD	L,A			; ... TO GET ADDRESS OF FUNCTION
	EX	(SP),HL			; RESTORE HL & PUT FUNC ADDRESS -> (SP)
	RET				; EFFECTIVELY A JP TO TGT ADDRESS

SIO_FTBL_A
	.DW	SIO_IN_A
	.DW	SIO_OUT_A
	.DW	SIO_IST_A
	.DW	SIO_OST_A
	.DW	SIO_INITDEV
	.DW	SIO_QUERY
	.DW	SIO_DEVICE

SIO_DISPATCH_B
	; DISPATCH TO FUNCTION HANDLER
	PUSH	HL			; SAVE HL FOR NOW
	LD	A,B			; GET FUNCTION
	AND	$0F			; ISOLATE LOW NIBBLE
	RLCA				; X 2 FOR WORD OFFSET INTO FUNCTION TABLE
	LD	HL,SIO_FTBL_B		; START OF FUNC TABLE
	CALL	ADDHLA			; HL := ADDRESS OF ADDRESS OF FUNCTION
	LD	A,(HL)			; DEREF HL
	INC	HL			; ...
	LD	H,(HL)			; ...
	LD	L,A			; ... TO GET ADDRESS OF FUNCTION
	EX	(SP),HL			; RESTORE HL & PUT FUNC ADDRESS -> (SP)
	RET				; EFFECTIVELY A JP TO TGT ADDRESS

SIO_FTBL_B
	.DW	SIO_IN_B
	.DW	SIO_OUT_B
	.DW	SIO_IST_B
	.DW	SIO_OST_B
	.DW	SIO_INITDEV
	.DW	SIO_QUERY
	.DW	SIO_DEVICE

SIO_INIT:
         XOR    A                       ; Signal success
         RET

; ----------------------------------------------------------------------------
; Interrupt Service Routine
; ----------------------------------------------------------------------------

SIO_INT_HDLR:
                ; Check if there is a char in channel A
		; If not, there is a char in channel B
		SUB	A
		OUT 	(SIOA_C),A
		IN   	A,(SIOA_C)	; Status byte D2=TX Buff Empty, D0=RX char ready
		RRCA			; Rotates RX status into Carry Flag,
		JR	NC, serialIntB

serialIntA:
		LD	HL,(serAInPtr)
		INC	HL
		LD	A,L
		CP	serAInMask
		JR	NZ, notAWrap
		LD	HL,serABuf
notAWrap:
		LD	(serAInPtr),HL
		IN	A,(SIOA_D)
		LD	(HL),A

		LD	A,(serABufUsed)
		INC	A
		LD	(serABufUsed),A
		CP	SER_FULLSIZE
		JR	C,rtsA0
	        LD   	A,$05
		OUT  	(SIOA_C),A
	        LD   	A,RTS_HIGH
		OUT  	(SIOA_C),A
rtsA0:
		RET

serialIntB:
		LD	HL,(serBInPtr)
		INC	HL
		LD	A,L
		CP	serBInMask
		JR	NZ, notBWrap
		LD	HL,serBBuf
notBWrap:
		LD	(serBInPtr),HL
		IN	A,(SIOB_D)
		LD	(HL),A

		LD	A,(serBBufUsed)
		INC	A
		LD	(serBBufUsed),A
		CP	SER_FULLSIZE
		JR	C,rtsB0
	        LD   	A,$05
		OUT  	(SIOB_C),A
	        LD   	A,RTS_HIGH
		OUT  	(SIOB_C),A
rtsB0:
		RET

; ----------------------------------------------------------------------------
; PORT A
; ----------------------------------------------------------------------------

; input character from port A

SIO_IN_A:       PUSH    HL

waitForCharA:   CALL    SIO_IST_A
                JR	Z, waitForCharA
		LD	HL,(serARdPtr)
		INC	HL
		LD	A,L
		CP	serAInMask
		JR	NZ, notRdWrapA
		LD	HL,serABuf
notRdWrapA:
		DI
		LD	(serARdPtr),HL

		LD	A,(serABufUsed)
		DEC	A
		LD	(serABufUsed),A

		CP	SER_EMPTYSIZE
		JR	NC,rtsA1
	        LD   	A,$05
		OUT  	(SIOA_C),A
	        LD   	A,RTS_LOW
		OUT  	(SIOA_C),A
rtsA1:
		LD	A,(HL)
		EI

		POP	HL

                LD      E, A                    ; CHAR READ TO E
                XOR	A			; SIGNAL SUCCESS

		RET

; output character to port A

SIO_OUT_A:
#IF (VFDTERMENABLE)
                CALL    VFDTERM_PUTC
#ENDIF
conoutA1:
                CALL	SIO_OST_A	; See if SIO channel A is finished transmitting
		JR	Z,conoutA1	; Loop until SIO flag signals ready
                LD      A, E            ; char to output is in E
		OUT	(SIOA_D),A	; OUTput the character
        	XOR	A	        ; SIGNAL SUCCESS
		RET

; check output status A

SIO_OST_A:
		SUB	A
		OUT 	(SIOA_C),A
		IN   	A,(SIOA_C)	; Status byte D2=TX Buff Empty, D0=RX char ready
                AND     $04
                JP      Z, CIO_IDLE
                XOR	A	       	; ZERO ACCUM
                INC	A	       	; ACCUM := 1 TO SIGNAL 1 BUFFER POSITION
        	RET

; check input status A

SIO_IST_A:
		LD	A,(serABufUsed)
                CP      $00
	        JP	Z,CIO_IDLE	; NOT READY, RETURN VIA IDLE PROCESSING
                XOR	A		; ZERO ACCUM
                INC	A		; ACCUM := 1 TO SIGNAL 1 CHAR WAITING
		RET

; ----------------------------------------------------------------------------
; PORT B
; ----------------------------------------------------------------------------

; input character from port A

SIO_IN_B:       PUSH    HL

waitForCharB:   CALL    SIO_IST_B
                JR	Z, waitForCharB
		LD	HL,(serBRdPtr)
		INC	HL
		LD	A,L
		CP	serBInMask
		JR	NZ, notRdWrapB
		LD	HL,serBBuf
notRdWrapB:
		DI
		LD	(serBRdPtr),HL

		LD	A,(serBBufUsed)
		DEC	A
		LD	(serBBufUsed),A

		CP	SER_EMPTYSIZE
		JR	NC,rtsB1
	        LD   	A,$05
		OUT  	(SIOB_C),A
	        LD   	A,RTS_LOW
		OUT  	(SIOB_C),A
rtsB1:
		LD	A,(HL)
		EI

		POP	HL

                LD      E, A                    ; CHAR READ TO E
                XOR	A			; SIGNAL SUCCESS

		RET

; output character to port B

SIO_OUT_B:
conoutB1:
                CALL	SIO_OST_B	; See if SIO channel A is finished transmitting
		JR	Z,conoutB1	; Loop until SIO flag signals ready
                LD      A, E            ; char to output is in E
		OUT	(SIOB_D),A	; OUTput the character
        	XOR	A	        ; SIGNAL SUCCESS
		RET

; check output status B

SIO_OST_B:
		SUB	A
		OUT 	(SIOB_C),A
		IN   	A,(SIOB_C)	; Status byte D2=TX Buff Empty, D0=RX char ready
                AND     $04
                JP      Z, CIO_IDLE
                XOR	A	       	; ZERO ACCUM
                INC	A	       	; ACCUM := 1 TO SIGNAL 1 BUFFER POSITION
        	RET

; check input status B

SIO_IST_B:
		LD	A,(serBBufUsed)
                CP      $00
	        JP	Z,CIO_IDLE	; NOT READY, RETURN VIA IDLE PROCESSING
                XOR	A		; ZERO ACCUM
                INC	A		; ACCUM := 1 TO SIGNAL 1 CHAR WAITING
		RET

;------------------------------------------------------------------------------
; COMMON
;------------------------------------------------------------------------------

SIO_QUERY:
	LD	E,(IY + 4)		; FIRST CONFIG BYTE TO E
	LD	D,(IY + 5)		; SECOND CONFIG BYTE TO D
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE

SIO_DEVICE:
	LD	D,CIODEV_SIO	; D := DEVICE TYPE
	LD	E,(IY)		; E := PHYSICAL UNIT
	XOR	A		; SIGNAL SUCCESS
	RET

SIO_INITDEV:
        XOR     A               ; SIGNAL SUCCESS
        RET

; Note: bug in assembler causes .ds to not generate output, thus screwing up
;   offsets in the binary. Do a DW 75 times to yield 150 bytes.

;serABuf:	.ds	SER_BUFSIZE	; SIO A Serial buffer
serABuf:        .DW     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                .DW     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                .DW     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
serAInPtr	.DW	00h
serARdPtr	.DW	00h
serABufUsed	.DB	00h
;serBBuf:	.ds	SER_BUFSIZE	; SIO B Serial buffer
serBBuf         .DW     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                .DW     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                .DW     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
serBInPtr	.DW	00h
serBRdPtr	.DW	00h
serBBufUsed	.DB	00h

serAInMask      .EQU     serAInPtr&$FF
serBInMask      .EQU     serBInPtr&$FF

; configuration block
SIO_CFG_A       .DB     0
                .DB	0				; SIO TYPE
                .DB	SIOA_D				; IO PORT BASE (RBR, THR)
                .DB	SIOA_C       			; LINE STATUS PORT (LSR)
                .DW	DEFSERCFG			; LINE CONFIGURATION
                .FILL	2,$FF				; FILLER

SIO_CFG_B       .DB     1
                .DB	0				; SIO TYPE
                .DB	SIOB_D       			; IO PORT BASE (RBR, THR)
                .DB	SIOB_C       			; LINE STATUS PORT (LSR)
                .DW	DEFSERCFG			; LINE CONFIGURATION
                .FILL	2,$FF				; FILLER
