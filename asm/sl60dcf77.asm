;[ASCII]
;******************************************
;***********  DCF77 Library  **************
;******************************************
;******  by Robin Tönniges (2016)  ********
;******************************************

#include <sys.hsm>
#include <library.hsm>
#include <code.hsm>
#include <interrupt.hsm>


;-------------------------------------;
; declare variables

;Zeropointer
ZP_temp1        EQU  10h
ZP_temp2        EQU  12h

;Constants
CON_INT         EQU 7   ;IRQ7

;Variables
VAR_second      DB  0   ;Second/Bit counter
VAR_flankcnt    DB  0   ;Flank counter
VAR_synced      DB  1   ;Sync flag -> 0 if synchronized
VAR_dataok      DB  0   ;Parity check -> Bit 1 = Minutes OK, Bit 2 = Hours OK, Bit 3 = Date OK

VAR_minutes     DB  0
VAR_hours       DB  0
VAR_day         DB  0
VAR_weekday     DB  0
VAR_month       DB  0
VAR_year        DB  0
VAR_dateparity  DB  0

VAR_tmpminutes  DB  0
VAR_tmphours    DB  0
VAR_tmpday      DB  0
VAR_tmpweekday  DB  0
VAR_tmpmonth    DB  0

VAR_timerhandle DB  0   ;Address of timerinterrupt-handle

;-------------------------------------;
; begin of assembly code

codestart
#include <library.hsm>

initfunc
;Enable hardware-interrupt (IRQ7)
        LDA  #CON_INT
        LPT  #dcf77
        JSR  (KERN_IC_SETVECTOR)
        JSR  (KERN_IC_ENABLEINT)
        
;Enable timer-interrupt
        CLA    
        LPT  #timer
        JSR  (KERN_MULTIPLEX)
        STAA VAR_timerhandle  ;Adresse des Timer Handlers in Variable speichern

;Initialize zeropage variables
        FLG  ZP_temp1   ;Hardware-interrupt flag
        FLG  ZP_temp1+1 ;Time between two flanks (Value * 1/30.517578Hz)
        FLG  ZP_temp2   ;Temp data
        FLG  ZP_temp2+1 ;Reserve       
        CLA
        RTS
               
termfunc  
        ;Disable timer-interrupt
        LDA  #1
        LDXA VAR_timerhandle      
        JSR (KERN_MULTIPLEX)
        ;Disable hardware-interrupt
        LDA #CON_INT
        JSR (KERN_IC_DISABLEINT)
        RTS
     
funcdispatch
        DEC
        JPZ func_getSeconds     ;Function 01h  
        DEC 
        JPZ func_getMinutes     ;Function 02h         
        DEC 
        JPZ func_getHours       ;Function 03h 
        DEC 
        JPZ func_getDay         ;Function 04h   
        DEC 
        JPZ func_getWeekday     ;Function 05h       
        DEC 
        JPZ func_getMonth       ;Function 06h      
        DEC 
        JPZ func_getYear        ;Function 07h 
        DEC 
        JPZ func_getEntryPoint  ;Function 08h
        JMP _failRTS
        
        
;Function '01h' = Get seconds (OUTPUT = Accu), Carry = 0 if successfull
func_getSeconds
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_second
        JMP _RTS

;Function '02h' = Get minutes (OUTPUT = Accu), Carry = 0 if successfull         
func_getMinutes  
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_minutes
        JMP _RTS
        
;Function '03h' = Get hours (OUTPUT = Accu), Carry = 0 if successfull 
func_getHours
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_hours
        JMP _RTS        
       
;Function '04h' = Get day (OUTPUT = Accu), Carry = 0 if successfull 
func_getDay
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_day
        JMP _RTS    
        
;Function '05h' = Get weekday (OUTPUT = Accu), Carry = 0 if successfull 
;1 = monday, 2 = tuesday, 3 = wednesday, 4 = thursday, 5 = friday, 6 = saturday, 7 = sunday
func_getWeekday
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_weekday
        JMP _RTS   

;Function '06h' = Get month (OUTPUT = Accu), Carry = 0 if successfull 
func_getMonth
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_month
        JMP _RTS     
        
;Function '07h' = Get year (OUTPUT = Accu), Carry = 0 if successfull 
func_getYear
        LDAA VAR_synced
        JNZ _failRTS
        LDAA VAR_dataok
        CMP #7
        JNZ _failRTS
        LDAA VAR_year
        JMP _RTS

;Function '08h' = Get entrypoint of library         
func_getEntryPoint
        LPT #funcdispatch
        JMP _RTS

;--------------------------------------------------------- 
;Interrupt routines   
;---------------------------------------------------------       
       
;Receiver interrupt        
dcf77
        MOV ZP_temp1, #1    ;Flank detected -> Set flag
        INCA VAR_flankcnt   ;Count flanks (For signal-error-detection)
        RTS       
        
