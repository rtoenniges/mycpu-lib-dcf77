/*
 *  Displays Date/Time information from DCF77-Library (sl60dcf77) on 4x20 LCD
 *  Register an application handler and uses struct pointer from library
 *
 *  2026  Robin Toenniges, development@toenniges.org
 */
 
// Compile with "cl65 -t mycpu dcf77.c dcf77lib.s -o dcf77"
 
// DO NOT START DIRECTLY AFTER "NETSTART" IN A SCRIPT (e.g. INIT-File) //
// CPU crashes after first Handler-Call... dont know why :-( //

#include <stdio.h>
#include <stdlib.h>
#include <mycpu.h>
#include <string.h>
#include "dcf77lib.h"

static u16_t *REG_RAMPAGE = (u16_t *) 0x3800;
static u16_t *REG_ROMPAGE = (u16_t *) 0x3900;
static u16_t *REG_ZEROPAGE = (u16_t *) 0x3A00;
static u16_t *REG_STACKPAGE = (u16_t *) 0x3B00;
static FARPTR dcf77StructPTR = 0;

static u8_t meszData[] = "    ";
static u8_t minData[] = "          ";
static u8_t hourData[] = "            ";
static u8_t dayData[] = "             ";
static u8_t wdayData[] = "         ";
static u8_t monthData[] = "           ";
static u8_t yearData[] = "            ";

static u8_t tmpRAMPAGE = 0;
static u8_t thisRAMPAGE = 0;

static u8_t tmpZEROPAGE = 0;
static u8_t thisZEROPAGE = 0;

static u8_t tmpSTACKPAGE = 0;
static u8_t thisSTACKPAGE = 0;

static u8_t dcf77Struct[17];
static unsigned int second, minute, hour, day, month, year, delay;

