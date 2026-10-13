// SPDX-License-Identifier: GPL-2.0-only
/* Copyright (C) 2024-2025 Oplus. All rights reserved. */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/proc_fs.h>

#include "game_opt.h"

static struct proc_dir_entry *game_opt_dir;

static int __init oplus_game_opt_init(void)
{
	int ret;

	game_opt_dir = proc_mkdir("game_opt", NULL);
	if (!game_opt_dir)
		return -ENOMEM;

	ret = oplus_hybrid_frame_sync_init(game_opt_dir);
	if (ret)
		goto remove_dir;

	ret = oplus_rwsem_opt_init(game_opt_dir);
	if (ret)
		goto remove_hfs;

	pr_info("oplus_game_opt: hybrid frame sync and rwsem optimization ready\n");
	return 0;

remove_hfs:
	oplus_hybrid_frame_sync_exit(game_opt_dir);
remove_dir:
	remove_proc_subtree("game_opt", NULL);
	game_opt_dir = NULL;
	return ret;
}

static void __exit oplus_game_opt_exit(void)
{
	if (!game_opt_dir)
		return;
	oplus_rwsem_opt_exit(game_opt_dir);
	oplus_hybrid_frame_sync_exit(game_opt_dir);
	remove_proc_subtree("game_opt", NULL);
	game_opt_dir = NULL;
}

module_init(oplus_game_opt_init);
module_exit(oplus_game_opt_exit);

MODULE_DESCRIPTION("Oplus Game Opt compatibility layer");
MODULE_LICENSE("GPL v2");
