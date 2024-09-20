;[ASCII]
;******************************************
;***********  DCF77 Library  **************
;******************************************
;***** by Robin Tönniges (2016-2024) ******
;******************************************

#include <sys.hsm>
#include <code.hsm>
#include <interrupt.hsm>
#include <time.hsm> 
#include <mem.hsm> 

;Comment this line out if you dont want synced status on Multi-I/O-LEDs
#DEFINE SYNC_DISP 
;Comment this line in if you use the SCC-Rack-Extension
;#DEFINE SCC_BOARD 
;Comment this line in if library should load on higher ROM-Page
;#DEFINE HIGH_ROM 
;Comment this line in if you want debug output
;#DEFINE DEBUG

;Debug Message
;Second[MeteoCount1|MeteoCount2]: BitLevel(PulseTime) {Additional comments}
;Example: 28[28|49]: H(6) Minute: 32

ORG 8000h
 DW 8002h
 DW initfunc
 DW termfunc
 DW codestart
;-------------------------------------;
; declare variables

;Addresses
HDW_INT             EQU 7       ;IRQ7

#IFDEF SCC_BOARD
HDW_SCC_BOARD       EQU 3000h   ;Address of SCC board
#ENDIF

#IFDEF SYNC_DISP
KERN_IOCHANGELED    EQU 0306h   ;Kernel routine for changing the Multi-I/O-LEDs
#ENDIF

;Decoding parameter
;Low        = 100ms         is theoretically 3
;High       = 200ms         is theoretically 6
;Syncpause  = 1800-1900ms   is theoretically 54-57
;New second = 800-900ms     is theoretically 24-27
PARAM_LOWHIGH       SET 5       ;Edge time < PARAM_LOWHIGH      = 0(Low),           >= PARAM_LOWHIGH    = 1(High)
PARAM_SYNCPAUSE     SET 50      ;Edge time < PARAM_SYNCPAUSE    = New second/bit,   >= PARAM_SYNCPAUSE  = Syncpoint
PARAM_SECOND        SET 20      ;Edge time < PARAM_SECOND       = New bit,          >= PARAM_SECOND     = New second
PARAM_IGNORE        SET 2       ;Edge time < PARAM_IGNORE       = Signal interference (ignore)

;Variables
FLG_firstStart      DB  1   ;This flag indicates first start of library -> Ignore first edge
FLG_dcfReceiver     DW  0   ;This flag is set to 1 if new input (rising edge) comes from the DCF77-Receiver
                            ;FLG_dcfReceiver+1 is set to 1 if bit is ready for decoding
FLG_synced          DB  1   ;Sync flag -> 0 if synchron with dcf77
VAR_bitCount        DB  0   ;Timer Interrupt Counter
VAR_bitCache        DW  0   ;Byte 0 = time value, Byte 1 = temp value
VAR_edgeCnt         DB  0   ;Edge counter
VAR_dataOK          DB  0   ;Parity check -> Bit 1 = Minutes OK, Bit 2 = Hours OK, Bit 3 = Date OK, Bit 4 = Meteo OK

;VAR_pSecond         DB  0   ;Pseudo second to bridge desynchronization
VAR_second          DB  0   ;DCF77-Second/Bit counter

;Time variables initialized with FFh to "lock" Get-functions until 2nd synchronization point reached
VAR_minutes         DB  0FFh
VAR_hours           DB  0FFh

VAR_day             DB  0FFh
VAR_weekday         DB  0FFh
VAR_month           DB  0FFh
VAR_year            DB  0FFh

VAR_dateParity      DB  0

;2x 82 Bit + 0 (Little endian)
VAR_meteo1          DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ;Weather bits n
                    DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ;Weather bits n+1
                        ;******* Minute *******|********* Hour *********|********* Day **********|**** Month ****|*** WD **|******** Year *********|
                    DB  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0
                    DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ;Weather bits n+2

VAR_meteo2          DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                    DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                    DB  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0
                    DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                    
ZP_meteoWrite       EQU 20h ;Write pointer for meteo data
ZP_meteoRead        EQU 22h ;Read pointer for meteo data
VAR_meteoCount1     DB  0 ;Weather bit counter (0-41)
VAR_meteoCount2     DB  0 ;Time bit counter (42-81)

VAR_tmpMinutes      DB  0
VAR_tmpHours        DB  0
VAR_tmpDay          DB  0
VAR_tmpWeekday      DB  0
VAR_tmpMonth        DB  0
VAR_tmpYear         DB  0
VAR_ledsDataOK      DB  0

VAR_timerhandle     DB  0   ;Address of timer interrupt handle

