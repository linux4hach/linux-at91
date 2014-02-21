/*
 * CPU frequency scaling for AT91SAM
 *
 * Copyright (C) 2013 Atmel Corporation
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/errno.h>
#include <linux/io.h>
#include <linux/gpio.h>
#include <linux/clk.h>
#include <linux/cpufreq.h>
#include <linux/opp.h>
#include <linux/platform_device.h>
#include <linux/regulator/consumer.h>
#include <mach/at91_pmc.h>
#include <mach/at91_ramc.h>

#define DEFAULT_TRANS_LATENCY	100000

struct cpufreq_regs_setting {
	u32	cpufreq_khz;
	u32	lpddr_rtr;
	u32	pllar_mul;
	u32	mckr_mdiv;
};

struct at91_cpufreq_data {
	struct clk *cpu_clk;
	u32	cur_frequency;
	u32	latency;
	struct cpufreq_frequency_table *freq_table;
	u32	freq_count;
	struct cpufreq_regs_setting *regs_setting_table;
	u32	regs_setting_count;
	struct device *dev;

	struct regulator *vddcore_reg;
};

static struct at91_cpufreq_data	*cpufreq_info;

#ifdef CPUFRE_DEBUG
void led_red_off(void)
{
	gpio_direction_output(AT91_PIN_PE24, 0);
}

void led_red_on(void)
{
	gpio_direction_output(AT91_PIN_PE24, 1);
}

void led_blue_on(void)
{
	gpio_direction_output(AT91_PIN_PE25, 0);
}

void led_blue_off(void)
{
	gpio_direction_output(AT91_PIN_PE25, 1);
}

void led_init(void)
{
	gpio_request(AT91_PIN_PE24, "Red LED");
	gpio_request(AT91_PIN_PE25, "Blue LED");
	led_red_off();
	led_blue_off();
}
#endif

static void (*update_cpu_clock)(void __iomem *pmc,
				u32 pllar_mul,
				u32 mckr_mdiv,
				void __iomem *sramc);

extern void __update_cpu_clock(void __iomem *pmc,
				u32 pllar_mul,
				u32 mckr_mdiv,
				void __iomem *sramc);
extern u32 __update_cpu_clock_sz;

static void update_lpddr_rtr(u32 value)
{
	at91_ramc_write(0, AT91_DDRSDRC_RTR, value);
}

static void set_cpu_freq(u32 target_freq)
{
	struct cpufreq_regs_setting *regs_setting;
	int i;

	for (i = 0; i < cpufreq_info->regs_setting_count; i++) {
		if (cpufreq_info->regs_setting_table[i].cpufreq_khz
						== target_freq)
			break;
	}

	if (i >= cpufreq_info->regs_setting_count) {
		dev_err(cpufreq_info->dev,
			"failed to find frequency: %d in setting table\n",
				target_freq);
		return;
	}

	regs_setting = &cpufreq_info->regs_setting_table[i];

	update_lpddr_rtr(regs_setting->lpddr_rtr);

	update_cpu_clock = (void *) (AT91_IO_VIRT_BASE - __update_cpu_clock_sz);

	memcpy(update_cpu_clock, __update_cpu_clock, __update_cpu_clock_sz);

	update_cpu_clock(at91_pmc_base,
				regs_setting->pllar_mul,
				regs_setting->mckr_mdiv,
				at91_ramc_base[0]);
}

static int at91_cpufreq_verify(struct cpufreq_policy *policy)
{
	return cpufreq_frequency_table_verify(policy,
					      cpufreq_info->freq_table);
}

static u32 _get_cur_freq(void)
{
	u32 mdiv;
	u32 mckr_mdiv = (at91_pmc_read(AT91_PMC_MCKR) & AT91_PMC_MDIV) >> 8;

	if (mckr_mdiv == 3)
		mdiv = mckr_mdiv;
	else
		mdiv = 1 << mckr_mdiv;

	return mdiv * clk_get_rate(clk_get(NULL, "mck")) / 1000;
}

static u32 at91_cpufreq_getspeed(u32 cpu)
{
	return cpufreq_info->cur_frequency;
}

static int at91_cpufreq_target(struct cpufreq_policy *policy,
			      u32 target_freq,
			      u32 relation)
{
	struct cpufreq_frequency_table *freq_table = cpufreq_info->freq_table;
	struct cpufreq_freqs freqs;
	unsigned long flags;
	int index;
#ifdef CONFIG_REGULATOR
	struct opp *opp;
	u32	volt;
#endif
	int ret = 0;

	if (policy->cpu != 0)
		return -EINVAL;

	/* Lookup the next frequency */
	ret = cpufreq_frequency_table_target(policy, freq_table,
					   target_freq, relation, &index);
	if (ret)
		return -EINVAL;

	freqs.old = cpufreq_info->cur_frequency;
	freqs.new = freq_table[index].frequency;
	freqs.cpu = policy->cpu;

	pr_info("CPU frequency from %d MHz to %d MHz%s\n",
			freqs.old / 1000, freqs.new / 1000,
			(freqs.old == freqs.new) ? " (skipped)" : "");

	if (freqs.old == freqs.new)
		return 0;

	cpufreq_notify_transition(policy, &freqs, CPUFREQ_PRECHANGE);

	local_irq_save(flags);
	set_cpu_freq(freqs.new);

