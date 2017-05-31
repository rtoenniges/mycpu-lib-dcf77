;[ASCII]
;******************************************
;***********  DCF77 Library  **************
;******************************************
;******  by Robin Tönniges (2017)  ********
;******************************************

#include <sys.hsm>
#include <library.hsm>
#include <code.hsm>
#include <interrupt.hsm>

;Comment this line out if you dont want synced status on Multi-I/O-LEDs
#DEFINE SYNC_DISP 
;Comment this line in if you use the SCC-Rack-Extension
;#DEFINE SCC_BOARD 

;-------------------------------------;
; declare variables

;Zeropointer
ZP_temp1            EQU  10h

;Addresses
HDW_INT             EQU 7       ;IRQ7
HDW_SCC_BOARD       EQU 3000h   ;Address of SCC board
KERN_IOCHANGELED    EQU 0306h   ;Kernel routine for changing the Multi-I/O-LEDs

;Decoding parameter
PARAM_LOWHIGH       SET 4       ;Edge time < PARAM_LOWHIGH = 0(Low), >= PARAM_LOWHIGH = 1(High)
PARAM_SYNCPAUSE     SET 40      ;Edge time < PARAM_SYNCPAUSE = New second/bit, >= PARAM_SYNCPAUSE = Syncpoint
PARAM_SECOND        SET 20      ;Edge time < PARAM_SECOND = New bit, >= PARAM_SECOND = New second
PARAM_IGNORE        SET 1       ;Edge time < PARAM_IGNORE = Signal interference (ignore)

;Variables
FLG_dcfReceiver     DB  1   ;This flag is set to 1 if input comes from the DCF77-Receiver
FLG_synced          DB  1   ;Sync flag -> 0 if synchron with dcf77
VAR_edgeCnt         DB  0   ;Edge counter
VAR_dataOK          DB  0   ;Parity check -> Bit 1 = Minutes OK, Bit 2 = Hours OK, Bit 3 = Date OK

VAR_pSecond         DB  0   ;Pseudo second to bridge desynchronization
VAR_second          DB  0   ;DCF77-Second/Bit counter

;Time variables initialized with FFh to "lock" Get-functions until 2nd synchronization point reached
VAR_minutes         DB  FFh
VAR_hours           DB  FFh

VAR_day             DB  FFh
VAR_weekday         DB  FFh
VAR_month           DB  FFh
VAR_year            DB  FFh

VAR_dateParity      DB  0

VAR_tmpMinutes      DB  0
VAR_tmpHours        DB  0
VAR_tmpDay          DB  0
VAR_tmpWeekday      DB  0
VAR_tmpMonth        DB  0
VAR_tmpYear         DB  0
VAR_ledsDataOK      DB  0

VAR_timerhandle     DB  0   ;Address of timer interrupt handle



;-------------------------------------;
; begin of assembly code

codestart
#include <library.hsm>
;--------------------------------------------------------- 
;Library handling  
;---------------------------------------------------------  

;Library initialization
;---------------------------------------------------------   
initfunc

;Initialize zeropage variables
            FLG  ZP_temp1   ;Time between two interrupts (Value * 1/30.517578Hz)s 
            FLG  ZP_temp1+1 ;Temporary data
        
;Enable hardware interrupt (IRQ7)
            LDA  #HDW_INT
            LPT  #int_dcf77
            JSR  (KERN_IC_SETVECTOR)
            JSR  (KERN_IC_ENABLEINT)
        
;Enable timer interrupt
            CLA    
            LPT  #int_timer
            JSR  (KERN_MULTIPLEX)
            STAA VAR_timerhandle  ;Save adress of timerhandle  

;If sync display enabled clear LEDs 
#IFDEF SYNC_DISP
            CLA
            JSR (KERN_IOCHANGELED)
#ENDIF   
            CLA
            RTS
            
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
            CLC
            JSR (KERN_SPINLOCK)
            ;Set LEDs to default
#IFDEF SYNC_DISP
            LDA #0FFh
            JSR (KERN_IOCHANGELED)
#ENDIF
#IFDEF SCC_BOARD
            LDAA HDW_SCC_BOARD
            AND #FBh
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
            JPZ func_getEntryPoint  ;Function 08h
            JMP _failRTS
  
       
;Function '01h' = Get seconds (OUTPUT = Accu), Carry = 0 if successfull
func_getSeconds
            LDAA FLG_synced
            JNZ _failRTS
            LDAA VAR_second
            JMP _RTS

;Function '02h' = Get minutes (OUTPUT = Accu), Carry = 0 if successfull         
func_getMinutes  
            LDAA FLG_synced
            JNZ _failRTS
            LDAA VAR_dataOK
            AND #01h
            JPZ _failRTS
            LDAA VAR_minutes
            CMP #FFh
            JPZ _failRTS
            JMP _RTS
        