#IFDEF DEBUG
#include <conio.hsm> 
STR_sync            DB "Sync pause detected!",0
STR_interference    DB "Interference detected!",0
STR_lost_sync       DB "Synchronization lost!",0
STR_minute_fail     DB "Minute: Bad Parity!",0
STR_hour_fail       DB "Hour: Bad Parity!",0
STR_date_fail       DB "Date: Bad Parity!",0
STR_meteo           DB "Meteo: ",0
STR_minute          DB "Minute: ",0
STR_hour            DB "Hour: ",0
STR_day             DB "Day: ",0
STR_weekday         DB "Weekday: ",0
STR_month           DB "Month: ",0
STR_year            DB "Year: ",0
#ENDIF 

;-------------------------------------;
; begin of assembly code

codestart
;--------------------------------------------------------- 
;Library handling  
;---------------------------------------------------------  


;Library initialization
;---------------------------------------------------------   
initfunc
            ORA #0
            JNZ funcdispatch
            CLC
            JSR (KERN_ISLOADED)
            CLA
            JPC _RTS
            
;Initialize Zeropointer
            FLG ZP_meteoWrite
            FLG ZP_meteoWrite+1
            FLG ZP_meteoRead
            FLG ZP_meteoRead+1

#IFDEF HIGH_ROM
            ;move this program to a separate memory page
            LPT  #codestart
            LDA  #0Eh
            JSR  (KERN_MULTIPLEX)  ;may fail on older kernel
#ENDIF

            LPT #VAR_meteo1
            SPT ZP_meteoRead
            LPT #VAR_meteo2
            SPT ZP_meteoWrite

;Enable hardware interrupt (IRQ7)
            LDA #HDW_INT
            LPT #int_dcf77
            JSR (KERN_IC_SETVECTOR)
            JSR (KERN_IC_ENABLEINT)
        
;Enable timer interrupt
            CLA    
            LPT #int_timer
            JSR (KERN_MULTIPLEX)
            STAA VAR_timerhandle  ;Save adress of timerhandle 

;Register idle function
            SEC
            LPT #int_idle
            JSR (KERN_SETIDLEFUNC)

;If sync display enabled clear LEDs 
#IFDEF SYNC_DISP
            CLA
            JSR (KERN_IOCHANGELED)
#ENDIF   
            CLA
            JMP (KERN_EXITTSR)
            
;Termination function
;---------------------------------------------------------                  
termfunc  
            ;Disable timer-interrupt
            LDA  #1
            LDXA VAR_timerhandle      
            JSR (KERN_MULTIPLEX)
            ;Disable hardware-interrupt
            LDA #HDW_INT
            JSR (KERN_IC_DISABLEINT)
            ;Disable spinlock
            ;CLC
            ;JSR (KERN_SPINLOCK)
            ;Disable idle function
            CLC
            LPT #int_idle
            JSR (KERN_SETIDLEFUNC)

#IFDEF SYNC_DISP
            ;Set LEDs to default
            LDA #0FFh
            JSR (KERN_IOCHANGELED)
#ENDIF

#IFDEF SCC_BOARD
            LDAA HDW_SCC_BOARD
            AND #0FBh
            STAA HDW_SCC_BOARD
#ENDIF 
            RTS

;Functiondispatch
;---------------------------------------------------------     
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
            JPZ func_getMeteoTime   ;Function 08h
            DEC 
            JPZ func_getEntryPoint  ;Function 09h
            DEC
            JPZ func_getROMPage     ;Function 0Ah
            JMP _failRTS
  
       
;Function '01h' = Get seconds (OUTPUT = Accu), Carry = 0 if successfull
func_getSeconds
            LDAA FLG_synced
            JNZ _failRTS
            LDAA VAR_second
            JMP _RTS

;Function '02h' = Get minutes (OUTPUT = Accu), Carry = 0 if successfull         
func_getMinutes  
            LDAA VAR_dataOK
            AND #01h
            JPZ _failRTS
            LDAA VAR_minutes
            CMP #0FFh
            JPZ _failRTS
            JMP _RTS
        
;Function '03h' = Get hours (OUTPUT = Accu), Carry = 0 if successfull 
func_getHours
            LDAA VAR_dataOK
            AND #02h
            JPZ _failRTS
            LDAA VAR_hours
            CMP #0FFh
            JPZ _failRTS
            JMP _RTS        
       
;Function '04h' = Get day (OUTPUT = Accu), Carry = 0 if successfull 
func_getDay
            LDAA VAR_dataOK
            AND #04h
            JPZ _failRTS
            LDAA VAR_day
            CMP #0FFh
            JPZ _failRTS
            JMP _RTS    
        
