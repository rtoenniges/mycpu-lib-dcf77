;[ASCII]
;******************************************
;***********  DCF77 Library  **************
;******************************************
;***** by Robin Toenniges (2016-2025) *****
;******************************************

#include <conio.hsm> 
#include <sys.hsm>
#include <code.hsm>
#include <interrupt.hsm>
#include <time.hsm> 
#include <mem.hsm> 
#include <registers.hsm>

;Comment this line out if you dont want synced status on Multi-I/O-LEDs
#DEFINE SYNC_DISP 
;Comment this line in if you use the SCC-Rack-Extension
#DEFINE SCC_BOARD 
;Comment this line in if library should load on higher ROM-Page
#DEFINE HIGH_ROM 
;Comment this line in if you want debug output
;#DEFINE DEBUG

;Debug Message Format
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
;Low        = 100ms         is theoretically 3 tics
;High       = 200ms         is theoretically 6 tics
;Syncpause  = 1800-1900ms   is theoretically 54-57 tics
;New second = 800-900ms     is theoretically 24-27 tics
PARAM_LOWHIGH       SET 5       ;Edge time < PARAM_LOWHIGH      = 0(Low),           >= PARAM_LOWHIGH    = 1(High)
PARAM_SYNCPAUSE     SET 50      ;Edge time < PARAM_SYNCPAUSE    = New second/bit,   >= PARAM_SYNCPAUSE  = Syncpoint
PARAM_SECOND        SET 20      ;Edge time < PARAM_SECOND       = New bit,          >= PARAM_SECOND     = New second
PARAM_IGNORE        SET 2       ;Edge time < PARAM_IGNORE       = Signal interference (ignore)

;Variables
FLG_firstStart      DB  1   ;This flag indicates first start of library -> Ignore first edge
FLG_dcfReceiver     DB  0   ;This flag is set to 1 if new input (rising edge) comes from the DCF77-Receiver
FLG_startPSecond    DW  0   ;This flag starts the pseudo second (Bit 59) if no leap second was received (Byte 0 = Timer start, Byte 1 = Second reached)
VAR_bitCount        DB  0   ;Timer Interrupt Counter / Count ticks between edges (Low = ~3, High = ~6)
VAR_bitCache        DW  0   ;Byte 0 = time value, Byte 1 = temp value
VAR_edgeCnt         DB  0   ;Edge counter for error checking

VAR_dateParity      DB  0    ;Temp variable for date parity checking

VAR_pSecond         DB  0   ;Pseudo second to bridge desynchronization

;Time variables initialized with FFh to lock "Get-functions" until 2nd synchronization point reached
;*****************
START_DATA_STRUCT
FLG_synced          DB  1   ;00h | Sync flag -> 0 if synchron with dcf77
VAR_dataOK          DB  0   ;01h | Parity check -> Bit 0 = Minutes OK, Bit 1 = Hours OK, Bit 2 = Date OK, Bit 3 = Meteo OK
VAR_bitData         DB  0   ;02h | Bit data '0->00h' or '1->80h' of current second
VAR_addInfo         DB  0, 0, 0, 0, 0   ;03h - 07h | Additional infos 1 or 0 (03h = Callbit, 04h = Switch MEZ/MESZ, 05h = MESZ, 06h = MEZ, 07h = Leap second)

VAR_delay           DB  0   ;08h | delay in seconds/bits
VAR_reserve         DB  0   ;09h | Reserve

VAR_second          DB  0FFh ;0Ah | DCF77-Second/Bit counter
VAR_minutes         DB  0FFh ;0Bh
VAR_hours           DB  0FFh ;0Ch

VAR_day             DB  0FFh ;0Dh
VAR_weekday         DB  0FFh ;0Eh
VAR_month           DB  0FFh ;0Fh
VAR_year            DB  0FFh ;10h   

                    ;11h - 63h
VAR_meteoRead       DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ;Weather bits n
                    DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ;Weather bits n+1
                        ;******* Minute *******|********* Hour *********|********* Day **********|**** Month ****|*** WD **|******** Year *********|
                    DB  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0
                    DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ;Weather bits n+2
