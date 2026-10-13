/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _OPLUS_GAME_OPT_H
#define _OPLUS_GAME_OPT_H

struct proc_dir_entry;

int oplus_hybrid_frame_sync_init(struct proc_dir_entry *parent);
void oplus_hybrid_frame_sync_exit(struct proc_dir_entry *parent);

int oplus_rwsem_opt_init(struct proc_dir_entry *parent);
void oplus_rwsem_opt_exit(struct proc_dir_entry *parent);

#endif /* _OPLUS_GAME_OPT_H */