;Function '05h' = Get weekday (OUTPUT = Accu), Carry = 0 if successfull 
;1 = monday, 2 = tuesday, 3 = wednesday, 4 = thursday, 5 = friday, 6 = saturday, 7 = sunday
func_getWeekday
            LDAA VAR_dataOK
            AND #04h
            JPZ _failRTS
            LDAA VAR_weekday
            CMP #0FFh
            JPZ _failRTS
            JMP _RTS   

;Function '06h' = Get month (OUTPUT = Accu), Carry = 0 if successfull 
func_getMonth
            LDAA VAR_dataOK
            AND #04h
            JPZ _failRTS
            LDAA VAR_month
            CMP #0FFh
            JPZ _failRTS
            JMP _RTS     
        
;Function '07h' = Get year (OUTPUT = Accu), Carry = 0 if successfull 
func_getYear
            LDAA VAR_dataOK
            AND #04h
            JPZ _failRTS
            LDAA VAR_year
            CMP #0FFh
            JPZ _failRTS
            JMP _RTS
            
;Function '08h' = Get encoded METEO Information (X/Y = Pointer to string), Carry = 0 if successfull
;Bit 0-41 = meteotime (3 minutes)
;Bit 42-81 = time information (Minutes + Hours + Day + Month + Weekday + Year) without parity
func_getMeteoTime
            LDAA VAR_dataOK
            AND #08h
            JPZ _failRTS
            LPT ZP_meteoRead
            JMP _RTS

;Function '09h' = Get entrypoint of library         
func_getEntryPoint
            LPT #funcdispatch
            JMP _RTS

;Function '0Ah' = Get ROM-Page of library
func_getROMPage
            LDAA REG_ROMPAGE
            JMP _RTS

;--------------------------------------------------------- 
;Interrupt routines   
;---------------------------------------------------------       
       
;BEGIN - Receiver interrupt
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>    
int_dcf77
            ;First start?
            LDAA FLG_firstStart
            JPZ _rInt0
            STZA FLG_firstStart
            RTS

            ;Check for interference
            LDAA VAR_bitCount
            CMP #PARAM_IGNORE
            JPC _rInt0
            ;Interference detected -> Ignore

;DEBUG print interference            
#IFDEF DEBUG
    LDA #13 ;\r
    JSR (KERN_PRINTCHAR)
    LPT #STR_interference
    JSR (KERN_PRINTSTR)
#ENDIF

            RTS

_rInt0      LDA #1 
            STAA FLG_dcfReceiver ;Flank detected -> Set flag (Pause timer count)
            INCA VAR_edgeCnt ;Count edges (For signal error detection)
            LDAA VAR_bitCount
            STAA VAR_bitCache ;Move bitCounter to cache
            STZA VAR_bitCount
            STZA FLG_dcfReceiver ;Resume timer count
            
            ;LDAA VAR_bitCache 
            CMP #PARAM_SYNCPAUSE ;Synchronize with signal -> Detect syncpoint/-gap
            JNC _rInt2
            ;Time >= PARAM_SYNCPAUSE -> Time longer than 1 second
            ;Syncpoint reached
            STZA FLG_synced
            STZA VAR_second
            STZA VAR_edgeCnt
            
#IFDEF DEBUG
    LDA #13 ;\r
    JSR (KERN_PRINTCHAR)
    LPT #STR_sync
    JSR (KERN_PRINTSTR)
#ENDIF

            RTS

;Time < PARAM_SYNCPAUSE          
_rInt2      CMP #PARAM_SECOND 
            JNC _rInt3
            INCA VAR_second ;Time >= PARAM_SECOND -> Next second
            RTS

;Time < PARAM_SECOND -> New bit
_rInt3      LDAA VAR_edgeCnt ;First do signal checking -> Twice as many edges+1 as seconds?
            SEC
            SBC #1
            DIV #2
            CMPA VAR_second
            JPZ _rInt4 ;Check successfull -> Go forward to bit checking
            
;No longer synchronized        
deSync  
            LDA #1 
            STAA FLG_synced
            STZA VAR_dataOK
            LDA #08
            STAA VAR_ledsDataOK
            STZA VAR_second
            STZA VAR_meteoCount1
            STZA VAR_meteoCount2
  
;New bit -> Ready for decode   
_rInt4      LDA #1
            STAA FLG_dcfReceiver+1
                              
;DEBUG print desynchronisation            
#IFDEF DEBUG
    LDAA FLG_synced
    JPZ _RTS
    LDA #13 ;\r
    JSR (KERN_PRINTCHAR)
    LPT #STR_lost_sync
    JSR (KERN_PRINTSTR)
#ENDIF 

            RTS


