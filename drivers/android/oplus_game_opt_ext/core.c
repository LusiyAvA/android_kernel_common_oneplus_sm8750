// SPDX-License-Identifier: GPL-2.0-only
/* Copyright (C) 2024-2026 Oplus. All rights reserved. */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/notifier.h>
#include <linux/string.h>

#include "game_opt_ext.h"

static bool game_opt_ext_ready;

static int oplus_game_opt_ext_enable(void)
{
	int ret;

	if (game_opt_ext_ready)
		return 0;

	ret = oplus_hybrid_frame_sync_init();
	if (ret)
		return ret;

	ret = oplus_rwsem_opt_init();
	if (ret) {
		oplus_hybrid_frame_sync_exit(true);
		return ret;
	}

	game_opt_ext_ready = true;
	pr_info("oplus_game_opt_ext: Hybrid Frame Sync and rwsem optimization ready\n");
	return 0;
}

static void oplus_game_opt_ext_disable(bool remove_proc)
{
	if (!game_opt_ext_ready)
		return;

	oplus_rwsem_opt_exit(remove_proc);
	oplus_hybrid_frame_sync_exit(remove_proc);
	game_opt_ext_ready = false;
}

static int oplus_game_opt_ext_module_event(struct notifier_block *nb,
					   unsigned long action, void *data)
{
	struct module *mod = data;
	int ret;

	if (strcmp(module_name(mod), OPLUS_GAME_OPT_VENDOR_MODULE))
		return NOTIFY_DONE;

	switch (action) {
	case MODULE_STATE_LIVE:
		ret = oplus_game_opt_ext_enable();
		if (ret)
			pr_err("oplus_game_opt_ext: failed to attach to %s: %d\n",
			       module_name(mod), ret);
		break;
	case MODULE_STATE_GOING:
		/* The vendor module has already run its exit and removed its proc tree. */
		oplus_game_opt_ext_disable(false);
		break;
	default:
		break;
	}

	/* The extension must never prevent the vendor module from loading. */
	return NOTIFY_DONE;
}

static struct notifier_block game_opt_ext_module_nb = {
	.notifier_call = oplus_game_opt_ext_module_event,
};

static int __init oplus_game_opt_ext_init(void)
{
	int ret;

	ret = register_module_notifier(&game_opt_ext_module_nb);
	if (ret)
		return ret;

	pr_info("oplus_game_opt_ext: waiting for %s\n",
		OPLUS_GAME_OPT_VENDOR_MODULE);
	return 0;
}

static void __exit oplus_game_opt_ext_exit(void)
{
	unregister_module_notifier(&game_opt_ext_module_nb);
	oplus_game_opt_ext_disable(true);
}

module_init(oplus_game_opt_ext_init);
module_exit(oplus_game_opt_ext_exit);

MODULE_DESCRIPTION("Oplus Game Opt extensions for the vendor game module");
MODULE_LICENSE("GPL");