END_DATA_STRUCT
;*****************

PAR_DATA_SIZE       EQU END_DATA_STRUCT - START_DATA_STRUCT


VAR_meteoWrite      DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                    DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                    DB  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0
                    DB  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
         
VAR_dataStructPTR   DS  2
    
ZP_dataStructPTR    EQU 10h ;Pointer for Data struct in extra RAM

VAR_meteoCount1     DB  0 ;Weather bit counter for METEO data (0-41)
VAR_meteoCount2     DB  0 ;Time bit counter for METEO data (42-81)

VAR_tmpSecond       DB  0
VAR_tmpMinutes      DB  0
VAR_tmpHours        DB  0
VAR_tmpDay          DB  0
VAR_tmpWeekday      DB  0
VAR_tmpMonth        DB  0
VAR_tmpYear         DB  0
VAR_ledsDataOK      DB  0

VAR_timerhandle     DB  0   ;Address of timer interrupt handle

PAR_HDLMax          SET 6 ;Maximum number of App-Handler
VAR_tabHANDLER      DS  2*PAR_HDLMax  ;Address register for handlers
VAR_tabHDLROMPAGE   DS  PAR_HDLMax ;ROM-Pages from registered handlers
FLG_startHandler    DB  0

VAR_HDLCount        DB  0 ;Number of registered handlers
VAR_HDLbitmaskREG   DB  0,0,0,0,0,0 ;Bitmask of registered handlers
VAR_HDLbitmaskEN    DB  0,0,0,0,0,0 ;Bitmask of enabled handlers
VAR_HDLPTR          DB  0 ;Current active handler

PAR_FIFOsize        SET 24
VAR_FIFOdata        DS  PAR_FIFOsize*2 ;FIFO for second and bit data, in case CPU is busy and idle handler is not called often enough (LOW = second, HIGH = bit)
VAR_FIFOptr         DW  0 ;Pointer for FIFO. 0 = No new data available (Byte 0 = WritePTR, Byte 1 = ReadPTR)

#IFDEF DEBUG
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
        
            ;Reference Zeropointer
            FLG ZP_dataStructPTR
            FLG ZP_dataStructPTR+1        

#IFDEF HIGH_ROM
;Move this program to a separate memory page
            LPT  #codestart
            LDA  #0Eh
            JSR  (KERN_MULTIPLEX)  ;may fail on older kernel
#ENDIF
            
;Allocate RAM for Data-Struct            
            LPT #PAR_DATA_SIZE
            SEC
            JSR (KERN_MALLOCFREE)
            SPTA VAR_dataStructPTR

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
            LDAA VAR_HDLCount
            JPZ _term0
            ;avoid kill of application if still handler registered
            LDA  #12h
            JMP  (KERN_MULTIPLEX)
            
            ;Disable timer-interrupt
_term0      LDA  #1
            LDXA VAR_timerhandle      
            JSR (KERN_MULTIPLEX)
            ;Disable hardware-interrupt
            LDA #HDW_INT
            JSR (KERN_IC_DISABLEINT)
            ;Disable idle function
            CLC
            LPT #int_idle
            JSR (KERN_SETIDLEFUNC)
            ;Free allocated RAM
            CLC
            LPTA VAR_dataStructPTR
            JSR (KERN_MALLOCFREE)

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
            DEC
            JPZ func_getDataStruct  ;Function 0Bh
            DEC
            JPZ func_setHandler     ;Function 0Ch
            DEC
            JPZ func_tellROMPage    ;Function 0Dh
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
            
;Function '08h' = Get encoded METEO Information (X/Y = Pointer to zero terminated string), Carry = 0 if successfull
;TODO: INFO
func_getMeteoTime
            LDAA VAR_dataOK
            AND #08h
            JPZ _failRTS
            LPTA VAR_meteoRead
            JMP _RTS

