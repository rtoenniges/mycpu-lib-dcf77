;[ASCII]
;******************************************
;****  DCF77 Library - Test program *******
;******************************************
;******  by Robin Tönniges (2016)  ********
;******************************************

;***********************************************
;*Parameter:
;*Nothing = Set system clock with DCF77 - Data
;*Number 1-7 = Display data set 1-7 from the library
;*Number 8 = Display current time and date
;*
;*
;*
;***********************************************

;Include
#include <program.hsm>
#include <ctype.hsm> 
#include <conio.hsm> 
#include <time.hsm> 
#include <code.hsm> 

;Declare variables
DCF77LIB        EQU 60h

ZP_paramPtr     EQU 00h

STR_done        DB "System clock successfully set!",0
STR_fault       DB "Receiver not synchronized or data incomplete!",0

VAR_seconds     DB 0
VAR_minutes     DB 0
VAR_hours       DB 0
VAR_day         DB 0
VAR_month       DB 0
VAR_year        DB 0


;--------------------------------------------------------- 
;Main program  
;---------------------------------------------------------
codestart

main    
        FLG ZP_paramPtr ;Initialize zeropointer

;Get parameter from console
skipPar LPA
        JPZ setSysTime
        CMP #20h
        JNZ skipPar

_skp0   SPT ZP_paramPtr
        LPA
        JPZ setSysTime  ;No parameter -> set system clock
        CMP #20h
        JPZ _skp0
        
        LPT ZP_paramPtr
        JSR (KERN_STRING2NUMBER)
        CMP #8
        JPZ printTime   ;Parameter '8' -> print date/time
        PHA   

;Parameter 0-7 -> Print data from library        
        LDA #DCF77LIB
        JSR  (KERN_LIBSELECT)        
        PLA
        JSR (KERN_LIBCALL)
        JPC printFault
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        CLA
        RTS

setSysTime
        LDA #DCF77LIB
        JSR  (KERN_LIBSELECT) 
        LDA #1 ;Seconds
        JSR (KERN_LIBCALL)
        JPC printFault
        STAA VAR_seconds
        LDA #2 ;Minutes
        JSR (KERN_LIBCALL)
        JPC printFault
        STAA VAR_minutes
        LDA #3 ;Hours
        JSR (KERN_LIBCALL)
        JPC printFault
        STAA VAR_hours
        LDA #4 ;Day
        JSR (KERN_LIBCALL)
        JPC printFault
        STAA VAR_day
        LDA #6 ;Month
        JSR (KERN_LIBCALL)
        JPC printFault
        STAA VAR_month
        LDA #7 ;Year
        JSR (KERN_LIBCALL)
        JPC printFault
        STAA VAR_year
        
        ;Set system clock
        LDAA VAR_hours
        LDXA VAR_minutes
        LDYA VAR_seconds
        SEC
        JSR (KERN_GETSETTIME)
        
        LDAA VAR_day
        LDXA VAR_month
        LDYA VAR_year
        SEC
        JSR (KERN_GETSETDATE)
        
        LPT #STR_done
        JSR (KERN_PRINTSTR)
        CLA
        RTS
        
printTime
        LDA #DCF77LIB
        JSR  (KERN_LIBSELECT) 
        LDA #3 ;Hours
        JSR (KERN_LIBCALL)
        JPC printFault
        JSR leadingZero
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        LDA #':'
        JSR (KERN_PRINTCHAR)
        LDA #2 ;Minutes
        JSR (KERN_LIBCALL)
        JPC printFault
        JSR leadingZero
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        LDA #':'
        JSR (KERN_PRINTCHAR)
        LDA #1 ;Seconds
        JSR (KERN_LIBCALL)
        JPC printFault
        JSR leadingZero
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        LDA #13
        JSR (KERN_PRINTCHAR)
        LDA #4 ;Day
        JSR (KERN_LIBCALL)
        JPC printFault
        JSR leadingZero
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        LDA #'.'
        JSR (KERN_PRINTCHAR)
        LDA #6 ;Month
        JSR (KERN_LIBCALL)
        JPC printFault
        JSR leadingZero
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        LDA #'.'
        JSR (KERN_PRINTCHAR)
        LDA #7 ;Year
        JSR (KERN_LIBCALL)
        JPC printFault
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        CLA
        RTS


;--------------------------------------------------------- 
;Helper functions   
;---------------------------------------------------------

;Print leading zero for date and time <10
leadingZero
        PHA
        CLC
        SBC #9
        JPC lz_0 
        LDA #'0'
        JSR (KERN_PRINTCHAR)
        PLA ;<10
        RTS
lz_0    PLA ;>9
        RTS

        
printFault
        LPT #STR_fault
        JSR (KERN_PRINTSTR)
        
_RTS    CLA
        RTS