#ifdef CPUFRE_DEBUG
	led_red_on();
	led_blue_off();
#endif

	local_irq_restore(flags);

	cpufreq_info->cur_frequency = freqs.new;

	cpufreq_notify_transition(policy, &freqs, CPUFREQ_POSTCHANGE);

#ifdef CPUFRE_DEBUG
	led_red_off();
	led_blue_on();
#endif

#ifdef CONFIG_REGULATOR
	rcu_read_lock();
	opp = opp_find_freq_exact(cpufreq_info->dev,
				  cpufreq_info->cur_frequency * 1000, true);
	if (IS_ERR(opp)) {
		rcu_read_unlock();
		dev_err(cpufreq_info->dev, "failed to find OPP for %d\n",
			cpufreq_info->cur_frequency * 1000);
		return -EINVAL;
	}

	volt = opp_get_voltage(opp);
	rcu_read_unlock();

	if (cpufreq_info->vddcore_reg)
		regulator_set_voltage(cpufreq_info->vddcore_reg, volt, volt);

	pr_info("\nNow, running on the frequency / voltage: %dMHz / %dmV\n",
						freqs.new / 1000, volt / 1000);
#else
	pr_info("\nNow, running on the frequency: %d MHz\n", freqs.new / 1000);
#endif

	return 0;
}

static int at91_cpufreq_init(struct cpufreq_policy *policy)
{
	int ret = -EINVAL;

	ret = cpufreq_frequency_table_cpuinfo(policy, cpufreq_info->freq_table);
	if (ret) {
		dev_err(cpufreq_info->dev,
				"Invalid frequency table: %d\n", ret);
		return ret;
	}

	/* set default policy and cpuinfo */
	policy->min = policy->cpuinfo.min_freq;
	policy->max = policy->cpuinfo.max_freq;
	policy->cur = cpufreq_info->cur_frequency;
	policy->cpuinfo.transition_latency = cpufreq_info->latency;
	policy->governor = CPUFREQ_DEFAULT_GOVERNOR;

	cpufreq_frequency_table_get_attr(cpufreq_info->freq_table, policy->cpu);

	dev_info(cpufreq_info->dev, "CPUFREQ support for AT91 initialized\n");

#ifdef CPUFRE_DEBUG
	led_init();
#endif

	return 0;
}

static int at91_cpufreq_exit(struct cpufreq_policy *policy)
{
	cpufreq_frequency_table_put_attr(policy->cpu);
	return 0;
}

static struct freq_attr *at91_cpufreq_attr[] = {
	&cpufreq_freq_attr_scaling_available_freqs,
	NULL,
};

static struct cpufreq_driver at91_cpufreq_driver = {
	.verify		= at91_cpufreq_verify,
	.target		= at91_cpufreq_target,
	.init		= at91_cpufreq_init,
	.exit		= at91_cpufreq_exit,
	.get		= at91_cpufreq_getspeed,
	.name		= "at91-cpufreq",
	.attr		= at91_cpufreq_attr,
};

static int of_init_cpufreq_regs_setting_table(void)
{
	const struct property *prop;
	const __be32 *val;
	int nr;
	struct cpufreq_regs_setting *regs_setting_table;
	struct device *dev = cpufreq_info->dev;

	prop = of_find_property(dev->of_node,
				"atmel,cpufreq_regs_setting", NULL);
	if (!prop)
		return -ENODEV;
	if (!prop->value)
		return -ENODATA;
	if (prop->length % sizeof(struct cpufreq_regs_setting)) {
		dev_err(dev, "%s: invalid cpufreq register setting table\n",
								__func__);
		return -EINVAL;
	}

	nr = prop->length / sizeof(struct cpufreq_regs_setting);
	cpufreq_info->regs_setting_count = nr;

	regs_setting_table = devm_kzalloc(dev,
			sizeof(struct cpufreq_regs_setting) * nr, GFP_KERNEL);
	if (!regs_setting_table) {
		dev_warn(dev, "%s: unable to allocate register setting table\n",
								__func__);
		return -ENOMEM;
	}

	cpufreq_info->regs_setting_table = regs_setting_table;

	val = prop->value;
	while (nr) {
		regs_setting_table->cpufreq_khz = be32_to_cpup(val++);
		regs_setting_table->lpddr_rtr = be32_to_cpup(val++);
		regs_setting_table->pllar_mul = be32_to_cpup(val++);
		regs_setting_table->mckr_mdiv = be32_to_cpup(val++);

		regs_setting_table++;
		nr--;
	}

	return 0;
}