;Function '03h' = Get hours (OUTPUT = Accu), Carry = 0 if successfull 
func_getHours
            LDAA FLG_synced
            JNZ _failRTS
            LDAA VAR_dataOK
            AND #02h
            JPZ _failRTS
            LDAA VAR_hours
            CMP #FFh
            JPZ _failRTS
            JMP _RTS        
       
;Function '04h' = Get day (OUTPUT = Accu), Carry = 0 if successfull 
func_getDay
            LDAA FLG_synced
            JNZ _failRTS
            LDAA VAR_dataOK
            AND #04h
            JPZ _failRTS
            LDAA VAR_day
            CMP #FFh
            JPZ _failRTS
            JMP _RTS    
        
;Function '05h' = Get weekday (OUTPUT = Accu), Carry = 0 if successfull 
;1 = monday, 2 = tuesday, 3 = wednesday, 4 = thursday, 5 = friday, 6 = saturday, 7 = sunday
func_getWeekday
            LDAA FLG_synced
            JNZ _failRTS
            LDAA VAR_dataOK
            AND #04h
            JPZ _failRTS
            LDAA VAR_weekday
            CMP #FFh
            JPZ _failRTS
            JMP _RTS   

;Function '06h' = Get month (OUTPUT = Accu), Carry = 0 if successfull 
func_getMonth
            LDAA FLG_synced
            JNZ _failRTS
            LDAA VAR_dataOK
            AND #04h
            JPZ _failRTS
            LDAA VAR_month
            CMP #FFh
            JPZ _failRTS
            JMP _RTS     
        
;Function '07h' = Get year (OUTPUT = Accu), Carry = 0 if successfull 
func_getYear
            LDAA FLG_synced
            JNZ _failRTS
            LDAA VAR_dataOK
            AND #04h
            JPZ _failRTS
            LDAA VAR_year
            CMP #FFh
            JPZ _failRTS
            JMP _RTS

;Function '08h' = Get entrypoint of library         
func_getEntryPoint
            LPT #funcdispatch
            JMP _RTS

;--------------------------------------------------------- 
;Interrupt routines   
;---------------------------------------------------------       
       
;Receiver interrupt        
int_dcf77
            LDA #1 
            STAA FLG_dcfReceiver ;Flank detected -> Set flag
            INCA VAR_edgeCnt ;Count edges (For signal error detection)
            RTS       
        
;Timer interrupt
int_timer
            ;Measure time between two edges
            LDA FLG_dcfReceiver
            JNZ decode       
            INC ZP_temp1
            RTS

;--------------------------------------------------------- 
;DCF77 decoding   
;---------------------------------------------------------
decode 
;From this point no interrupt should break the programm
            SEC
            JSR (KERN_SPINLOCK) ;"You shall not pass"           
            
;Synchronize with signal -> Detect syncpoint/-gap
            LDA ZP_temp1
            CMP #PARAM_SYNCPAUSE  
            JNC _dec0
;Time >= PARAM_SYNCPAUSE -> Time longer than 1 second
;Syncpoint reached
            STZ FLG_synced
            STZ VAR_second
            STZ VAR_edgeCnt
            JMP _decEnd
     
;Time < PARAM_SYNCPAUSE -> New second or bit information     
;Count seconds, Check signal for errors   
_dec0       CMP #PARAM_IGNORE
            JPC _dec1
            DECA VAR_edgeCnt
            JMP _decIgnore
_dec1       CMP #PARAM_SECOND 
            JNC newBit
            ;Time >= PARAM_SECOND -> Next second
            INCA VAR_second  
            JMP _decEnd

;Time < PARAM_SECOND -> New bit 
newBit 
;Display synced status on I/O-Module LEDs
#IFDEF SYNC_DISP
            JSR syncDisp
#ENDIF  
;Display synced status on SCC-Board
#IFDEF SCC_BOARD
            JSR sccBoard
#ENDIF  
;First do signal checking -> Twice as many edges+1 as seconds?
            LDAA VAR_edgeCnt
            SEC
            SBC #1
            DIV #2
            CMPA VAR_second
            JPZ _nBit0 ;Check successfull -> Go forward to bit checking
            
;No longer synchronized        
deSync  
            LDA #1 
            STAA FLG_synced
            STZ VAR_dataOK
            LDA #08
            STAA VAR_ledsDataOK
            JMP _decEnd
  
;Decode bit     
_nBit0      LDAA FLG_synced
            JNZ _decEnd
            ;Only continue if synchronized
          
            LDAA VAR_second
            JNZ _nBit3
            JSR getBit
            JNZ deSync ;If Bit 0 != 0 -> Not synchronized or incorrect signal
            