;Timer interrupt
timer
        LDA ZP_temp1
        JNZ impCtrl       
        ;Measure time between two flanks
        INC ZP_temp1+1
        RTS

;--------------------------------------------------------- 
;DCF77 decoding   
;---------------------------------------------------------

;Synchronize with signal -> Detect 59th second
impCtrl 
        CLC
        LDA ZP_temp1+1
        SBC #50  
        JNC imp_1
        ;Flanktime >= 50 -> Time longer than 1 second
;Signal synchron
        CLA 
        STAA VAR_synced
        STAA VAR_second
        STAA VAR_flankcnt
        JMP imp_end
     
;Count seconds, Check signal for errors   
imp_1   CLC
        LDA ZP_temp1+1
        SBC #20  
        JNC imp_2 ;Flanktime < 20 -> Next bit
        ;Flanktime >= 20 -> Next second
        INCA VAR_second
        ;Signal checking -> Twice as many flanks as seconds?
        LDAA VAR_flankcnt
        DIV #2
        CMPA VAR_second
        JPZ imp_end
;No longer synchronized        
DeSync  LDA #1 
        STAA VAR_synced
        CLA
        STAA VAR_dataok
        JMP imp_end
        
;Determine datapackets
imp_2   LDAA VAR_second
        CMP #20 ;Begin of time information = 1
        JNZ imp_3
        LDA ZP_temp1+1
        JSR getBit
        JPZ DeSync ;Bit 20 != 1 -> No longer synchronized or incorrect signal
        JMP imp_end 
 
imp_3   LDAA VAR_synced
        JNZ imp_end
        ;Only continue if synchronized
        CLC
        LDAA VAR_second
        SBC #20
        JNC imp_end 
        ;Second >= 21
        CLC
        LDAA VAR_second
        SBC #28
        JNC imp_4 ;Go to minute decoding
        ;Second >= 29
        CLC
        LDAA VAR_second
        SBC #35
        JNC imp_7 ;Go to hour decoding
        ;Second >= 36
        CLC
        LDAA VAR_second
        SBC #41
        JNC imp_10 ;Go to day decoding
        ;Second >= 42
        CLC
        LDAA VAR_second
        SBC #44
        JNC imp_12 ;Go to weekday decoding
        ;Second >= 45
        CLC
        LDAA VAR_second
        SBC #49
        JNC imp_14 ;Go to month decoding
        ;Second >= 50
        CLC
        LDAA VAR_second
        SBC #58
        JNC imp_16 ;Go to year decoding
        ;Second >= 59
        JMP imp_end

;---------------------------------------------------------

;Decode minutes
imp_4   LDAA VAR_second
        CMP #21
        JNZ imp_6
        MOV ZP_temp2, #0

;Get bit
imp_6   LDA ZP_temp1+1
        JSR getBit
        PHA
        LDAA VAR_second
        CMP #28
        JPZ imp_5 ;Last bit -> Check parity
        PLA
        ORA ZP_temp2
        SHR
        STA ZP_temp2
        JMP imp_end

;Check parity        
imp_5   LDA ZP_temp2  
        LDX #7
        CLY
        JSR bitCnt
        JPC par_0   
        PLA ;Bit count = "unequal"
        JNZ par_1
        LDA #1
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_0   PLA ;Bit count = "equal"
        JPZ par_1
        LDA #1
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_1   LDA ZP_temp2 ;Parity OK
        JSR bcdToDec
        STAA VAR_tmpminutes
        LDA #1
        ORAA VAR_dataok
        STAA VAR_dataok
        JMP imp_end

    
;Decode hours
imp_7   LDAA VAR_second
        CMP #29
        JNZ imp_9
        MOV ZP_temp2, #0

;Get
imp_9   LDA ZP_temp1+1
        JSR getBit
        PHA
        LDAA VAR_second
        CMP #35
        JPZ imp_8 ;Last bit -> Check parity
        PLA
        ORA ZP_temp2
        SHR
        STA ZP_temp2 
        JMP imp_end

;Check parity         
imp_8   SHR ZP_temp2 ;Shift hour-byte right by 1
        LDA ZP_temp2  
        LDX #6
        CLY
        JSR bitCnt
        JPC par_2   
        PLA ;Bit count = "unqual"
        JNZ par_3
        LDA #2
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_2   PLA ;Bit count = "equal"
        JPZ par_3
        LDA #2
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_3   LDA ZP_temp2 ;Parity OK
        JSR bcdToDec
        STAA VAR_tmphours
        LDA #2
        ORAA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
        
        
;Decode day
imp_10  LDAA VAR_second
        CMP #36
        JNZ imp_11
        MOV ZP_temp2, #0
  
;Get bit      
imp_11  LDA ZP_temp1+1
        JSR getBit
        ORA ZP_temp2
        SHR
        STA ZP_temp2  
      