;Function '09h' = Get entrypoint of library         
func_getEntryPoint
            LPT #funcdispatch
            JMP _RTS

;Function '0Ah' = Get ROM-Page of library
func_getROMPage
            LDAA REG_ROMPAGE
            JMP _RTS

;Function '0Bh' = Get data struct
;X/Y = Pointer to struct in RAM, Accu = RAMPAGE
;   Byte 0 = Sync flag -> 0 if synchron with dcf77
;   Byte 1 = Parity check -> Bit 1 = Minutes OK, Bit 2 = Hours OK, Bit 3 = Date OK, Bit 4 = Meteo OK
;   Byte 2 = Bit data 0 or 1 for current second
;   Byte 3 - 7 = Additional infos 1 or 0 (03h = Callbit, 04h = Switch MEZ/MESZ, 05h = MESZ, 06h = MEZ, 07h = Leap second)
;   Byte 8 = Second
;   Byte 9 = Minute
;   Byte 10 = Hour
;   Byte 11 = Day
;   Byte 12 = Weekday
;   Byte 13 = Month
;   Byte 14 = Year
;   Byte 15 - 97 = Meteo data (Zero terminated bit string)
func_getDataStruct
            LPTA VAR_dataStructPTR
            SAY
            SEC
            SBC #ROMPAGE_RAM0
            SAY
            LDAA REG_ROMPAGE
            INC
            JMP _RTS

;Function '0Ch' = Set/Delete event handler (Triggered after every new bit)
;C(1) = Set new handler -> X/Y = Handler-Address, Accu = Return Handler-No.
;C(0) = Delete handler -> Handler-No. in X-Reg
;Return Carry = 0 if successfull
; -> Function '0Dh' = "Tell ROMPAGE" needs to be called also!
func_setHandler
            JNC _clrHDL0
    
;Set new handler
            TXA
            CLX
            PHA
_setHDL1    LDA VAR_HDLbitmaskREG,X
            JPZ _setHDL0
            INX
            CPX #PAR_HDLMax
            JNC _setHDL1 
            PLA ;Dummy
            JMP _failRTS ;No free handler
           
_setHDL0    TXA
            PLX ;Accu = Handl. Nr., X = Low-Address, Y = High-Address
            PHA
            SHL ;Double handler number (2 Bytes per handler)
            SAX
            STA  VAR_tabHANDLER,X
            STY  VAR_tabHANDLER+1,X
            PLX
            LDA #1
            STA  VAR_HDLbitmaskREG,X
            INCA VAR_HDLCount
            TXA
            INC ;Increment Handler number so it begins with 1
            JMP _RTS
;Delete handler            
_clrHDL0    CLA
            DEX ;Decrement handler number
            STA VAR_HDLbitmaskEN, X ;Disable handler 
            STA VAR_HDLbitmaskREG, X ;Delete handler 
            DECA VAR_HDLCount          
            JMP _RTS


;Function '0Dh' = Tell ROMPAGE to registered handler routine and enable handler
;Handler-No. in X-Register, ROMPAGE-No. in Y-Register
;Return Carry = 0 if successfull
func_tellROMPage
            TYA
            DEX
            STA  VAR_tabHDLROMPAGE,X
            LDA #1
            STA  VAR_HDLbitmaskEN, X
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
            STZA VAR_bitCount
            RTS

            ;Check for interference
_rInt0      LDAA VAR_bitCount
            CMP #PARAM_IGNORE
            JPC _rInt6
            ;Interference detected -> Ignore

;DEBUG print interference            
#IFDEF DEBUG
    LDA #13 ;\r
    JSR (KERN_PRINTCHAR)
    LPT #STR_interference
    JSR (KERN_PRINTSTR)
#ENDIF

            RTS

_rInt6      LDA #1 
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
            STZA FLG_startPSecond
            STZA FLG_startPSecond+1
            STZA VAR_pSecond
            
#IFDEF DEBUG
    LDA #13 ;\r
    JSR (KERN_PRINTCHAR)
    LPT #STR_sync
    JSR (KERN_PRINTSTR)
