/*	$Id$	*/

#define	SERIAL_TICKCNT	20	/* use a slightly higher speed logic when simulating */

void sdramexec(Vnvax *tb);
void ttoexec(Vnvax *tb);
void ttiexec(Vnvax *tb);
void ttiinit(void);
void tick(Vnvax *tb);

extern int tto_active, tti_active;
extern volatile int ttisig;
extern unsigned long nticks;