static int at91_cpufreq_probe(struct platform_device *pdev)
{
	struct device_node *np;
	static struct regulator *vddcore = NULL;
	int ret = -EINVAL;

	np = pdev->dev.of_node;
	if (!np)
		return -ENODEV;

	cpufreq_info = devm_kzalloc(&pdev->dev,
				sizeof(*cpufreq_info), GFP_KERNEL);
	if (!cpufreq_info) {
		ret = -ENOMEM;
		goto err_put_node;
	}

	cpufreq_info->dev = &pdev->dev;

	np = of_find_node_by_path("/cpus/cpu@0");
	if (!np) {
		dev_err(cpufreq_info->dev, "failed to find cpu0 node\n");
		return -ENOENT;
	}

	/* We expect an OPP table supplied by platform */
	ret = opp_get_opp_count(cpufreq_info->dev);
	if (ret < 0) {
		dev_err(cpufreq_info->dev, "no OPP table is found: %d\n", ret);
		goto err_put_node;
	}
	cpufreq_info->freq_count = (u32)ret;

	ret = opp_init_cpufreq_table(cpufreq_info->dev,
					&cpufreq_info->freq_table);
	if (ret) {
		dev_err(cpufreq_info->dev,
			"failed to init cpufreq table: %d\n", ret);
		goto err_put_node;
	}

	if (of_property_read_u32(np, "clock-latency", &cpufreq_info->latency))
		cpufreq_info->latency = DEFAULT_TRANS_LATENCY;

	cpufreq_info->cur_frequency = _get_cur_freq();
	if (!cpufreq_info->cur_frequency) {
		dev_err(cpufreq_info->dev, "failed to get clock rate\n");
		ret = -EINVAL;
		goto err_free_table;
	}

	ret = of_init_cpufreq_regs_setting_table();
	if (ret) {
		dev_err(cpufreq_info->dev,
			"failed to init register setting table: %d\n", ret);
		goto err_free_table;
	}

#ifdef CONFIG_REGULATOR
	vddcore = regulator_get(&pdev->dev, "vddcore");
	if (IS_ERR(vddcore)) {
		dev_err(cpufreq_info->dev,
			"%s: unable to get the vddcore regulator\n", __func__);
		vddcore = NULL;
	} else {
		dev_info(cpufreq_info->dev, "Found vddcore regulator\n");
	}
#endif
	cpufreq_info->vddcore_reg = vddcore;

	ret = cpufreq_register_driver(&at91_cpufreq_driver);
	if (ret) {
		dev_err(cpufreq_info->dev,
			"%s: failed to register cpufreq driver\n", __func__);
#ifdef CONFIG_REGULATOR
		goto err_put_regulator;
#else
		goto err_free_table;
#endif
	}

	of_node_put(np);
	return 0;

#ifdef CONFIG_REGULATOR
err_put_regulator:
	regulator_put(cpufreq_info->vddcore_reg);
#endif

err_free_table:
	opp_free_cpufreq_table(cpufreq_info->dev, &cpufreq_info->freq_table);
err_put_node:
	of_node_put(np);
	dev_err(cpufreq_info->dev, "%s: failed initialization\n", __func__);
	return ret;
}

static int at91_cpufreq_remove(struct platform_device *pdev)
{
	cpufreq_unregister_driver(&at91_cpufreq_driver);
	opp_free_cpufreq_table(cpufreq_info->dev, &cpufreq_info->freq_table);

#ifdef CONFIG_REGULATOR
	regulator_put(cpufreq_info->vddcore_reg);
#endif

	return 0;
}

#ifdef CONFIG_REGULATOR
int regulator_cpufreq_suspend_finish(void)
{
	struct opp *opp;
	u32	volt;

	rcu_read_lock();
	opp = opp_find_freq_exact(cpufreq_info->dev,
				  cpufreq_info->cur_frequency * 1000, true);
	if (IS_ERR(opp)) {
		rcu_read_unlock();
		dev_err(cpufreq_info->dev, "failed to find OPP for %d\n",
			cpufreq_info->cur_frequency * 1000);
		return -EINVAL;
	}

	volt = opp_get_voltage(opp);
	rcu_read_unlock();

	if ((cpufreq_info->vddcore_reg)
		&& (!regulator_set_voltage(cpufreq_info->vddcore_reg,
								volt, volt)))
		pr_info("Vddcore suspend finish voltage %dmV\n", volt / 1000);

	return 0;
}
#endif

static struct platform_driver at91_cpufreq_platdrv = {
	.driver = {
		.name	= "at91-cpufreq",
		.owner	= THIS_MODULE,
	},
	.probe		= at91_cpufreq_probe,
	.remove		= at91_cpufreq_remove,
};
module_platform_driver(at91_cpufreq_platdrv);

MODULE_AUTHOR("Wenyou.Yang <wenyou.yang@atmel.com>");
MODULE_DESCRIPTION("Atmel AT91 cpufreq driver");
MODULE_LICENSE("GPL");