#ENDIF

            JMP _rInt1

;Time < PARAM_SYNCPAUSE          
_rInt2      CMP #PARAM_SECOND 
            JNC _rInt3
            INCA VAR_second ;Time >= PARAM_SECOND -> Next second
            
;Check for leap second | Add pseudo second 59/60
            LDAA VAR_addInfo+4 ;Leap second at the end of hour?
            JPZ _rInt7
            JSR func_getMinutes
            JPC _rInt7
            CMP #59
            JNZ _rInt7
            LDAA VAR_second
            CMP #59
            JNZ _rInt1
            LDA #1
            STAA FLG_startPSecond
            JMP _rInt1
            
_rInt7      LDAA VAR_second
            CMP #58 ;Start pseudo second 59
            JNZ _rInt1
            LDA #1
            STAA FLG_startPSecond
            JMP _rInt1


;Time < PARAM_SECOND -> New bit
_rInt3      LDAA VAR_edgeCnt ;First do signal checking -> Twice as many edges+1 as seconds?
            SEC
            SBC #1
            SHR
            CMPA VAR_second
            JNZ deSync
            LDA #1 
            STAA FLG_startHandler ;Start App-Handler every new bit
            JMP _rInt4 ;Check successfull -> Go forward to bit checking
            
;No longer synchronized        
deSync  
            LDAA FLG_synced
            JNZ deSync1    ;Skip reset if already desync
            LDA #1 
            STAA FLG_synced
            LDA #1 
            STAA FLG_startHandler ;Start App-Handler to tell we are not synchronized
            LDA #08
            STAA VAR_ledsDataOK
            STZA VAR_dataOK
            STZA VAR_second
            STZA VAR_meteoCount1
            STZA VAR_meteoCount2
            STZA FLG_startPSecond
            STZA FLG_startPSecond+1
            STZA VAR_pSecond
deSync1     JSR _rInt1
            JMP _rInt4
            
            
;1. New second -> add to FIFO
_rInt1      LDAA VAR_FIFOptr ;Write Pointer/Counter
            CMP #PAR_FIFOsize
            JNC _rInt8 ;Counter Overflow?
            CLA
            STAA VAR_FIFOptr
_rInt8      CLC
            SHL ;FIFO has two bytes per pointer
            TAX
            LDAA VAR_second
            STA VAR_FIFOdata,X 
            RTS
            
;2. New bit -> add to FIFO  
_rInt4      LDAA VAR_FIFOptr ;Write Pointer/Counter
            CLC
            SHL ;FIFO has two bytes per pointer
            TAX
            JSR getBit
            STA VAR_FIFOdata+1,X
            INCA VAR_FIFOptr
            RTS
;END - Receiver interrupt
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<


  
;BEGIN - Timer interrupt 30.51757813 times per second
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 
int_timer
            ;Measure time between two edges
            LDAA FLG_dcfReceiver
            JNZ _tint0       
            INCA VAR_bitCount
            
            ;Start psuedo second
_tint0      LDAA FLG_startPSecond
            JPZ _RTS
            INCA VAR_pSecond
            RTS
;END - Timer interrupt
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



;BEGIN - Idle function (Bit decoding)
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 
int_idle

;New bit available?
            LDAA VAR_FIFOptr ;Write Pointer
            JPZ _pSec ;No data
            SEC
            JSR (KERN_SPINLOCK)
            
;Gather second and bit data from FIFO
            LDAA VAR_FIFOptr+1
            CMP #PAR_FIFOsize
            JNC _nBit11
            CLA ; Read Pointer Overflow -> Reset
            STAA VAR_FIFOptr+1
_nBit11     CLC
            SHL ;FIFO has two bytes per pointer
            TAX
            LDA VAR_FIFOdata,X
            STAA VAR_tmpSecond
            LDA VAR_FIFOdata+1,X
            STAA VAR_bitData
            
            LDAA VAR_FIFOptr
            DEC ;WritePTR starts by 1
            CMPA VAR_FIFOptr+1
            JPZ _nBit7
            ;Write>Read OR Write<Read (Write ptr overflow)
            INCA VAR_FIFOptr+1
            JMP _nBit

            
