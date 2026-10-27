package dev.abdullah.openlock

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for the pure notification-hiding decisions. */
class NotificationRedactionTest {

    private fun decide(
        hide: Boolean = true,
        ongoing: Boolean = false,
        foregroundService: Boolean = false,
        groupSummary: Boolean = false,
        media: Boolean = false,
        category: String? = null,
    ) = NotificationRedaction.shouldRedact(
        hideEnabledForApp = hide,
        isOngoing = ongoing,
        isForegroundService = foregroundService,
        isGroupSummary = groupSummary,
        isMediaSession = media,
        category = category,
    )

    @Test
    fun redactsAnOrdinaryMessageFromAHiddenApp() {
        assertTrue(decide())
        assertTrue(decide(category = "msg"))
        assertTrue(decide(category = "email"))
    }

    @Test
    fun neverRedactsWhenHidingIsOffForTheApp() {
        assertFalse(decide(hide = false))
        // Hiding-off wins even over otherwise-redactable content.
        assertFalse(decide(hide = false, category = "msg"))
    }

    @Test
    fun leavesOngoingAndForegroundServiceNoticesAlone() {
        assertFalse(decide(ongoing = true))
        assertFalse(decide(foregroundService = true))
    }

    @Test
    fun leavesGroupSummariesAlone() {
        // The per-message children are redacted; swallowing the bundle header
        // too would leave an empty group.
        assertFalse(decide(groupSummary = true))
    }

    @Test
    fun leavesMediaAndTimeCriticalCategoriesAlone() {
        assertFalse(decide(media = true))
        assertFalse(decide(category = "call"))
        assertFalse(decide(category = "alarm"))
        assertFalse(decide(category = "transport"))
        assertFalse(decide(category = "event"))
        assertFalse(decide(category = "reminder"))
    }

    @Test
    fun categoryMatchIsCaseInsensitive() {
        assertFalse(decide(category = "CALL"))
        assertFalse(decide(category = "Alarm"))
    }

    @Test
    fun summaryTextRedactsToAppLabelAndCountOnly() {
        assertEquals("WhatsApp · 1 new notification", NotificationRedaction.summaryText("WhatsApp", 1))
        assertEquals("WhatsApp · 2 new notifications", NotificationRedaction.summaryText("WhatsApp", 2))
        assertEquals("Signal · 9 new notifications", NotificationRedaction.summaryText("Signal", 9))
    }

    @Test
    fun summaryTextClampsNonPositiveCountsToOne() {
        assertEquals("Mail · 1 new notification", NotificationRedaction.summaryText("Mail", 0))
        assertEquals("Mail · 1 new notification", NotificationRedaction.summaryText("Mail", -5))
    }

    @Test
    fun groupingKeysAndIdsAreStablePerPackage() {
        assertEquals(
            NotificationRedaction.groupKey("com.whatsapp"),
            NotificationRedaction.groupKey("com.whatsapp"),
        )
        assertEquals(
            NotificationRedaction.notificationId("com.whatsapp"),
            "com.whatsapp".hashCode(),
        )
    }
}