;Second/bit = 0 -> Take over data from last minute            
            LDAA VAR_dataOK
            AND #01h
            JPZ _nBit1
            LDAA VAR_tmpMinutes ;Take over 'minutes'
            STAA VAR_minutes
_nBit1      LDAA VAR_dataOK
            AND #02h
            JPZ _nBit2
            LDAA VAR_tmpHours ;Take over 'hours'
            STAA VAR_hours
_nBit2      LDAA VAR_dataOK
            AND #04h
            JPZ _decEnd
            LDAA VAR_tmpWeekday ;Take over 'weekday'
            STAA VAR_weekday
            LDAA VAR_tmpDay ;Take over 'day'
            STAA VAR_day
            LDAA VAR_tmpMonth ;Take over 'month'
            STAA VAR_month
            LDAA VAR_tmpYear ;Take over 'year'
            STAA VAR_year
            JMP _decEnd
        
_nBit3      CMP #20
            JNC _decEnd ;Below bit 20 is nothing important
            JNZ _nBit4
            JSR getBit; Second/bit = 20 -> Begin of time information always '1'
            JPZ deSync ;If Bit 20 != 1 -> Not synchronized or incorrect signal
            JMP _decEnd
 
;Bit >20 - Get/decode data
_nBit4      LDAA VAR_second
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
            JNZ _decEnd
            ;Second = 59 -> Leap second!
            JSR getBit ;Always '0'
            JNZ deSync 
            JMP _decEnd

;Get/decode minutes
;---------------------------------------------------------
getMinutes   
            CMP #28
            JPZ parityMinutes ;Last bit -> Check parity
            CMP #21
            JNZ _gMin0
            MOV ZP_temp1+1,#0 ;First bit -> Clear data

;Get bit (minutes)
_gMin0      JSR getBit
            ORA ZP_temp1+1
            SHR
            STA ZP_temp1+1
            JMP _decEnd

;Last bit
;Check parity (minutes)        
parityMinutes  
            JSR getBit ;Get "Carry-Bit" and save it to stack for later use
            PHA
            ;Determine if bitcount of data is even or odd
            LDA ZP_temp1+1
            LDX #7
            CLY
            JSR bitCnt
            JPC _pMin0   
            PLA ;Bit count = "odd"
            JNZ _pMinOK
        
_pMinBAD    LDA #06h ;Parity n.OK
            ANDA VAR_dataOK
            STAA VAR_dataOK
            JMP _decEnd
        
_pMin0      PLA ;Bit count = "even"
            JNZ _pMinBAD
        
_pMinOK     LDA ZP_temp1+1 ;Parity OK
            JSR bcdToDec
            STAA VAR_tmpMinutes
            LDA #01h
            ORAA VAR_dataOK
            STAA VAR_dataOK
            JMP _decEnd
        
    
;Get/decode hours
;---------------------------------------------------------
getHours
            CMP #35
            JPZ parityHours ;Last bit -> Check parity
            CMP #29
            JNZ _gHrs0
            MOV ZP_temp1+1,#0 ;First Bit -> Clear data

;Get bit (hours)
_gHrs0      JSR getBit
            ORA ZP_temp1+1
            SHR
            STA ZP_temp1+1 
            JMP _decEnd

;Last bit
;Check parity (hours)         
parityHours       
            SHR ZP_temp1+1 ;Shift data right by 1
            
            JSR getBit ;Get "Carry-Bit" and save it to stack for later use
            PHA
            ;Determine if bitcount of data is even or odd
            LDA ZP_temp1+1  
            LDX #6
            CLY
            JSR bitCnt
            JPC _pHrs0   
            PLA ;Bit count = "odd"
            JNZ _pHrsOK
            
_pHrsBAD    LDA #05h ;Parity n.OK
            ANDA VAR_dataOK
            STAA VAR_dataOK
            JMP _decEnd
            
_pHrs0      PLA ;Bit count = "even"
            JNZ _pHrsBAD
            
_pHrsOK     LDA ZP_temp1+1 ;Parity OK
            JSR bcdToDec
            STAA VAR_tmpHours
            LDA #02h
            ORAA VAR_dataOK
            STAA VAR_dataOK
            JMP _decEnd
                
        
;Get/decode day
;---------------------------------------------------------
getDay  
            CMP #36 
            JNZ _gDay0
            MOV ZP_temp1+1,#0 ;First Bit -> Clear data
  
;Get bit (day)      
_gDay0      JSR getBit
            ORA ZP_temp1+1
            SHR
            STA ZP_temp1+1  
            ;Check for last bit
            LDAA VAR_second
            CMP #41       
            JNZ _decEnd 
            
            