;Read==Write           
_nBit7      STZA VAR_FIFOptr
            STZA VAR_FIFOptr+1
            JMP _nBit


;Pseudo second?
_pSec       LDAA VAR_FIFOptr
            JNZ _nBit8 ;Add pseudo second only if idle-task is in sync with interrupt
            LDAA VAR_pSecond
            CMP #31
            JNC _nBit8
            INCA VAR_tmpSecond
            STZA VAR_bitData
            STZA FLG_startPSecond
            STZA VAR_pSecond
            LDA #1
            STAA FLG_startHandler ;Start App-Handler every new bit + pseudo second
            JMP _nBit
            
_nBit8      CLC
            JSR (KERN_SPINLOCK)
            RTS

;New bit received
_nBit       JSR _nBit8

;Add VAR_delay to data struct in RAM            
            LDX #08h
            LDAA VAR_FIFOptr
            SEC
            SBCA VAR_FIFOptr+1
            STAA VAR_delay
            JPC _nBit6
            LDA #0FFh
            SEC
            SBCA VAR_delay
            STAA VAR_delay
_nBit6      STA (ZP_dataStructPTR),X
            
;TODO: DEBUG PRINT FIFO pointer
    ;LDAA VAR_delay
    ;CLX
    ;CLY
    ;JSR (KERN_PRINTDEZ)
    ;LDA #13 ;\r
    ;JSR (KERN_PRINTCHAR)
;---------------------------------------------------------
;Display synced status on I/O-Module LEDs
#IFDEF SYNC_DISP
        JSR syncDisp
#ENDIF  
;Display synced status on SCC-Board
#IFDEF SCC_BOARD
        JSR sccBoard
#ENDIF

;Add data to struct in RAM
            PUSH ZP_dataStructPTR ;Save ZP to stack
            PUSH ZP_dataStructPTR+1 ;Save ZP to stack
            LPTA VAR_dataStructPTR
            SPT ZP_dataStructPTR
            LDX #00h ;FLG_synced
            LDAA FLG_synced
            STA (ZP_dataStructPTR),X

            LDX #0Ah ;Second
            LDAA VAR_tmpSecond
            STA (ZP_dataStructPTR),X ;Add second to struct in RAM

;DEBUG print desynchronisation            
#IFDEF DEBUG
        LDAA FLG_synced
        JPZ _dbg2
        LDA #13 ;\r
        JSR (KERN_PRINTCHAR)
        LPT #STR_lost_sync
        JSR (KERN_PRINTSTR)
_dbg2
#ENDIF 

;Add data to struct in RAM
_nBit5      LDAA VAR_bitData
            JPZ _tFill3
            LDA #1
_tFill3     LDX #02h ;VAR_bitData
            STA (ZP_dataStructPTR),X
            POP ZP_dataStructPTR+1 ;Restore ZP from stack
            POP ZP_dataStructPTR ;Restore ZP from stack
                      
;If not synced -> Stop decoding
            LDAA FLG_synced
            JNZ decRTS

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

;Check which second/bit we have            
            LDAA VAR_tmpSecond
            JNZ _nBit3
            LDAA VAR_bitData
            JNZ deSync ;If Bit 0 != 0 -> Not synchronized or incorrect signal
            
;Second/bit = 0 -> Take over data from last minute  
            PUSH ZP_dataStructPTR ;Save ZP to stack
            PUSH ZP_dataStructPTR+1 ;Save ZP to stack
            LPTA VAR_dataStructPTR
            SPT ZP_dataStructPTR  
            LDAA VAR_tmpSecond
            TAY ;Save Seconds in Y-Reg
            LDAA VAR_dataOK
            AND #01h
            JPZ _nBit1
            LDAA VAR_tmpMinutes ;Take over 'minutes'
            STAA VAR_minutes
            LDX #0Bh
            STA (ZP_dataStructPTR),X ;Add minutes to data struct in RAM
            
