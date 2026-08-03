

/* ---- drivers/md/raid5.c (excerpts, FW v5.1.22) ---- */

static void do_release_stripe(struct r5conf *conf, struct stripe_head *sh,
			      struct list_head *temp_inactive_list)
{
	int i;
	int injournal = 0;	/* number of date pages with R5_InJournal */

	BUG_ON(!list_empty(&sh->lru));
	BUG_ON(atomic_read(&conf->active_stripes)==0);

	if (r5c_is_writeback(conf->log))
		for (i = sh->disks; i--; )
			if (test_bit(R5_InJournal, &sh->dev[i].flags))
				injournal++;
	/*
	 * In the following cases, the stripe cannot be released to cached
	 * lists. Therefore, we make the stripe write out and set
	 * STRIPE_HANDLE:
	 *   1. when quiesce in r5c write back;
	 *   2. when resync is requested fot the stripe.
	 */
	if (test_bit(STRIPE_SYNC_REQUESTED, &sh->state) ||
	    (conf->quiesce && r5c_is_writeback(conf->log) &&
	     !test_bit(STRIPE_HANDLE, &sh->state) && injournal != 0)) {
		if (test_bit(STRIPE_R5C_CACHING, &sh->state))
			r5c_make_stripe_write_out(sh);
		set_bit(STRIPE_HANDLE, &sh->state);
	}

	if (test_bit(STRIPE_HANDLE, &sh->state)) {
		if (test_bit(STRIPE_DELAYED, &sh->state) &&
		    !test_bit(STRIPE_PREREAD_ACTIVE, &sh->state))
			list_add_tail(&sh->lru, &conf->delayed_list);
		else if (test_bit(STRIPE_BIT_DELAY, &sh->state) &&
			   sh->bm_seq - conf->seq_write > 0)
			list_add_tail(&sh->lru, &conf->bitmap_list);
		else {
			clear_bit(STRIPE_DELAYED, &sh->state);
			clear_bit(STRIPE_BIT_DELAY, &sh->state);
			if (conf->worker_cnt_per_group == 0) {
				if (stripe_is_lowprio(sh))
					list_add_tail(&sh->lru,
							&conf->loprio_list);
				else
					list_add_tail(&sh->lru,
							&conf->handle_list);
			} else {
				raid5_wakeup_stripe_thread(sh);
				return;
			}
		}
		md_wakeup_thread(conf->mddev->thread);
	} else {
		BUG_ON(stripe_operations_active(sh));
		if (test_and_clear_bit(STRIPE_PREREAD_ACTIVE, &sh->state))
			if (atomic_dec_return(&conf->preread_active_stripes)
			    < IO_THRESHOLD)
				md_wakeup_thread(conf->mddev->thread);
		atomic_dec(&conf->active_stripes);
		if (!test_bit(STRIPE_EXPANDING, &sh->state)) {
			if (!r5c_is_writeback(conf->log))
				list_add_tail(&sh->lru, temp_inactive_list);
			else {
				WARN_ON(test_bit(R5_InJournal, &sh->dev[sh->pd_idx].flags));
				if (injournal == 0)
					list_add_tail(&sh->lru, temp_inactive_list);
				else if (injournal == conf->raid_disks - conf->max_degraded) {
					/* full stripe */
					if (!test_and_set_bit(STRIPE_R5C_FULL_STRIPE, &sh->state))
						atomic_inc(&conf->r5c_cached_full_stripes);
					if (test_and_clear_bit(STRIPE_R5C_PARTIAL_STRIPE, &sh->state))
						atomic_dec(&conf->r5c_cached_partial_stripes);
					list_add_tail(&sh->lru, &conf->r5c_full_stripe_list);
					r5c_check_cached_full_stripe(conf);
				} else
					/*
					 * STRIPE_R5C_PARTIAL_STRIPE is set in
					 * r5c_try_caching_write(). No need to
					 * set it again.
					 */
					list_add_tail(&sh->lru, &conf->r5c_partial_stripe_list);

static void raid5_activate_delayed(struct r5conf *conf)
{
	if (atomic_read(&conf->preread_active_stripes) < IO_THRESHOLD) {
		while (!list_empty(&conf->delayed_list)) {
			struct list_head *l = conf->delayed_list.next;
			struct stripe_head *sh;
			sh = list_entry(l, struct stripe_head, lru);
			list_del_init(l);
			clear_bit(STRIPE_DELAYED, &sh->state);
			if (!test_and_set_bit(STRIPE_PREREAD_ACTIVE, &sh->state))
				atomic_inc(&conf->preread_active_stripes);
			list_add_tail(&sh->lru, &conf->hold_list);
			raid5_wakeup_stripe_thread(sh);
		}
	}
}

static void raid5_unplug(struct blk_plug_cb *blk_cb, bool from_schedule)
{
	struct raid5_plug_cb *cb = container_of(
		blk_cb, struct raid5_plug_cb, cb);
	struct stripe_head *sh;
	struct mddev *mddev = cb->cb.data;
	struct r5conf *conf = mddev->private;
	int cnt = 0;
	int hash;

	if (cb->list.next && !list_empty(&cb->list)) {
		spin_lock_irq(&conf->device_lock);
		while (!list_empty(&cb->list)) {
			sh = list_first_entry(&cb->list, struct stripe_head, lru);
			list_del_init(&sh->lru);
			/*
			 * avoid race release_stripe_plug() sees
			 * STRIPE_ON_UNPLUG_LIST clear but the stripe
			 * is still in our list
			 */
			smp_mb__before_atomic();
			clear_bit(STRIPE_ON_UNPLUG_LIST, &sh->state);
			/*
			 * STRIPE_ON_RELEASE_LIST could be set here. In that
			 * case, the count is always > 1 here
			 */
			hash = sh->hash_lock_index;
			__release_stripe(conf, sh, &cb->temp_inactive_list[hash]);
			cnt++;
		}
		spin_unlock_irq(&conf->device_lock);
	}
	release_inactive_stripe_list(conf, cb->temp_inactive_list,
				     NR_STRIPE_HASH_LOCKS);
	if (mddev->queue)
		trace_block_unplug(mddev->queue, cnt, !from_schedule);
	kfree(cb);
}

static void release_stripe_plug(struct mddev *mddev,
				struct stripe_head *sh)
{
	struct blk_plug_cb *blk_cb = blk_check_plugged(
		raid5_unplug, mddev,
		sizeof(struct raid5_plug_cb));
	struct raid5_plug_cb *cb;

	if (!blk_cb) {
		raid5_release_stripe(sh);
		return;
	}

	cb = container_of(blk_cb, struct raid5_plug_cb, cb);

	if (cb->list.next == NULL) {
		int i;
		INIT_LIST_HEAD(&cb->list);
		for (i = 0; i < NR_STRIPE_HASH_LOCKS; i++)
			INIT_LIST_HEAD(cb->temp_inactive_list + i);
	}

	if (!test_and_set_bit(STRIPE_ON_UNPLUG_LIST, &sh->state))
		list_add_tail(&sh->lru, &cb->list);
	else
		raid5_release_stripe(sh);
}