// SPDX-License-Identifier: GPL-2.0-only
/*
 * Opt-in rwsem reader handoff adapted from the OnePlus 15 Game Opt driver.
 * Copyright (C) 2025 Oplus. All rights reserved.
 */

#include <linux/kernel.h>
#include <linux/list.h>
#include <linux/mutex.h>
#include <linux/proc_fs.h>
#include <linux/rculist.h>
#include <linux/sched.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <trace/hooks/rwsem.h>

#include "game_opt_ext.h"

#define RWSEM_FLAG_HANDOFF	BIT(2)
#define RWSEM_READER_SHIFT	8
#define RWSEM_PROC_PATH		OPLUS_GAME_OPT_PROC_DIR "/lock_stealing"

struct game_rwsem_task {
	struct list_head node;
	struct list_head free_node;
	struct task_struct *task;
};

typedef void (*game_rwsem_probe_t)(void *unused, struct rw_semaphore *sem,
				   long *cntp, int *ret);

static LIST_HEAD(game_rwsem_tasks);
static DEFINE_MUTEX(game_rwsem_tasks_lock);

static bool game_rwsem_task_tracked(struct task_struct *task)
{
	struct game_rwsem_task *entry;
	bool tracked = false;

	rcu_read_lock();
	list_for_each_entry_rcu(entry, &game_rwsem_tasks, node) {
		if (entry->task == task) {
			tracked = true;
			break;
		}
	}
	rcu_read_unlock();

	return tracked;
}

static void game_rwsem_read_trylock_failed(void *unused,
					   struct rw_semaphore *sem,
					   long *cntp, int *ret)
{
	if (cntp && game_rwsem_task_tracked(current))
		*cntp |= RWSEM_FLAG_HANDOFF << RWSEM_READER_SHIFT;
}

static struct game_rwsem_task *game_rwsem_find_locked(struct task_struct *task)
{
	struct game_rwsem_task *entry;

	list_for_each_entry(entry, &game_rwsem_tasks, node) {
		if (entry->task == task)
			return entry;
	}
	return NULL;
}

static void game_rwsem_clear_tasks(void)
{
	struct game_rwsem_task *entry, *next;
	LIST_HEAD(free_list);

	mutex_lock(&game_rwsem_tasks_lock);
	list_for_each_entry_safe(entry, next, &game_rwsem_tasks, node) {
		list_del_rcu(&entry->node);
		list_add(&entry->free_node, &free_list);
	}
	mutex_unlock(&game_rwsem_tasks_lock);

	synchronize_rcu();
	list_for_each_entry_safe(entry, next, &free_list, free_node) {
		list_del(&entry->free_node);
		put_task_struct(entry->task);
		kfree(entry);
	}
}

static int game_rwsem_tasks_show(struct seq_file *m, void *v)
{
	struct game_rwsem_task *entry;

	rcu_read_lock();
	list_for_each_entry_rcu(entry, &game_rwsem_tasks, node)
		seq_printf(m, "pid=%d tgid=%d name=%s\n", entry->task->pid,
			   entry->task->tgid, entry->task->comm);
	rcu_read_unlock();
	return 0;
}

static int game_rwsem_tasks_open(struct inode *inode, struct file *file)
{
	return single_open(file, game_rwsem_tasks_show, NULL);
}

static ssize_t game_rwsem_tasks_write(struct file *file,
				      const char __user *buf, size_t count,
				      loff_t *ppos)
{
	struct game_rwsem_task *entry;
	struct task_struct *task;
	char input[32];
	int pid, enable;
	size_t len;

	len = min(count, sizeof(input) - 1);
	if (copy_from_user(input, buf, len))
		return -EFAULT;
	input[len] = '\0';

	if (sscanf(input, "%d %d", &pid, &enable) != 2)
		return -EINVAL;
	if (pid <= 0) {
		game_rwsem_clear_tasks();
		return count;
	}

	task = find_get_task_by_vpid(pid);
	if (!task)
		return -ESRCH;

	mutex_lock(&game_rwsem_tasks_lock);
	entry = game_rwsem_find_locked(task);
	if (enable > 0 && !entry) {
		entry = kzalloc(sizeof(*entry), GFP_KERNEL);
		if (!entry) {
			mutex_unlock(&game_rwsem_tasks_lock);
			put_task_struct(task);
			return -ENOMEM;
		}
		entry->task = task;
		list_add_tail_rcu(&entry->node, &game_rwsem_tasks);
		task = NULL;
	} else if (enable <= 0 && entry) {
		list_del_rcu(&entry->node);
	}
	mutex_unlock(&game_rwsem_tasks_lock);

	if (enable <= 0 && entry) {
		synchronize_rcu();
		put_task_struct(entry->task);
		kfree(entry);
	}
	if (task)
		put_task_struct(task);

	return count;
}

static const struct proc_ops game_rwsem_tasks_ops = {
	.proc_open = game_rwsem_tasks_open,
	.proc_read = seq_read,
	.proc_write = game_rwsem_tasks_write,
	.proc_lseek = seq_lseek,
	.proc_release = single_release,
};

int oplus_rwsem_opt_init(void)
{
	game_rwsem_probe_t probe = game_rwsem_read_trylock_failed;
	int ret;

	if (!proc_create(RWSEM_PROC_PATH, 0664, NULL, &game_rwsem_tasks_ops))
		return -ENOMEM;

	ret = register_trace_android_vh_rwsem_read_trylock_failed(probe, NULL);
	if (ret) {
		remove_proc_entry(RWSEM_PROC_PATH, NULL);
		return ret;
	}
	return 0;
}

void oplus_rwsem_opt_exit(bool remove_proc)
{
	game_rwsem_probe_t probe = game_rwsem_read_trylock_failed;

	unregister_trace_android_vh_rwsem_read_trylock_failed(probe, NULL);
	if (remove_proc)
		remove_proc_entry(RWSEM_PROC_PATH, NULL);
	game_rwsem_clear_tasks();
}