_nBit1      LDAA VAR_dataOK
            AND #02h
            JPZ _nBit2
            LDAA VAR_tmpHours
            STAA VAR_hours ;Take over 'hours'
            LDX #0Ch
            STA (ZP_dataStructPTR),X ;Add hours to data struct in RAM
            
            ;Set system time
            LDAA VAR_dataOK
            AND #03h
            CMP #03h
            JNZ _nBit2
            LDAA VAR_hours;Load Hours in Accu
            LDXA VAR_minutes;Load Minutes in X-Reg
            ;Sync every minute at xx:xx:00
            SEC
            JSR (KERN_GETSETTIME)
            
_nBit2      POP ZP_dataStructPTR+1 ;Restore ZP from stack
            POP ZP_dataStructPTR ;Restore ZP from stack
            LDAA VAR_dataOK
            AND #04h
            JPZ decRTS
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
            
            ;Set system datetime
            ;Sync every minute at xx:xx:00
            SEC
            JSR (KERN_GETSETDATE)
            
;fill struct in RAM with date data
            PUSH ZP_dataStructPTR ;Save ZP to stack
            PUSH ZP_dataStructPTR+1 ;Save ZP to stack
            LPTA VAR_dataStructPTR
            SPT ZP_dataStructPTR 
            LDX #0Dh
_tFill0     LDA START_DATA_STRUCT,X
            STA (ZP_dataStructPTR),X
            INX
            CPX #11h
            JPC _tFill4
            JMP _tFill0

_tFill4     POP ZP_dataStructPTR+1 ;Restore ZP from stack
            POP ZP_dataStructPTR ;Restore ZP from stack
            JMP decRTS

;Second > 0        
_nBit3      CMP #20
            JNZ _nBit4
            LDAA VAR_bitData ;Second/bit = 20 -> Begin of time information always '1'
            JPZ deSync ;If Bit 20 != 1 -> Not synchronized or incorrect signal
            JMP decRTS
 
;Second != 20 - Get/decode data
_nBit4      LDAA VAR_tmpSecond
            CMP #15
            JNC getMeteo ;Go to meteo
            ;Second >= 15
            CMP #20
            JNC getAddInfo ; Get additional information bits
            ;Second >= 20 (21 / Bit 20 already handled)
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
            JNZ decRTS
            ;Second = 59 -> Leap second!
            LDAA VAR_bitData ;Always '0'
            JNZ deSync 
            JMP decRTS


;Get/decode meteotime
;---------------------------------------------------------
getMeteo    
            JSR func_getMinutes
            JPC _gMet12 ;No minute data available -> Skip meteo section // TODO: Get every byte and check minute later
            MOD #3
            JPZ _gMet10 ;//Check for start minute -> = 0, 3, 6, 9, ...
            ;Minute -> n+1 or n+2
            LDAA VAR_meteoCount1
            CMP #14
            JNC decRTS ;Previous data not complete
            TAX
            JSR getBitChar
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount1        
            TXA
            CMP #41
            JPZ _getMeteo0
            JMP decRTS
            
            ;Last bit received
_getMeteo0  CLA
            LDX #82
            STA VAR_meteoWrite,X ;Terminate String with 0
            
;fill data struct with meteo data (Zero terminated string)
            PUSH ZP_dataStructPTR ;Save ZP to stack
            PUSH ZP_dataStructPTR+1 ;Save ZP to stack
            LPTA VAR_dataStructPTR
            SPT ZP_dataStructPTR
            LDX #11h
            CLY
_tFill1     LDA VAR_meteoWrite,Y
            STA VAR_meteoRead,Y
            STA (ZP_dataStructPTR),X
            INX
            INY
            CPY #83 ; Meteo String 82 Byte + 0
            JPC _tFill2
            JMP _tFill1

