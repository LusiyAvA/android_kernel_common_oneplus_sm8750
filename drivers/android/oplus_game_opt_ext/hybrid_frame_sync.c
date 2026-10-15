// SPDX-License-Identifier: GPL-2.0-only
/*
 * Hybrid Frame Sync ABI adapted from the OnePlus 15 Game Opt driver.
 * Copyright (C) 2024-2025 Oplus. All rights reserved.
 */

#include <linux/compat.h>
#include <linux/fs.h>
#include <linux/proc_fs.h>
#include <linux/spinlock.h>
#include <linux/sysctl.h>
#include <linux/uaccess.h>

#include "game_opt_ext.h"
#include "hybrid_frame_sync.h"

#define HFS_BUFFER_CAPACITY	16
#define HFS_BUFFER_MASK		(HFS_BUFFER_CAPACITY - 1)
#define HFS_PROC_MODE		0666
#define HFS_PROC_PATH		OPLUS_GAME_OPT_PROC_DIR "/hfs_ctrl"

static DEFINE_SPINLOCK(hfs_lock);
static DEFINE_CTL_TABLE_POLL(hybrid_frame_poll);
static struct hybrid_frame_data hfs_events[HFS_BUFFER_CAPACITY];
static unsigned int hfs_begin;
static unsigned int hfs_end;
static struct ctl_table_header *hfs_sysctl_header;

static unsigned int hfs_size(void)
{
	return (hfs_end + HFS_BUFFER_CAPACITY - hfs_begin) & HFS_BUFFER_MASK;
}

static int hfs_sysctl_poll(struct ctl_table *table, int write,
			   void *buffer, size_t *lenp, loff_t *ppos)
{
	return -EOPNOTSUPP;
}

static struct ctl_table hfs_sysctl_table[] = {
	{
		.procname = "hybrid_frame",
		.mode = 0664,
		.proc_handler = hfs_sysctl_poll,
		.poll = &hybrid_frame_poll,
	},
	{}
};

static void hfs_notify(void)
{
	proc_sys_poll_notify(&hybrid_frame_poll);
}

static long hfs_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	struct hybrid_frame_data event;
	void __user *uarg = (void __user *)arg;
	unsigned long flags;
	long ret = 0;

	if (_IOC_TYPE(cmd) != HYBRID_FRAME_SYNC_MAGIC ||
	    _IOC_NR(cmd) >= FRAME_HYBRID_MAX_ID)
		return -EINVAL;

	switch (cmd) {
	case CMD_ID_FRAME_HYBRID_WR:
		if (copy_from_user(&event, uarg, sizeof(event)))
			return -EFAULT;

		spin_lock_irqsave(&hfs_lock, flags);
		if (hfs_size() == HFS_BUFFER_MASK)
			hfs_begin = (hfs_begin + 1) & HFS_BUFFER_MASK;
		hfs_events[hfs_end] = event;
		hfs_end = (hfs_end + 1) & HFS_BUFFER_MASK;
		spin_unlock_irqrestore(&hfs_lock, flags);
		hfs_notify();
		break;

	case CMD_ID_FRAME_HYBRID_RD:
		spin_lock_irqsave(&hfs_lock, flags);
		if (hfs_begin == hfs_end) {
			ret = -EAGAIN;
		} else {
			event = hfs_events[hfs_begin];
			hfs_begin = (hfs_begin + 1) & HFS_BUFFER_MASK;
			event.end = hfs_begin == hfs_end;
		}
		spin_unlock_irqrestore(&hfs_lock, flags);
		if (!ret && copy_to_user(uarg, &event, sizeof(event)))
			ret = -EFAULT;
		break;

	case CMD_ID_FRAME_HYBRID_WAKE:
		spin_lock_irqsave(&hfs_lock, flags);
		hfs_begin = 0;
		hfs_end = 0;
		spin_unlock_irqrestore(&hfs_lock, flags);
		hfs_notify();
		break;

	default:
		ret = -EINVAL;
	}

	return ret;
}

#ifdef CONFIG_COMPAT
static long hfs_compat_ioctl(struct file *file, unsigned int cmd,
			     unsigned long arg)
{
	return hfs_ioctl(file, cmd, (unsigned long)compat_ptr(arg));
}
#endif

static const struct proc_ops hfs_proc_ops = {
	.proc_ioctl = hfs_ioctl,
#ifdef CONFIG_COMPAT
	.proc_compat_ioctl = hfs_compat_ioctl,
#endif
	.proc_lseek = noop_llseek,
};

int oplus_hybrid_frame_sync_init(void)
{
	unsigned long flags;

	spin_lock_irqsave(&hfs_lock, flags);
	hfs_begin = 0;
	hfs_end = 0;
	spin_unlock_irqrestore(&hfs_lock, flags);

	if (!proc_create(HFS_PROC_PATH, HFS_PROC_MODE, NULL, &hfs_proc_ops))
		return -ENOMEM;

	hfs_sysctl_header = register_sysctl("game_frame_sync", hfs_sysctl_table);
	if (!hfs_sysctl_header) {
		remove_proc_entry(HFS_PROC_PATH, NULL);
		return -ENOMEM;
	}

	return 0;
}

void oplus_hybrid_frame_sync_exit(bool remove_proc)
{
	if (hfs_sysctl_header) {
		unregister_sysctl_table(hfs_sysctl_header);
		hfs_sysctl_header = NULL;
	}
	if (remove_proc)
		remove_proc_entry(HFS_PROC_PATH, NULL);
}
