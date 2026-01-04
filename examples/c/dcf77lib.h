/*****************************************************************************/
/*                                                                           */
/*                  dcf77lib.h                                               */
/*                                                                           */
/*            C-Functions for sl60dcf77                                      */
/*                                                                           */
/*                                                                           */
/*                                                                           */
/* (C) 2026       Robin Tönniges                                             */
/* EMail:         development@toenniges.org                                  */
/*                                                                           */
/*                                                                           */
/* This software is provided 'as-is', without any expressed or implied       */
/* warranty.  In no event will the authors be held liable for any damages    */
/* arising from the use of this software.                                    */
/*                                                                           */
/* Permission is granted to anyone to use this software for any purpose,     */
/* including commercial applications, and to alter it and redistribute it    */
/* freely, subject to the following restrictions:                            */
/*                                                                           */
/* 1. The origin of this software must not be misrepresented; you must not   */
/*    claim that you wrote the original software. If you use this software   */
/*    in a product, an acknowledgment in the product documentation would be  */
/*    appreciated but is not required.                                       */
/* 2. Altered source versions must be plainly marked as such, and must not   */
/*    be misrepresented as being the original software.                      */
/* 3. This notice may not be removed or altered from any source              */
/*    distribution.                                                          */
/*                                                                           */
/*****************************************************************************/

#ifndef _DCF77LIB_H
#define _DCF77LIB_H

/* Check for errors */
#if !defined(__MYCPU__)
#  error This module may only be used when compiling for MyCPU!
#endif


/*****************************************************************************/
/*                               Code                                        */
/*****************************************************************************/


/*** data types ***/
//typedef unsigned char  LIBHANDLE;
//typedef unsigned long  FARPTR;  /*bits 0-15=adr, bits 16-23=RAMPG, bits 24-31=ROMPG */
typedef void (*HANDLERFUNC) (void);



/*** function prototypes ***/

FARPTR __fastcall__ dcf_start( void );
/* Start/Load DCF77 Library and return Pointer to Data Struct */

void __fastcall__ dcf_stop( void );
/* Try to unload DCF77 Library (May fail if used by other programs) */

void __fastcall__ dcf_regHandler( HANDLERFUNC handlerfunc );
/* Register Handler to DCF77 Library. Called every new received bit */

void __fastcall__ dcf_startHandler( void );
/* Start DCF77 Handler registered with "dcf_regHandler" */

void __fastcall__ dcf_deleteHandler( void );
/* Stop/Delete DCF77 Handler registered with "dcf_regHandler" */

/* End of dcf77lib.h */
#endif