_tFill2     LDA #08h
            ORAA VAR_dataOK
            STAA VAR_dataOK
            POP ZP_dataStructPTR+1 ;Restore ZP from stack
            POP ZP_dataStructPTR ;Restore ZP from stack

;DEBUG print meteo string
#IFDEF DEBUG
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_meteo
    JSR (KERN_PRINTSTR)
    LPTA VAR_meteoRead
    JSR (KERN_PRINTSTR)
#ENDIF


_gMet12     STZA VAR_meteoCount1 ;Reset bit counter
            STZA VAR_meteoCount2 ;Reset bit counter            
            JMP decRTS    
            
;Start minute (0, 3, 6, 9, ...)
_gMet10     LDAA VAR_tmpSecond
            CMP #1
            JNZ _gMet11 ;Bit > 1 -> Write to Array
            STZA VAR_meteoCount1 ;First minute & first bit -> Reset bit counter
            STZA VAR_meteoCount2 ;First minute & first bit -> Reset bit counter
_gMet11     JSR getBitChar
            LDXA VAR_meteoCount1
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount1
            JMP decRTS       

;Get/decode additional information bits
;---------------------------------------------------------
getAddInfo
            CMP #15
            JNZ _getAI0
            LDA #03h ;VAR_addInfo start
            STAA VAR_bitCache+1

;Get additional bits
_getAI0     PUSH ZP_dataStructPTR ;Save ZP to stack
            PUSH ZP_dataStructPTR+1 ;Save ZP to stack
            LPTA VAR_dataStructPTR
            SPT ZP_dataStructPTR  
            LDAA VAR_bitData
            JPZ _getAI1
            LDA #1
_getAI1     LDXA VAR_bitCache+1
            STA (ZP_dataStructPTR),X
            INCA VAR_bitCache+1
            POP ZP_dataStructPTR+1 ;Restore ZP from stack
            POP ZP_dataStructPTR ;Restore ZP from stack

            JMP decRTS 

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
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount2

;Get bit (minutes)
_gMin0      LDAA VAR_bitData
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1
            JMP decRTS

;*** Get meteo 2/2 ***
_gMet21     LDAA VAR_meteoCount2
            CMP #49
            JNZ parityMinutes ;Previous meteo data not complete
            TAX
            LDA #'0'
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount2

;Last bit
;Check parity (minutes)        
parityMinutes  
            LDAA VAR_bitData ;Get "Carry-Bit" and save it to stack for later use
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

            JMP decRTS
        
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
            JMP decRTS
        
    
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
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount2

;Get bit (hours)
_gHrs0      LDAA VAR_bitData
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1
            JMP decRTS

;*** Get meteo 2/2 ***
_gMet31     LDAA VAR_meteoCount2
            CMP #56
            JNZ parityHours ;Previous meteo data not complete
            TAX
            LDA #'0'
            STA VAR_meteoWrite,X ; 1. '0'
            INX
            STA VAR_meteoWrite,X ; 2. '0'
            INX
            STXA VAR_meteoCount2

;Last bit
;Check parity (hours)         
parityHours       
            SHRA VAR_bitCache+1
            LDAA VAR_bitData ;Get "Carry-Bit" and save it to stack for later use
            PHA
            ;Determine if bitcount of data is even or odd
            LDAA VAR_bitCache+1
            LDX #6
            CLY
            JSR bitCnt
            JPC _pHrs0   
            PLA ;Bit count = "odd"
            JNZ _pHrsOK
            
_pHrsBAD    LDA #0Dh ;Parity n.OK
            ANDA VAR_dataOK
            STAA VAR_dataOK

;DEBUG print hours parity failure            
#IFDEF DEBUG
    LDA #' '
    JSR (KERN_PRINTCHAR)
    LPT #STR_hour_fail
    JSR (KERN_PRINTSTR)
#ENDIF 

            JMP decRTS
            
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
            JMP decRTS
                
        
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
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount2
  
;Get bit (day)      
_gDay0      LDAA VAR_bitData
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1
            ;Check for last bit
            LDAA VAR_tmpSecond
            CMP #41       
            JNZ decRTS 