;END - Receiver interrupt
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<


  
;BEGIN - Timer interrupt 30.51757813 times per second
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 
int_timer
            ;Measure time between two edges
            LDAA FLG_dcfReceiver
            JNZ _RTS       
            INCA VAR_bitCount
            RTS
;END - Timer interrupt
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



;BEGIN - Idle function (Bit decoding)
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 
int_idle
            LDAA FLG_dcfReceiver+1
            JPZ _RTS
            STZA FLG_dcfReceiver+1 ;Get ready for new bit immediately
;--------------------------------------------------------- 
;DCF77 decoding   
;---------------------------------------------------------

;From this point no interrupt should break the programm
            ;SEC
            ;JSR (KERN_SPINLOCK) ;"You shall not pass"                       

;New bit received
;---------------------------------------------------------
;Display synced status on I/O-Module LEDs
#IFDEF SYNC_DISP
        JSR syncDisp
#ENDIF  
;Display synced status on SCC-Board
#IFDEF SCC_BOARD
        JSR sccBoard
#ENDIF  

            LDAA FLG_synced
            JNZ _RTS

;DEBUG print time measurement and bit information
#IFDEF DEBUG
        LDA #13 ;\r
        JSR (KERN_PRINTCHAR)
        LDAA VAR_second
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        LDA #'['
        JSR (KERN_PRINTCHAR) 
        LDAA VAR_meteoCount1
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        LDA #'|'
        JSR (KERN_PRINTCHAR) 
        LDAA VAR_meteoCount2
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        LDA #']'
        JSR (KERN_PRINTCHAR) 
        LDA #':'
        JSR (KERN_PRINTCHAR)
        LDA #' '
        JSR (KERN_PRINTCHAR)
        
        JSR getBit
        CMP #80h
        JNZ _dbg0
        LDA #'H'
        JMP _dbg1
_dbg0   LDA #'L'
_dbg1   JSR (KERN_PRINTCHAR) 
        LDA #'('
        JSR (KERN_PRINTCHAR) 
        
        LDAA VAR_bitCache
        CLX
        CLY
        JSR (KERN_PRINTDEZ)
        
        LDA #')'
        JSR (KERN_PRINTCHAR) 
#ENDIF 

            LDAA VAR_second
            JNZ _nBit3
            JSR getBit
            JNZ deSync ;If Bit 0 != 0 -> Not synchronized or incorrect signal
            
;Second/bit = 0 -> Take over data from last minute    
            LDAA FLG_synced
            JNZ _RTS
            LDAA VAR_second
            TAY            
_nBit0      LDAA VAR_dataOK
            AND #01h
            JPZ _nBit1
            LDAA VAR_tmpMinutes ;Take over 'minutes'
            STAA VAR_minutes
            TAX
_nBit1      LDAA VAR_dataOK
            AND #02h
            JPZ _nBit2
            LDAA VAR_tmpHours ;Take over 'hours'
            STAA VAR_hours
            ;Set system time
            PHA
            LDAA VAR_dataOK
            AND #03h
            CMP #03h
            JNZ _RTS
            PLA
            CPY #0
            JNZ _nBit2 ;Sync every minute at xx:xx:00
            SEC
            JSR (KERN_GETSETTIME)
            
_nBit2      LDAA VAR_dataOK
            AND #04h
            JPZ _RTS
            LDAA VAR_tmpYear ;Take over 'year'
            STAA VAR_year
            TAY
            LDAA VAR_tmpMonth ;Take over 'month'
            STAA VAR_month
            TAX
            LDAA VAR_tmpWeekday ;Take over 'weekday'
            STAA VAR_weekday
            LDAA VAR_tmpDay ;Take over 'day'
            STAA VAR_day
            ;Set system date
            PHA
            LDAA VAR_second
            CMP #0
            JNZ _RTS ;Sync every minute at xx:xx:00
            PLA
            SEC
            JSR (KERN_GETSETDATE)

            JMP _RTS

;Bit > 0        
_nBit3      CMP #20
            JNZ _nBit4
            JSR getBit ;Second/bit = 20 -> Begin of time information always '1'
            JPZ deSync ;If Bit 20 != 1 -> Not synchronized or incorrect signal
            JMP _RTS
 
