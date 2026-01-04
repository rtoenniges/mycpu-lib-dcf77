;
; Robin Toenniges 2026
;
; FARPTR __fastcall__ dcf_start( void );
; void __fastcall__ dcf_stop( void );
; void __fastcall__ dcf_regHandler( void *ptr );
; void dcf_startHandler( void );
; void dcf_deleteHandler( void );

        .import     k_libselect, k_libdeselect, k_libcall, k_libunload
		.export     _dcf_start, _dcf_stop, _dcf_regHandler, _dcf_startHandler, _dcf_deleteHandler

        .importzp   sreg, tmp1, tmp2


REG_ROMPAGE = $3900

.bss
libHandler:   .res 1

.code

_dcf_start:
       ;Load/Set DCF Library
       JSR setDcfLib
	   
	   ;Get ROM-Page
	   LDA #0Ah
	   JSR k_libcall
       STA tmp1 ;libROMP
	   
	   ;Get Struct-Pointer and RAM-Page
	   LDA #0Bh
	   JSR k_libcall
	   STA tmp2 ;libRAMP
	   TYA
	   SAX
	   JMP makeFarPtr

_dcf_stop:
       ;Stop and delete Application Handler
	   LDA #60h
	   JSR k_libunload
       RTS


_dcf_regHandler:
	   PHA ;PTR low
	   PHX ;PTR high
	   
	   ;Select DCF Library
       JSR setDcfLib

	   ;Register Application Handler
	   LDA #0Ch
	   PLY ;PTR high
	   PLX ;PTR low
	   SEC
	   JSR k_libcall
	   STAA libHandler
       RTS

_dcf_startHandler:
       ;Select DCF Library
       JSR setDcfLib

	   ;Tell ROM-Page and Start Application Handler
	   LDA #0Dh
	   LDXA libHandler
	   LDY REG_ROMPAGE
	   JSR k_libcall
       RTS

_dcf_deleteHandler:
       ;Select DCF Library
       JSR setDcfLib

	   ;Stop and delete Application Handler
	   LDA #0Ch
	   LDXA libHandler
	   JSR k_libcall
       RTS
       

makeFarPtr:   ;input: AX=16bit addr, output: 32bit addr
        LDY  tmp2 ;libRAMP
        STY  sreg
        LDY  tmp1 ;libROMP
        STY  sreg+1
        RTS
		
setDcfLib:
       ;Load Library
       LDA #60h
	   JSR k_libselect
	   RTS