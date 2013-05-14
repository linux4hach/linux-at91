/*
 * arch/arm/mach-at91/cpufreq_cpu_clock.S
 *
 *    Copyright (C) 2013 Atmel
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 */

#include <linux/linkage.h>
#include <mach/hardware.h>
#include <mach/at91_pmc.h>
#include <mach/at91_ramc.h>

#define MCKRDY_TIMEOUT		50000
#define PLLALOCK_TIMEOUT	50000

/*
 * Register usage:
 *  r0 = Base address of AT91_PMC
 *  r1 = the value of setting for PLLA
 *  r2 = the value of MCKR Prescaler and divider
 *  r3 = Base address of DDRAMC
 *  r4 = as counter
 *  r5 = temporary register
 */

pmc		.req	r0
pllar_mul	.req	r1
mckr_mdiv	.req	r2
ddramc		.req	r3
count		.req	r4
tmp		.req	r5
tmp1		.req	r6

/*
 * Wait until master clock is ready (after switching master clock source)
 */
	.macro wait_mckrdy
	ldr	count, =(MCKRDY_TIMEOUT)
1:	sub	count, count, #1
	cmp	count, #0
	beq	2f
	ldr	tmp, [pmc, #AT91_PMC_SR]
	tst	tmp, #AT91_PMC_MCKRDY
	beq	1b
2:
	.endm

/*
 * Wait until PLLA has locked.
 */
	.macro wait_pllalock
	ldr	count, =(PLLALOCK_TIMEOUT)
1:	sub	count, count, #1
	cmp	count, #0
	beq	2f
	ldr	tmp, [pmc, #AT91_PMC_SR]
	tst	tmp, #AT91_PMC_LOCKA
	beq	1b
2:
	.endm

/*
 * void __update_cpu_clock(void __iomem *pmc, u32 pllar_mul,
 *			u32 mckr_mdiv, void __iomem *ddramc)
 */
ENTRY(__update_cpu_clock)
	/* Save registers on stack */
	stmfd	sp!, {r4 - r12, lr}

	/* Make DDRAM enter self-refresh mode */
	ldr	tmp, [ddramc, #AT91_DDRSDRC_LPR]
	str	tmp, .saved_sam9_lpr
	bic	tmp, tmp, #AT91_DDRSDRC_LPCB
	orr	tmp, tmp, #AT91_DDRSDRC_LPCB_SELF_REFRESH
	str	tmp, [ddramc, #AT91_DDRSDRC_LPR]

	/* Master/Processor Clock Source Selection to Main Clock */
	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_CSS
	orr	tmp, tmp, #AT91_PMC_CSS_MAIN
	str	tmp, [pmc, #AT91_PMC_MCKR]

	bic	tmp, tmp, #AT91_PMC_PLLADIV2
	orr	tmp, tmp, #AT91_PMC_PLLADIV2_ON
	str	tmp, [pmc, #AT91_PMC_MCKR]

	bic	tmp, tmp, #AT91_PMC_MDIV
	bic	tmp, tmp, #AT91_PMC_ALT_PRES
	orr	tmp, tmp, #AT91SAM9_PMC_MDIV_2
	orr	tmp, tmp, #AT91_PMC_ALT_PRES_1
	str	tmp, [pmc, #AT91_PMC_MCKR]

	wait_mckrdy

	str	pllar_mul, [pmc, #AT91_CKGR_PLLAR]

	wait_pllalock

	/*
	 * Master/Processor Clock Source Selection PLLA
	 * and set new prescaler and divider
	 */
	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_ALT_PRES
	and	tmp1, mckr_mdiv, #AT91_PMC_ALT_PRES
	orr     tmp, tmp, tmp1
	str     tmp, [pmc, #AT91_PMC_MCKR]

	bic	tmp, tmp, #AT91_PMC_PLLADIV2
	and	tmp1, mckr_mdiv, #AT91_PMC_PLLADIV2
	orr     tmp, tmp, tmp1
	str	tmp, [pmc, #AT91_PMC_MCKR]

	bic	tmp, tmp, #AT91_PMC_MDIV
	and	tmp1, mckr_mdiv,#AT91_PMC_MDIV
	orr	tmp, tmp, tmp1
	str	tmp, [pmc, #AT91_PMC_MCKR]

	bic	tmp, tmp, #AT91_PMC_CSS
	orr	tmp, tmp, #AT91_PMC_CSS_PLLA
	str	tmp, [pmc, #AT91_PMC_MCKR]

	wait_mckrdy

	/* Restore LPR on AT91 with DDRAM */
	ldr	tmp, .saved_sam9_lpr
	str	tmp, [ddramc, #AT91_DDRSDRC_LPR]

	/* Restore registers, and return */
	ldmfd	sp!, {r4 - r12, pc}

.saved_sam9_lpr:
	.word 0

.ltorg

ENTRY(__update_cpu_clock_sz)
	.word .-__update_cpu_clock