;Bit != 20 - Get/decode data
_nBit4      LDAA VAR_second
            CMP #15
            JNC getMeteo ;Go to meteo
            ;Second >= 15
            CMP #21
            JNC _RTS ; Ignore bit 15-20
            ;Second >= 21
            CMP #29
            JNC getMinutes ;Go to minute decoding
            ;Second >= 29
            CMP #36
            JNC getHours ;Go to hour decoding
            ;Second >= 36
            CMP #42
            JNC getDay ;Go to day decoding
            ;Second >= 42
            CMP #45
            JNC getWDay ;Go to weekday decoding
            ;Second >= 45
            CMP #50
            JNC getMonth ;Go to month decoding
            ;Second >= 50
            CMP #59
            JNC getYear ;Go to year decoding
            ;Second >= 59
            JNZ _RTS
            ;Second = 59 -> Leap second!
            JSR getBit ;Always '0'
            JNZ deSync 
            JMP _RTS


;Get/decode meteotime
;---------------------------------------------------------
getMeteo    
            JSR func_getMinutes
            JPC _gMet12 ;No minute data available -> Skip meteo section
            MOD #3
            JPZ _gMet10 ;//Check for start minute -> = 0, 3, 6, 9, ...
            ;Minute -> n+1 or n+2
            LDAA VAR_meteoCount1
            CMP #14
            JNC _RTS ;Previous data not complete
            TAX
            JSR getBitChar
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount1        
            TXA
            CMP #41
            JNZ _RTS
            ;Last bit received
            CLA
            LDX #82
            STA (ZP_meteoWrite),X ;Terminate String with 0
            LDA #08h
            ORAA VAR_dataOK
            STAA VAR_dataOK
            LPT ZP_meteoRead ;Swap read and write register
            PHR
            LPT ZP_meteoWrite
            SPT ZP_meteoRead
            PLR
            SPT ZP_meteoWrite

;DEBUG print meteo string
#IFDEF DEBUG
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_meteo
    JSR (KERN_PRINTSTR)
    LPT ZP_meteoRead
    JSR (KERN_PRINTSTR)
#ENDIF


_gMet12     STZA VAR_meteoCount1 ;Reset bit counter
            STZA VAR_meteoCount2 ;Reset bit counter            
            JMP _RTS    
            
_gMet10     LDAA VAR_second ;Start minute (0, 3, 6, 9, ...)
            CMP #1
            JNZ _gMet11 ;Bit > 1 -> Write to Array
            STZA VAR_meteoCount1 ;First minute & first bit -> Reset bit counter
            STZA VAR_meteoCount2 ;First minute & first bit -> Reset bit counter
_gMet11     JSR getBitChar
            LDXA VAR_meteoCount1
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount1
            JMP _RTS        


;Get/decode minutes
;---------------------------------------------------------
getMinutes   
            CMP #28
            JPZ _gMet21 ;Last bit -> Check parity
            CMP #21
            JNZ _gMet20
            STZA VAR_bitCache+1    ;First bit -> Clear data
            LDAA VAR_meteoCount1
            CMP #28
            JNZ _gMin0 ;Previous meteo data not complete
            LDA #42
            STAA VAR_meteoCount2

;*** Get meteo 1/2 ***
_gMet20     LDAA VAR_meteoCount1
            CMP #28
            JNZ _gMin0 ;Previous meteo data not complete
            JSR getBitChar
            LDXA VAR_meteoCount2
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount2

;Get bit (minutes)
_gMin0      JSR getBit
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1
            JMP _RTS

;*** Get meteo 2/2 ***
_gMet21     LDAA VAR_meteoCount2
            CMP #49
            JNZ parityMinutes ;Previous meteo data not complete
            TAX
            LDA #'0'
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount2

;Last bit
;Check parity (minutes)        
parityMinutes  
            JSR getBit ;Get "Carry-Bit" and save it to stack for later use
            PHA
            ;Determine if bitcount of data is even or odd
            LDAA VAR_bitCache+1
            LDX #7
            CLY
            JSR bitCnt
            JPC _pMin0   
            PLA ;Bit count = "odd"
            JNZ _pMinOK
        
_pMinBAD    LDA #00Eh ;Parity n.OK
            ANDA VAR_dataOK
            STAA VAR_dataOK

;DEBUG print minutes parity failure            
#IFDEF DEBUG
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_minute_fail
    JSR (KERN_PRINTSTR)
#ENDIF 

            JMP _RTS
        
_pMin0      PLA ;Bit count = "even"
            JNZ _pMinBAD
        
_pMinOK     LDAA VAR_bitCache+1
            JSR bcdToDec
            STAA VAR_tmpMinutes
            LDA #01h
            ORAA VAR_dataOK
            STAA VAR_dataOK


;DEBUG print minutes
#IFDEF DEBUG 
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_minute
    JSR (KERN_PRINTSTR)
    LDAA VAR_tmpMinutes
    CLX
    CLY
    JSR (KERN_PRINTDEZ)
#ENDIF 
            JMP _RTS
        
    
