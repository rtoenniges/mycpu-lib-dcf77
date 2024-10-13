/*
 *  Displays Date/Time information from DCF77-Library (sl60dcf77) on 4x20 LCD
 *  Register an application handler and uses struct pointer from library
 *  Compile with "cl65 -t mycpu dcf77.c -o dcf77"
 *
 *  2024  Robin Tönniges, development@toenniges.org
 */

#include <stdio.h>
#include <stdlib.h>
#include <mycpu.h>
#include <string.h>

static unsigned int *REG_RAMPAGE = (unsigned int *) 0x3800;
static unsigned char libHandler = 0;
static unsigned char libROMPAGE = 0;
static FARPTR dcf77StructPTR = 0;

static unsigned char meszData[] = "    ";
static unsigned char minData[] = "          ";
static unsigned char hourData[] = "            ";
static unsigned char dayData[] = "             ";
static unsigned char wdayData[] = "         ";
static unsigned char monthData[] = "           ";
static unsigned char yearData[] = "            ";

static unsigned char tmpRAMPAGE = 0;
static unsigned char thisRAMPAGE = 0;



static void dcfHandler(void)
{
	unsigned char dcf77Struct[17];
	unsigned int second, minute, hour, day, month, year, delay;
	
	tmpRAMPAGE = *REG_RAMPAGE;
	*REG_RAMPAGE = thisRAMPAGE;
	
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
				lprintf("Date: %02d.%02d.20%d    ", day, month, year);	
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
				else if (second >= 15 && second < 21 && (dcf77Struct[0x01] & 0x08) == 0x08 && (minute % 3) == 2)
				{
					lprintf("->METEO available!  ");
				}
				else if (second >= 21 && second < 29) //Get minute
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
				else if (second >= 29 && second < 36) //Get hour
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
				else if (second >= 36 && second < 42) //Get day
				{
					dayData[41-second] = dcf77Struct[0x02] + '0';
					lprintf("->Day: %s", dayData);
				}
				else if (second >= 42 && second < 45) //Get weekday
				{
					wdayData[44-second] = dcf77Struct[0x02] + '0';
					lprintf("->Weekday: %s", wdayData);
				}
				else if (second >= 45 && second < 50) //Get month
				{
					monthData[49-second] = dcf77Struct[0x02] + '0';
					lprintf("->Month: %s", monthData);
				}
				else if (second >= 50 && second <= 58) //Get year
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
	
	*REG_RAMPAGE = tmpRAMPAGE;
}


void doAtExit(void)
{
    unsigned char a, x, y, flags;
	
	//Call sl60dcf77
	a = 0x60;
	x = 0;
	y = 0;
	flags = 0;
	kcall(0x02CC, &a, &x, &y, &flags); //Lib select
	
	a = 0x0C;
	x = libHandler;
	y = 0;
	flags = 0;
	kcall(0x02CA, &a, &x, &y, &flags); //Delete handler
	
	lcd_clear();
}


int main(int argc, char *argv[])
{
	unsigned char a, x, y, flags;
	unsigned char codepage = (unsigned char) getcodepage(0);
	unsigned int func_ptr = (unsigned int) &dcfHandler;
	
	if (isloaded("dcf77"))
	{
		return 0;
	}
	
	lcd_clear();
	lcd_scroll(0);
	lprintf("--=DCF77 Receiver=--");
	
    /* suppress warning about unused variables */
    (void)argc,(void)argv;
	
    //Call sl60dcf77
	a = 0x60;
	x = 0;
	y = 0;
	flags = 0;
	kcall(0x02CC, &a, &x, &y, &flags); //Lib select
	
	//Get DCF77-Lib ROMPAGE
	a = 0x0A;
	x = 0;
	y = 0;
	kcall(0x02CA, &a, &x, &y, &flags); //Lib call
	libROMPAGE = a;
	
	//Get struct pointer and RAMPAGE -> Build FARPTR
	a = 0x0B;
	x = 0;
	y = 0;
	kcall(0x02CA, &a, &x, &y, &flags); //Lib call
	dcf77StructPTR = ((unsigned char) x) |
	                 ((unsigned int) y << 8) |
					 ((unsigned long) a << 16) |
					 ((unsigned long) libROMPAGE << 24);
					 
	//Register application handler
	a = 0x0C;
	x = (unsigned char) func_ptr & 0xFF;
	y = (unsigned char) ((func_ptr >> 8) & 0xFF);
	flags = 1;
	kcall(0x02CA, &a, &x, &y, &flags); //Lib call
	
	//Tell C-ROMPAGE for appl. handler
	libHandler = a;
	x = libHandler;
	y = codepage;
	a = 0x0D;
	kcall(0x02CA, &a, &x, &y, &flags); //Lib call
	
	atexit(doAtExit);
	
	thisRAMPAGE = *REG_RAMPAGE; //Store current RAMPAGE
	
	tsr(0); 
    return 0;
}
