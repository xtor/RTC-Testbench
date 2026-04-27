// SPDX-License-Identifier: BSD-2-Clause
/*
 * Copyright (C) 2022-2025 Linutronix GmbH
 * Author Kurt Kanzenbach <kurt@linutronix.de>
 */

#include "tx_time.h"

#include "config.h"
#include "log.h"
#include "utils.h"

uint64_t tx_time_get_frame_duration(uint32_t link_speed, size_t frame_length)
{
	uint64_t duration_ns;

	/* ((frameLength * 8) / (linkSpeed * 1000000ULL)) * 1000000000ULL */
	duration_ns = (frame_length * 8 * 1000) / link_speed;

	return duration_ns;
}

uint64_t tx_time_get_frame_tx_time(uint64_t sequence_counter, uint64_t duration,
				   size_t num_frames_per_cycle, uint64_t tx_time_offset,
				   const char *traffic_class)
{
	const uint64_t cycle_time = app_config.application_base_cycle_time_ns;
	uint64_t tx_time, base_time, now_ns, past_cycles;
	struct timespec now;

	/*
	 * Calculate frame transmission time for next cycle. txTimeOffset is used to specify the
	 * offset within cycle, which has to be aligned with configured Qbv schedule.
	 *
	 *   BaseTime + TxOffset +
	 *   (sequenceCounter % numFramesPerCycle) * duration
	 *
	 *   |---------------------------|---------------------------|
	 *   ^BaseTime of n-1            BaseTime of n   ^^^^^^
	 *
	 * All calculations are performed in nanoseconds.
	 */

	app_clock_get(&now);
	now_ns = ts_to_ns(&now);
	past_cycles = (now_ns - app_config.application_base_start_time_ns) / cycle_time;
	base_time = (past_cycles + 1) * cycle_time + app_config.application_base_start_time_ns;

	tx_time = base_time + tx_time_offset + (sequence_counter % num_frames_per_cycle) * duration;

	/*
	 * TxTime has to be in the future. If not the frame will be dropped by ETF Qdisc. This may
	 * happen due to delays, preemption and so on. Inform the user accordingly.
	 */
	if (tx_time <= now_ns)
		log_message(LOG_LEVEL_ERROR, "%sTx: TxTime not in future!\n", traffic_class);

	return tx_time;
}