;Get/decode hours
;---------------------------------------------------------
getHours
            CMP #35
            JPZ _gMet31 ;Last bit -> Check parity
            CMP #29
            JNZ _gMet30
            STZA VAR_bitCache+1

;*** Get meteo 1/2 ***
_gMet30     LDAA VAR_meteoCount1
            CMP #28
            JNZ _gHrs0 ;Previous meteo data not complete
            JSR getBitChar
            LDXA VAR_meteoCount2
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount2

;Get bit (hours)
_gHrs0      JSR getBit
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1
            JMP _RTS

;*** Get meteo 2/2 ***
_gMet31     LDAA VAR_meteoCount2
            CMP #56
            JNZ parityHours ;Previous meteo data not complete
            TAX
            LDA #'0'
            STA (ZP_meteoWrite),X ; 1. '0'
            INX
            STA (ZP_meteoWrite),X ; 2. '0'
            INX
            STXA VAR_meteoCount2

;Last bit
;Check parity (hours)         
parityHours       
            SHRA VAR_bitCache+1
            JSR getBit ;Get "Carry-Bit" and save it to stack for later use
            PHA
            ;Determine if bitcount of data is even or odd
            LDAA VAR_bitCache+1
            LDX #6
            CLY
            JSR bitCnt
            JPC _pHrs0   
            PLA ;Bit count = "odd"
            JNZ _pHrsOK
            
_pHrsBAD    LDA #00Dh ;Parity n.OK
            ANDA VAR_dataOK
            STAA VAR_dataOK

;DEBUG print hours parity failure            
#IFDEF DEBUG
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_hour_fail
    JSR (KERN_PRINTSTR)
#ENDIF 

            JMP _RTS
            
_pHrs0      PLA ;Bit count = "even"
            JNZ _pHrsBAD
            
_pHrsOK     LDAA VAR_bitCache+1
            JSR bcdToDec
            STAA VAR_tmpHours
            LDA #02h
            ORAA VAR_dataOK
            STAA VAR_dataOK

;DEBUG print hours
#IFDEF DEBUG 
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_hour
    JSR (KERN_PRINTSTR)
    LDAA VAR_tmpHours
    CLX
    CLY
    JSR (KERN_PRINTDEZ)
#ENDIF 
            JMP _RTS
                
        
;Get/decode day
;---------------------------------------------------------
getDay  
            CMP #36 
            JNZ _gMet40
            STZA VAR_bitCache+1

;*** Get meteo 1/2 ***
_gMet40     LDAA VAR_meteoCount1
            CMP #28
            JNZ _gDay0 ;Previous meteo data not complete
            JSR getBitChar
            LDXA VAR_meteoCount2
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount2
  
;Get bit (day)      
_gDay0      JSR getBit
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1
            ;Check for last bit
            LDAA VAR_second
            CMP #41       
            JNZ _RTS 

;*** Get meteo 2/2 ***
            LDAA VAR_meteoCount2
            CMP #64
            JNZ _gDay1 ;Previous meteo data not complete
            TAX
            LDA #'0'
            STA (ZP_meteoWrite),X ; 1. '0'
            INX
            STA (ZP_meteoWrite),X ; 2. '0'
            LDA #71
            STAA VAR_meteoCount2          
            
;Last bit
_gDay1      SHRA VAR_bitCache+1
            ;Count high bits and add it to "VAR_dateParity"
            LDAA VAR_bitCache+1
            LDX #6
            CLY
            JSR bitCnt
            STAA VAR_dateParity
            ;Save day value
            LDAA VAR_bitCache+1
            JSR bcdToDec
            STAA VAR_tmpDay
            
;DEBUG print day
#IFDEF DEBUG 
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_day
    JSR (KERN_PRINTSTR)
    LDAA VAR_tmpDay
    CLX
    CLY
    JSR (KERN_PRINTDEZ)
#ENDIF 
            JMP _RTS        
        
        
;Get/decode weekday
;---------------------------------------------------------
getWDay 
            CMP #42
            JNZ _gMet50
            STZA VAR_bitCache+1

;*** Get meteo 1/2 ***
_gMet50     LDAA VAR_meteoCount1
            CMP #28
            JNZ _getWDay0 ;Previous meteo data not complete
            JSR getBitChar
            LDXA VAR_meteoCount2
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount2

;Get bit (weekday)    
_getWDay0   JSR getBit
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1
            ;Check for last bit
            LDAA VAR_second
            CMP #44       
            JNZ _RTS

;*** Get meteo 2/2 ***
            LDAA VAR_meteoCount2
            CMP #74
            JNZ _getWDay1 ;Previous meteo data not complete
            LDA #66
            STAA VAR_meteoCount2
 
