/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _OPLUS_GAME_OPT_EXT_H
#define _OPLUS_GAME_OPT_EXT_H

#define OPLUS_GAME_OPT_VENDOR_MODULE	"oplus_bsp_game_opt"
#define OPLUS_GAME_OPT_PROC_DIR		"game_opt"

int oplus_hybrid_frame_sync_init(void);
void oplus_hybrid_frame_sync_exit(bool remove_proc);

int oplus_rwsem_opt_init(void);
void oplus_rwsem_opt_exit(bool remove_proc);

#endif /* _OPLUS_GAME_OPT_EXT_H */
