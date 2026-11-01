package com.music.bitchord.data.settings

import java.io.File

/**
 * CPU budget for Automix's background analysis, not its audible mix algorithm.
 *
 * Inzx: BitChord fixed these at 1/2/4 threads. Here they're sized from the
 * phone's own cores, so an 8-core phone with four fast cores gets four, a
 * phone whose cores are all fast gets all of them, and a small phone never
 * gets more threads than it can run at once.
 */
enum class AutomixPerformanceMode {
    EFFICIENT,
    BALANCED,
    PERFORMANCE,
    ;

    val inferenceThreads: Int
        get() = when (this) {
            EFFICIENT -> 1
            BALANCED -> (CpuCores.fast / 2).coerceIn(2, CpuCores.fast.coerceAtLeast(2))
            PERFORMANCE -> CpuCores.fast.coerceAtLeast(2)
        }

    /** Whether analysis should yield to playback rather than compete with it. */
    val yieldsToPlayback: Boolean get() = this == EFFICIENT
}

/**
 * The phone's cores, and how many of them are fast. Intra-op threads that
 * land on the slow (little) cluster hold every run back to that cluster's
 * pace, so analysis is only given the cores that aren't little.
 */
object CpuCores {
    val total: Int by lazy { Runtime.getRuntime().availableProcessors().coerceAtLeast(1) }

    val fast: Int by lazy { countFast() ?: (total / 2).coerceAtLeast(1) }

    /** Cores whose top clock is within 70% of the fastest core's. */
    private fun countFast(): Int? = runCatching {
        val freqs = (0 until total).mapNotNull { cpu ->
            File("/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq")
                .takeIf { it.canRead() }
                ?.readText()?.trim()?.toLongOrNull()
        }
        if (freqs.size != total || freqs.isEmpty()) return@runCatching null
        val top = freqs.max()
        freqs.count { it >= top * 0.7 }
    }.getOrNull()?.takeIf { it > 0 }
}