;Last bit
            ;Shift data right by 4
_getWDay1   LDAA VAR_bitCache+1
            DIV #10h
            STAA VAR_bitCache+1
            
            ;Count high bits and add it to "VAR_dateParity"
            LDX #3
            LDYA VAR_dateParity
            JSR bitCnt
            STAA VAR_dateParity
            ;Save weekday value
            LDAA VAR_bitCache+1
            JSR bcdToDec
            STAA VAR_tmpWeekday

;DEBUG print weekday
#IFDEF DEBUG 
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_weekday
    JSR (KERN_PRINTSTR)
    LDAA VAR_tmpWeekday
    CLX
    CLY
    JSR (KERN_PRINTDEZ)
#ENDIF 

            JMP _RTS  
        
        
;Get/decode month
;---------------------------------------------------------
getMonth    
            CMP #45
            JNZ _gMet60
            STZA VAR_bitCache+1

;*** Get meteo ***
_gMet60     LDAA VAR_meteoCount1
            CMP #28
            JNZ _gMon0 ;Previous meteo data not complete
            JSR getBitChar
            LDXA VAR_meteoCount2
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount2
        
;Get bit (month)
_gMon0      JSR getBit
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1            
            ;Check for last bit
            LDAA VAR_second
            CMP #49       
            JNZ _RTS 

;*** Get meteo 2/2 ***
            LDAA VAR_meteoCount2
            CMP #71
            JNZ _gMon1 ;Previous meteo data not complete
            LDA #74
            STAA VAR_meteoCount2
            
;Last bit
            ;Shift data right by 2
_gMon1      SHRA VAR_bitCache+1
            SHRA VAR_bitCache+1
            
            ;Count high bits and add it to "VAR_dateParity"
            LDAA VAR_bitCache+1
            LDX #5
            LDYA VAR_dateParity
            JSR bitCnt
            STAA VAR_dateParity
            ;Save month value
            LDAA VAR_bitCache+1
            JSR bcdToDec
            STAA VAR_tmpMonth

;DEBUG print month
#IFDEF DEBUG 
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_month
    JSR (KERN_PRINTSTR)
    LDAA VAR_tmpMonth
    CLX
    CLY
    JSR (KERN_PRINTDEZ)
#ENDIF 

            JMP _RTS 
        
;Get/decode year
;---------------------------------------------------------
getYear     
            CMP #58
            JPZ parityDate ;Last bit -> Check parity
            CMP #50
            JNZ _gMet70
            STZA VAR_bitCache+1

;*** Get meteo ***
_gMet70     LDAA VAR_meteoCount1
            CMP #28
            JNZ _gYear0 ;Previous data not complete
            JSR getBitChar
            LDXA VAR_meteoCount2
            STA (ZP_meteoWrite),X
            INCA VAR_meteoCount2

;Get bit (year)
_gYear0     SHRA VAR_bitCache+1
            JSR getBit
            ORAA VAR_bitCache+1
            STAA VAR_bitCache+1
            JMP _RTS

;Last bit
;Check parity for whole date (Day, weekday, month, year)         
parityDate
            JSR getBit ;Get "Carry-Bit" and save it to stack for later use
            PHA
            ;Count high bits and add it to "VAR_dateParity"
            ;Determine if bitcount of "VAR_dateParity" is even or odd
            LDAA VAR_bitCache+1
            LDX #8
            LDYA VAR_dateParity
            JSR bitCnt
            JPC _pDat0
            PLA ;Bit count = "odd" 
            JNZ _pDateOK
            
_pDateBAD   LDA #00Bh ;Partity n.OK
            ANDA VAR_dataOK
            STAA VAR_dataOK

;DEBUG print hours parity failure            
#IFDEF DEBUG
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_date_fail
    JSR (KERN_PRINTSTR)
#ENDIF

            JMP _RTS
            
_pDat0      PLA ;Bit count = "even"
            JNZ _pDateBAD
            
_pDateOK    LDAA VAR_bitCache+1
            JSR bcdToDec
            STAA VAR_tmpYear ;Save year value
            LDA #04h
            ORAA VAR_dataOK
            STAA VAR_dataOK

;DEBUG print year
#IFDEF DEBUG 
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_year
    JSR (KERN_PRINTSTR)
    LDAA VAR_tmpYear
    CLX
    CLY
    JSR (KERN_PRINTDEZ)
#ENDIF 

            JMP _RTS
            
            
;Decoding end
;---------------------------------------------------------

;DEBUG print interference sign
#IFDEF DEBUG 
    LDA #13 ;\r
    JSR (KERN_PRINTCHAR)
    LPT #STR_interference
    JSR (KERN_PRINTSTR)
