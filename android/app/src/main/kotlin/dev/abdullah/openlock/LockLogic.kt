package dev.abdullah.openlock

import org.json.JSONArray
import java.util.Calendar

/**
 * Kotlin mirror of the Dart LockScheduleEvaluator and LockPolicyEngine. The
 * Dart versions are the exhaustively-tested source of truth; these keep the
 * running service in lockstep with them.
 */
object LockLogic {

    /** Packages locked right now by any enabled schedule. */
    fun scheduledLockedPackages(schedules: JSONArray, now: Calendar): Set<String> {
        val locked = HashSet<String>()
        for (i in 0 until schedules.length()) {
            val s = schedules.optJSONObject(i) ?: continue
            if (!s.optBoolean("enabled", true)) continue
            if (isScheduleActive(s, now)) {
                val pkgs = s.optJSONArray("packages") ?: continue
                for (j in 0 until pkgs.length()) locked.add(pkgs.optString(j))
            }
        }
        return locked
    }

    private fun isScheduleActive(
        schedule: org.json.JSONObject,
        now: Calendar,
    ): Boolean {
        val start = schedule.optInt("startMinutes", 0)
        val end = schedule.optInt("endMinutes", 0)
        val days = HashSet<Int>()
        schedule.optJSONArray("weekdays")?.let { arr ->
            for (i in 0 until arr.length()) days.add(arr.optInt(i))
        }

        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val today = dartWeekday(now.get(Calendar.DAY_OF_WEEK))
        val yesterday = if (today == 1) 7 else today - 1

        // All-day window.
        if (start == end) return days.contains(today)

        if (end >= start) {
            // Same-day window: [start, end).
            return days.contains(today) && nowMinutes >= start && nowMinutes < end
        }

        // Overnight window (belongs to the day it starts on).
        val evening = days.contains(today) && nowMinutes >= start
        val morning = days.contains(yesterday) && nowMinutes < end
        return evening || morning
    }

    /** Convert Calendar.DAY_OF_WEEK (1=Sun..7=Sat) to Dart weekday (1=Mon..7=Sun). */
    private fun dartWeekday(calendarDow: Int): Int =
        if (calendarDow == Calendar.SUNDAY) 7 else calendarDow - 1

    /**
     * The relock decision. [unlockedAt]/[leftAppAt]/[screenOffAt] use 0 to mean
     * "not happened". Mirrors the Dart LockPolicyEngine.
     */
    fun isLocked(
        mode: String,
        timeoutMinutes: Int,
        unlockedAt: Long,
        leftAppAt: Long,
        screenOffAt: Long,
        now: Long,
    ): Boolean {
        if (unlockedAt == 0L) return true
        if (screenOffAt > unlockedAt) return true
        val leftAfterUnlock = leftAppAt > unlockedAt
        return when (mode) {
            "onScreenOff" -> false
            "afterTimeout" ->
                if (!leftAfterUnlock) false
                else (now - leftAppAt) >= timeoutMinutes.toLong() * 60_000L
            else -> leftAfterUnlock // "immediately"
        }
    }
}