;Last bit
            SHR ZP_temp1+1 ;Shift data right by 1 
    
            ;Count high bits and add it to "VAR_dateParity"
            LDA ZP_temp1+1  
            LDX #6
            CLY
            JSR bitCnt
            STAA VAR_dateParity
            ;Save day value
            LDA ZP_temp1+1
            JSR bcdToDec
            STAA VAR_tmpDay
            JMP _decEnd        
        
        
;Get/decode weekday
;---------------------------------------------------------
getWDay 
            CMP #42
            JNZ _getWDay0
            MOV ZP_temp1+1,#0 ;First Bit -> Clear data
    
;Get bit (weekday)    
_getWDay0   JSR getBit
            ORA ZP_temp1+1
            SHR
            STA ZP_temp1+1 
            ;Check for last bit
            LDAA VAR_second
            CMP #44       
            JNZ _decEnd
 
;Last bit
            ;Shift data right by 4
            LDA ZP_temp1+1 
            DIV #10h
            STA ZP_temp1+1 
            
            ;Count high bits and add it to "VAR_dateParity"
            LDX #3
            LDYA VAR_dateParity
            JSR bitCnt
            STAA VAR_dateParity
            ;Save weekday value
            LDA ZP_temp1+1 
            JSR bcdToDec
            STAA VAR_tmpWeekday
            JMP _decEnd  
        
        
;Get/decode month
;---------------------------------------------------------
getMonth    
            CMP #45
            JNZ _gMon0
            MOV ZP_temp1+1 ,#0 ;First Bit -> Clear data
        
;Get bit (month)
_gMon0      JSR getBit
            ORA ZP_temp1+1 
            SHR
            STA ZP_temp1+1  
            ;Check for last bit
            LDAA VAR_second
            CMP #49       
            JNZ _decEnd 
            
;Last bit
            ;Shift data right by 2
            SHR ZP_temp1+1   
            SHR ZP_temp1+1  
            
            ;Count high bits and add it to "VAR_dateParity"
            LDA ZP_temp1+1   
            LDX #5
            LDYA VAR_dateParity
            JSR bitCnt
            STAA VAR_dateParity
            ;Save month value
            LDA ZP_temp1+1 
            JSR bcdToDec
            STAA VAR_tmpMonth
            JMP _decEnd 
        
;Get/decode year
;---------------------------------------------------------
getYear     
            CMP #58
            JPZ parityDate ;Last bit -> Check parity
            CMP #50
            JNZ _gYear0
            MOV ZP_temp1+1 ,#0 ;First Bit -> Clear data

;Get bit (year)
_gYear0     SHR ZP_temp1+1 
            JSR getBit
            ORA ZP_temp1+1 
            STA ZP_temp1+1  
            JMP _decEnd

;Last bit
;Check parity for whole date (Day, weekday, month, year)         
parityDate
            JSR getBit ;Get "Carry-Bit" and save it to stack for later use
            PHA
            ;Count high bits and add it to "VAR_dateParity"
            ;Determine if bitcount of "VAR_dateParity" is even or odd
            LDA ZP_temp1+1 
            LDX #8
            LDYA VAR_dateParity
            JSR bitCnt
            JPC _pDat0
            PLA ;Bit count = "odd" 
            JNZ _pDateOK
            
_pDateBAD   LDA #03h ;Partity n.OK
            ANDA VAR_dataOK
            STAA VAR_dataOK
            JMP _decEnd
            
_pDat0      PLA ;Bit count = "even"
            JNZ _pDateBAD
            
_pDateOK    LDA ZP_temp1+1  ;Parity OK
            JSR bcdToDec
            STAA VAR_tmpYear ;Save year value
            LDA #04h
            ORAA VAR_dataOK
            STAA VAR_dataOK
            JMP _decEnd
            
  
;Ready for next bit
_decEnd     STZ FLG_dcfReceiver ;Reset dcf77 interrupt flag 
            MOV ZP_temp1, #0 ;Reset Edge time
            CLC
            JSR (KERN_SPINLOCK) ;Enable the interrupts again
            RTS

;Interference detected -> continue counting            
_decIgnore  STZ FLG_dcfReceiver ;Reset dcf77 interrupt flag 
            CLC
            JSR (KERN_SPINLOCK) ;Enable the interrupts again
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
            LDA ZP_temp1
            CMP #PARAM_LOWHIGH
            JNC _gBit0
            ;Time >= PARAM_LOWHIGH -> Bit = 1
            LDA #80h
            SKA
_gBit0      CLA ;Time < PARAM_LOWHIGH -> Bit = 0
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
VAR_tmpConvert  DB  0      
bcdToDec
            PHA
            DIV #10h
            MUL #0Ah
            STA ZP_temp1+1
            PLA
            AND #0Fh
            CLC
            ADC ZP_temp1+1
            RTS
            

_RTS    
            CLC
            RTS
      
_failRTS
            CLA
            SEC
            RTS
        