#ENDIF 
            RTS
            
;--------------------------------------------------------- 
;Display snyc/data status on Multi-I/O LEDs   
;---------------------------------------------------------
#IFDEF SYNC_DISP
syncDisp
;Display synced status           
            LDAA FLG_synced
            JPZ _syncD0
            LDA #08h 
            EORA VAR_ledsDataOK
            STAA VAR_ledsDataOK
            JMP _syncD4
_syncD0     LDA #08h 
            ORAA VAR_ledsDataOK
            STAA VAR_ledsDataOK
            
            LDAA VAR_second
            CMP #21
            JNC _syncD4 ;Second <21 -> No time information fetching
            CMP #29
            JNC _syncD1 ;Second >= 21 & <29 -> Fetching minutes
            CMP #36
            JNC _syncD2 ;Second >= 29 & < 36 -> Fetching hours
            CMP #59
            JNC _syncD3 ;Second >= 36 & < 59 -> Fetching date
            JMP _syncD4
            
;Fetching minutes
_syncD1     LDAA VAR_dataOK
            AND #01h
            JNZ _syncD4
            LDA #01h 
            EORA VAR_ledsDataOK
            STAA VAR_ledsDataOK
            JMP _syncD4
            
;Fetching hours
_syncD2     LDAA VAR_dataOK
            AND #02h
            JNZ _syncD4
            LDA #02h 
            EORA VAR_ledsDataOK
            STAA VAR_ledsDataOK
            JMP _syncD4
            
;Fetching date 
_syncD3     LDAA VAR_dataOK
            AND #04h
            JNZ _syncD4
            LDA #04h 
            EORA VAR_ledsDataOK
            STAA VAR_ledsDataOK

_syncD4     LDAA VAR_dataOK
            ORAA VAR_ledsDataOK
            JSR (KERN_IOCHANGELED)
            RTS
        
#ENDIF

;--------------------------------------------------------- 
;Display snyc/data status on SCC-Board   
;---------------------------------------------------------
#IFDEF SCC_BOARD
sccBoard
;Receiver not synced (LED off)           
            LDAA FLG_synced
            JPZ _sccB0
            LDAA HDW_SCC_BOARD
            AND #04h
            JPZ _RTS
            LDAA HDW_SCC_BOARD
            EOR #04h
            STAA HDW_SCC_BOARD
            RTS
            
;Receiver synced but no data available (Toggle LED)
_sccB0      LDAA VAR_dataOK
            AND #07h
            CMP #07h
            JPZ _sccB1
            LDAA HDW_SCC_BOARD
            EOR #04h
            STAA HDW_SCC_BOARD
            RTS
   
;Receiver synced and data available (LED on)         
_sccB1      LDAA HDW_SCC_BOARD
            ORA #04h
            STAA HDW_SCC_BOARD
            RTS     
#ENDIF

;--------------------------------------------------------- 
;Helper functions   
;---------------------------------------------------------

;Get bit information from Time (Output: A = High(80h), Low(00h))        
getBit      
            LDAA VAR_bitCache
            CMP #PARAM_LOWHIGH
            JNC _gBit0
            ;Time >= PARAM_LOWHIGH -> Bit = 1
            LDA #80h
            SKA
_gBit0      CLA ;Time < PARAM_LOWHIGH -> Bit = 0
            RTS
        
;Get bit information from Time as Char (Output: A = Char)        
getBitChar      
            LDAA VAR_bitCache
            CMP #PARAM_LOWHIGH
            JNC _gBitC0
            ;Time >= PARAM_LOWHIGH -> Bit = 1
            LDA #'1'
            SKB
_gBitC0     LDA #'0' ;Time < PARAM_LOWHIGH -> Bit = 0
            RTS
        
       

    
;Count high bits
;Input: A = Byte, X = Number of bits, Y = Counter offset
;Output: A = Counter value, Carry = 0 -> odd, Carry = 1 -> even
bitCnt
_bCnt0      SHR
            JNC _bCnt1
            INY
_bCnt1      DXJP _bCnt0
            SAY
            PHA
            MOD #2
            JPZ _bCnt2
            CLC ;Counter value "odd"
            SKA
_bCnt2      SEC ;Counter value "even"
            PLA
            RTS
        
     
;Convert BCD to decimal (Input: A = BCD value) (Output: A = decimal vlaue)      
bcdToDec
            PHA
            DIV #10h
            MUL #00Ah
            STAA VAR_bitCache+1
            PLA
            AND #00Fh
            CLC
            ADCA VAR_bitCache+1
            RTS


_RTS    
            CLC
            RTS
      
_failRTS
            CLA
            SEC
            RTS
        