;Count high bits
        LDAA VAR_second
        CMP #41       
        JNZ imp_end 
        SHR ZP_temp2 ;Shift day-byte right by 1
        LDA ZP_temp2  
        LDX #6
        CLY
        JSR bitCnt
        STAA VAR_dateparity
        LDA ZP_temp2
        JSR bcdToDec
        STAA VAR_tmpday
        JMP imp_end        
        
        
;Decode weekday
imp_12  LDAA VAR_second
        CMP #42
        JNZ imp_13
        MOV ZP_temp2, #0
        
imp_13  LDA ZP_temp1+1
        JSR getBit
        ORA ZP_temp2
        SHR
        STA ZP_temp2       
;Count high bits
        LDAA VAR_second
        CMP #44       
        JNZ imp_end 
        ;Shift weekday-byte right by 4
        LDA ZP_temp2 
        DIV #10h
        STA ZP_temp2 
        LDX #3
        LDYA VAR_dateparity
        JSR bitCnt
        STAA VAR_dateparity
        LDA ZP_temp2
        JSR bcdToDec
        STAA VAR_tmpweekday
        JMP imp_end  
        
;Decode month
imp_14  LDAA VAR_second
        CMP #45
        JNZ imp_15
        MOV ZP_temp2, #0
        
;Get bit 
imp_15  LDA ZP_temp1+1
        JSR getBit
        ORA ZP_temp2
        SHR
        STA ZP_temp2 
        
;Count high bits
        LDAA VAR_second
        CMP #49       
        JNZ imp_end 
        ;Shift month-byte right by 2
        SHR ZP_temp2  
        SHR ZP_temp2  
        LDA ZP_temp2  
        LDX #5
        LDYA VAR_dateparity
        JSR bitCnt
        STAA VAR_dateparity
        LDA ZP_temp2
        JSR bcdToDec
        STAA VAR_tmpmonth
        JMP imp_end 
        
;Decode year
imp_16  LDAA VAR_second
        CMP #50
        JNZ imp_18
        MOV ZP_temp2, #0

;Get bit
imp_18  LDA ZP_temp1+1
        JSR getBit
        PHA
        LDAA VAR_second
        CMP #58
        JPZ imp_17 ;Last bit -> Check parity
        PLA
        ORA ZP_temp2
        SHR
        STA ZP_temp2 
        JMP imp_end

;Check parity for whole date (Day, weekday, month, year)         
imp_17  SHL ZP_temp2 ;Shift year-byte left by 1
        LDA ZP_temp2
        LDX #8
        LDYA VAR_dateparity
        JSR bitCnt
        JPC par_4   
        PLA ;Bit count = "unqual"
        JNZ par_5
        LDA #4
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_4   PLA ;Bit count = "equal"
        JPZ par_5
        LDA #4
        EORA VAR_dataok
        STAA VAR_dataok
        JMP imp_end
par_5   LDA ZP_temp2 ;Parity OK
        JSR bcdToDec ;Take over 'year'
        STAA VAR_year
        LDAA VAR_tmpminutes ;Take over 'minutes'
        STAA VAR_minutes
        LDAA VAR_tmphours ;Take over 'hours'
        STAA VAR_hours
        LDAA VAR_tmpday ;Take over 'day'
        STAA VAR_day
        LDAA VAR_tmpweekday ;Take over 'weekday'
        STAA VAR_weekday
        LDAA VAR_tmpmonth ;Take over 'month'
        STAA VAR_month
        LDA #4
        ORAA VAR_dataok
        STAA VAR_dataok
      
;Wait for next flank
imp_end
        MOV ZP_temp1, #0
        MOV ZP_temp1+1, #0
        RTS

;--------------------------------------------------------- 
;Helper functions   
;---------------------------------------------------------

;Get bit information from Flanktime (Input: A = Flanktime) (Output: A = High(80h), Low(00h))        
getBit
        CLC       
        SBC #3
        JNC get_0
        ;Flanktime >= 3 -> Bit = 1
        LDA #80h
        RTS
get_0   CLA ;Flanktime < 3 -> Bit = 0
        RTS
        
        
;Count high bits
;Input: A = Byte, X = Number of bits Bits, Y=Counter offset
;Output: A = Counter value, Carry = 0 -> unequal, Carry = 1 -> equal
bitCnt
cnt_0   SHR
        JNC cnt_1
        INY
cnt_1   DXJP cnt_0
        SAY
        PHA
        MOD #2
        JPZ cnt_2
        CLC ;Counter value "unequal"
        JMP cnt_3
cnt_2   SEC ;Counter value "equal"
cnt_3   PLA
        RTS
        
        
;Translate BCD in decimal (Input: A = BCD value) (Output: A = decimal vlaue)       
bcdToDec
        PHA
        DIV #10h
        MUL #0Ah
        STA ZP_temp2
        PLA
        AND #0Fh
        CLC
        ADC ZP_temp2
        STA ZP_temp2
        RTS

_RTS    
        CLC
        RTS
      
_failRTS
        CLA
        SEC
        RTS
        