static void dcfHandler(void)
{
    tmpRAMPAGE = *REG_RAMPAGE;
    *REG_RAMPAGE = thisRAMPAGE;
    
    tmpZEROPAGE = *REG_ZEROPAGE;
    *REG_ZEROPAGE = thisZEROPAGE;
    
    tmpSTACKPAGE = *REG_STACKPAGE;
    //*REG_STACKPAGE = thisSTACKPAGE;
    
    memcpyf2n(&dcf77Struct, dcf77StructPTR, sizeof(dcf77Struct));

    lcd_gotoxy(0,1);
        
    if (dcf77Struct[0x00] == 0) //Receiver synchronized?
    {
        second = dcf77Struct[0x0A];
        
        if ((dcf77Struct[0x01] & 0x07) == 0x07) //DateTime info available?
        {
            minute = dcf77Struct[0x0B];
            hour = dcf77Struct[0x0C];
            day = dcf77Struct[0x0D];
            month = dcf77Struct[0x0F];
            year = dcf77Struct[0x010];
            delay = dcf77Struct[0x08];
            
            if (dcf77Struct[0x05] && !dcf77Struct[0x06]) //MESZ
            {
                if (dcf77Struct[0x04] && (second % 2) == 0) //Switch MEZ/MESZ / Blink every second
                {
                    strcpy((char*)meszData, "    ");
                }
                else
                {
                    strcpy((char*)meszData, "MESZ");
                }
            }
            else if (!dcf77Struct[0x05] && dcf77Struct[0x06]) //MEZ
            {
                if (dcf77Struct[0x04] && (second % 2) == 0) //Switch MEZ/MESZ / Blink every second
                {
                    strcpy((char*)meszData, "    ");
                }
                else
                {
                    strcpy((char*)meszData, "MEZ ");
                }
            }
            else
            {
                strcpy((char*)meszData, "    ");
            }
            
            lprintf("Time: %02d:%02d:%02d  %s", hour, minute, second, meszData);
            lprintf("Date: %02d.%02d.20%02d    ", day, month, year);    
        } 
        else //Synchronized but no data
        {
            lprintf("Collecting Data...  ");
            lprintf("Second: %02d          ", second);
        }
        
        if (delay > 0)
        {
            lprintf("Receiver delay!: %02ds", delay);
        }
        else
        {
            //Print data info
            if (second == 0)
            {
                strcpy((char*)minData, "          ");
                strcpy((char*)hourData, "            ");
                strcpy((char*)dayData, "             ");
                strcpy((char*)wdayData, "         ");
                strcpy((char*)monthData, "           ");
                strcpy((char*)yearData, "            ");
            }
            else if(second < 15)
            {
                if (minute % 3 == 0)
                {
                    lprintf("->Get METEO-Data 1/3");
                }
                else if (minute % 3 == 1)
                {
                    lprintf("->Get METEO-Data 2/3");
                }
                else if (minute % 3 == 2)
                {
                    lprintf("->Get METEO-Data 3/3");
                }
            }
            else if (second < 21)
            {
                if ((dcf77Struct[0x01] & 0x08) == 0x08 && (minute % 3) == 2)
                {
                    lprintf("->METEO available!  ");
                }
            }
            else if (second < 29) //Get minute
            {
                if (second == 28)
                {
                    //Print parity bit
                    minData[28-second] = '(';
                    minData[28+1-second] = dcf77Struct[0x02] + '0';
                    minData[28+2-second] = ')';
                }
                else
                {
                    minData[30-second] = dcf77Struct[0x02] + '0';
                }
                lprintf("->Minute: %s", minData);
            }
            else if (second < 36) //Get hour
            {
                if (second == 35)
                {
                    //Print parity bit
                    hourData[35-second] = '(';
                    hourData[35+1-second] = dcf77Struct[0x02] + '0';
                    hourData[35+2-second] = ')';
                }
                else
                {
                    hourData[37-second] = dcf77Struct[0x02] + '0';
                }
                lprintf("->Hour: %s", hourData);
            }
            else if (second < 42) //Get day
            {
                dayData[41-second] = dcf77Struct[0x02] + '0';
                lprintf("->Day: %s", dayData);
            }
            else if (second < 45) //Get weekday
            {
                wdayData[44-second] = dcf77Struct[0x02] + '0';
                lprintf("->Weekday: %s", wdayData);
            }
            else if (second < 50) //Get month
            {
                monthData[49-second] = dcf77Struct[0x02] + '0';
                lprintf("->Month: %s", monthData);
            }
            else if (second < 59) //Get year
            {
                if (second == 58)
                {
                    //Print parity bit
                    yearData[58-second] = '(';
                    yearData[58+1-second] = dcf77Struct[0x02] + '0';
                    yearData[58+2-second] = ')';
                }
                else
                {
                    yearData[60-second] = dcf77Struct[0x02] + '0';
                }
                lprintf("->Year: %s", yearData);
            }
            else
            {
                lprintf("                    ");
            }
        }
        
        
    }
    else
    {
        lprintf("Not synchronized...                                         ");
    }
    
    *REG_ZEROPAGE = tmpZEROPAGE;
    *REG_RAMPAGE = tmpRAMPAGE;
    //*REG_STACKPAGE = tmpSTACKPAGE; //Kernel Idle-Function has its own stackpackge
}


void doAtExit(void)
{
    
    dcf_deleteHandler();
    
    dcf_stop();
    
    lcd_clear();
}


int main(int argc, char *argv[])
{
    /* suppress warning about unused variables */
    (void)argc,(void)argv,(void)REG_ROMPAGE,(void)REG_STACKPAGE,(void)tmpSTACKPAGE,(void)thisSTACKPAGE;
    
    // Program already running?
    if (isloaded("dcf77"))
    {
        return 0;
    }
    
    thisRAMPAGE = *REG_RAMPAGE; //Store current RAMPAGE
    thisZEROPAGE = *REG_ZEROPAGE; //Store current ZEROPAGE
    thisSTACKPAGE = *REG_STACKPAGE; //Store current STACKPAGE
    
    atexit(doAtExit);
    
    lcd_clear();
    lcd_scroll(0);
    lprintf("--=DCF77 Receiver=--");
    lprintf("Waiting for Sync... ");
    
    
    dcf77StructPTR = dcf_start();
    dcf_regHandler(&dcfHandler);
    dcf_startHandler();
    
    
    tsr(0); 
    return 0;
}
