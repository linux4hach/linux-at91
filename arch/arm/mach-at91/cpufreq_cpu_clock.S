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
#include <mach/at91_pio.h>

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

	.macro wait_sometime
	ldr	count, =0x100000
1:	sub	count, count, #1
	cmp	count, #0
	bne	1b
2:
	.endm

#define AT91_PINE_ADDR	0xfefffa00

	.macro led_red_on
	mov	tmp, #0x01
	mov	tmp1, tmp, lsl #24
	ldr     tmp, =(AT91_PINE_ADDR)
	str	tmp1, [tmp, #PIO_SODR]
	.endm

	.macro led_red_off
	mov	tmp, #0x01
	mov	tmp1, tmp, lsl #24
	ldr	tmp, =(AT91_PINE_ADDR)
	str	tmp1, [tmp, #PIO_CODR]
	.endm

	.macro led_blue_on
	mov	tmp, #0x01
	mov	tmp1, tmp, lsl #25
	ldr     tmp, =(AT91_PINE_ADDR)
	str	tmp1, [tmp, #PIO_CODR]
	.endm

	.macro led_blue_off
	mov	tmp, #0x01
	mov	tmp1, tmp, lsl #25
	ldr	tmp, =(AT91_PINE_ADDR)
	str	tmp1, [tmp, #PIO_SODR]
	.endm


#define DDR_ADDR	0xC0000000

/*
 * void __update_cpu_clock(void __iomem *pmc, u32 pllar_mul,
 *			u32 mckr_mdiv, void __iomem *ddramc)
 */
ENTRY(__update_cpu_clock)
	/* Save registers on stack */
	stmfd	sp!, {r4 - r12, lr}

	led_red_on
	led_blue_on

	/* Make DDRAM enter self-refresh mode */
	ldr tmp, =(DDR_ADDR)
	ldr	tmp1, [tmp]
	str	tmp1, .saved_data_of_ddr
	ldr	tmp, [ddramc, #AT91_DDRSDRC_LPR]
	str	tmp, .saved_sam9_lpr
	bic	tmp, tmp, #AT91_DDRSDRC_LPCB
	orr	tmp, tmp, #AT91_DDRSDRC_LPCB_SELF_REFRESH
	str	tmp, [ddramc, #AT91_DDRSDRC_LPR]

	wait_sometime

	/* Master/Processor Clock Source Selection to Main Clock */
	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_CSS
	orr	tmp, tmp, #AT91_PMC_CSS_MAIN
	str	tmp, [pmc, #AT91_PMC_MCKR]

	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_PLLADIV2
	orr	tmp, tmp, #AT91_PMC_PLLADIV2_ON
	str	tmp, [pmc, #AT91_PMC_MCKR]

	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_MDIV
	orr	tmp, tmp, #AT91SAM9_PMC_MDIV_2
	str	tmp, [pmc, #AT91_PMC_MCKR]

	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_ALT_PRES
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
	bic	tmp, tmp, #AT91_PMC_PLLADIV2
	and	tmp1, mckr_mdiv, #AT91_PMC_PLLADIV2
	orr     tmp, tmp, tmp1
	str	tmp, [pmc, #AT91_PMC_MCKR]

	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_ALT_PRES
	and	tmp1, mckr_mdiv, #AT91_PMC_ALT_PRES
	orr     tmp, tmp, tmp1
	str     tmp, [pmc, #AT91_PMC_MCKR]

	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_MDIV
	and	tmp1, mckr_mdiv,#AT91_PMC_MDIV
	orr	tmp, tmp, tmp1
	str	tmp, [pmc, #AT91_PMC_MCKR]

	ldr	tmp, [pmc, #AT91_PMC_MCKR]
	bic	tmp, tmp, #AT91_PMC_CSS
	orr	tmp, tmp, #AT91_PMC_CSS_PLLA
	str	tmp, [pmc, #AT91_PMC_MCKR]

	wait_mckrdy

	/* Restore LPR on AT91 with DDRAM */
	ldr	tmp, .saved_sam9_lpr
	str	tmp, [ddramc, #AT91_DDRSDRC_LPR]
	wait_sometime

	ldr	tmp, =(AT91_DDRSDRC_MODE_PRECHARGE)
	str	tmp, [ddramc, #AT91_DDRSDRC_MR]
	mov	tmp1, #0x0
	ldr tmp, =(DDR_ADDR)
	str	tmp1, [tmp]
	/*wait_sometime*/
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

	ldr	tmp, =(AT91_DDRSDRC_MODE_REFRESH)
	str	tmp, [ddramc, #AT91_DDRSDRC_MR]
	mov	tmp1, #0x0
	ldr tmp, =(DDR_ADDR)
	str	tmp1, [tmp]
	/*wait_sometime*/
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

	ldr	tmp, =(AT91_DDRSDRC_MODE_NORMAL)
	str	tmp, [ddramc, #AT91_DDRSDRC_MR]
	mov	tmp1, #0x0
	ldr tmp, =(DDR_ADDR)
	str	tmp1, [tmp]
	/*wait_sometime*/
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

	ldr	tmp1, .saved_data_of_ddr
	ldr tmp, =(DDR_ADDR)
	str	tmp1, [tmp]

	led_red_off
	led_blue_off

	/* Restore registers, and return */
	ldmfd	sp!, {r4 - r12, pc}

.saved_sam9_lpr:
	.word 0

.saved_data_of_ddr:
	.word 0

.ltorg

ENTRY(__update_cpu_clock_sz)
	.word .-__update_cpu_clock
