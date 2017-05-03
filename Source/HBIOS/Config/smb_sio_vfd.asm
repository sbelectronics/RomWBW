; SMB with SIO/2 and VFD

FDMEDIA         .EQU    FDM144          ; FDM720, FDM144, FDM360, FDM120 (ONLY RELEVANT IF FDENABLE = TRUE)
FDMEDIAALT      .EQU    FDM720          ; ALTERNATE MEDIA TO TRY, SAME CHOICES AS ABOVE (ONLY RELEVANT IF FDMAUTO = TRUE)
FDMAUTO         .EQU    TRUE            ; SELECT BETWEEN MEDIA OPTS ABOVE AUTOMATICALLY

FDSPECIAL       .EQU    FALSE           ; Use special mode instead oF AT/ESA mode

VFDTERMENABLE   .EQU    TRUE	; Enable VFD Terminal

ASCIENABLE      .EQU    FALSE           ; TRUE FOR Z180 ASCI SUPPORT

ACIAENABLE      .EQU    FALSE            ; Z80 ACIA Enable
SIOENABLE       .EQU    TRUE            ; Z80 SIO/2 Enable
INTTYPE         .EQU    IT_Z80IM2       ; INTERRUPT HANDLING TYPE (IT_NONE, IT_SIMH, IT_Z180, IT_CTC, ...)