;*** Get meteo 2/2 ***
            LDAA VAR_meteoCount2
            CMP #64
            JNZ _gDay1 ;Previous meteo data not complete
            TAX
            LDA #'0'
            STA VAR_meteoWrite,X ; 1. '0'
            INX
            STA VAR_meteoWrite,X ; 2. '0'
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
            JMP decRTS      
        
        
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
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount2

;Get bit (weekday)    
_getWDay0   LDAA VAR_bitData
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1
            ;Check for last bit
            LDAA VAR_tmpSecond
            CMP #44       
            JNZ decRTS

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

            JMP decRTS 
        
        
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
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount2
        
;Get bit (month)
_gMon0      LDAA VAR_bitData
            ORAA VAR_bitCache+1
            SHR
            STAA VAR_bitCache+1            
            ;Check for last bit
            LDAA VAR_tmpSecond
            CMP #49       
            JNZ decRTS 

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

            JMP decRTS
        
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
            STA VAR_meteoWrite,X
            INCA VAR_meteoCount2

;Get bit (year)
_gYear0     SHRA VAR_bitCache+1
            LDAA VAR_bitData
            ORAA VAR_bitCache+1
            STAA VAR_bitCache+1
            JMP decRTS

;Last bit
;Check parity for whole date (Day, weekday, month, year)         
parityDate
            LDAA VAR_bitData ;Get "Carry-Bit" and save it to stack for later use
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

            JMP decRTS
            
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


;Add dataOK byte to struct in RAM
decRTS      PUSH ZP_dataStructPTR ;Save ZP to stack
            PUSH ZP_dataStructPTR+1 ;Save ZP to stack
            LPTA VAR_dataStructPTR
            SPT ZP_dataStructPTR
            LDX #01h ;VAR_dataOK
            LDA START_DATA_STRUCT,X
            STA (ZP_dataStructPTR),X 
            POP ZP_dataStructPTR+1
            POP ZP_dataStructPTR
    
;Start application handler chain
            ;LDAA VAR_delay
            ;JNZ _RTS ;If receiver is delayed -> Skip handler
            
            LDAA FLG_startHandler ;Start Handler only if new second/pseudo second reached
            JPZ _RTS
            
            LDAA VAR_HDLCount
            JPZ _hdlRTS ;No handler registered

            CLX
_hdl0       LDA VAR_HDLbitmaskEN,X
            JNZ _hdl1
_hdl2       INX
            CPX #PAR_HDLMax
            JPC _hdlRTS ;End of handler chain
            JMP _hdl0
            
_hdl1       TXA
            STAA VAR_HDLPTR ;Current active handler No.
            SHL
            TAX

;call handler-routines in ROM
            LDYA VAR_HDLPTR
            LDA VAR_tabHDLROMPAGE,Y
            PHA
            LDA VAR_tabHANDLER+1,X
            PHA
            LDA VAR_tabHANDLER,X
            PHA
            JSR (KERN_CALLFROMROM)
            LDAA VAR_HDLPTR
            TAX
            JMP _hdl2 ;Next handler

_hdlRTS     STZA FLG_startHandler
            RTS
            
;END - Idle function
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            
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
            
            LDAA VAR_tmpSecond
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

;Get bit information from second (Output: A = High(80h), Low(00h))        
getBit      
            LDAA VAR_bitCache
            CMP #PARAM_LOWHIGH
            JNC _gBit0
            ;Time >= PARAM_LOWHIGH -> Bit = 1
            LDA #80h
            SKA
_gBit0      CLA ;Time < PARAM_LOWHIGH -> Bit = 0
            RTS
        
;Translate bitInfo to Char ('0' or '1') (Output: A = Char)        
getBitChar      
            LDAA VAR_bitData
            CMP #80h
            JNZ _gBitC0
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
            CLC
            MUL #0Ah
            STAA VAR_bitCache+1
            PLA
            AND #0Fh
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