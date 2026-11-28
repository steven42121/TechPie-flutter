package club.geekpie.techpie.island

import android.content.Intent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IslandTimelineRebuildTest {
    @Test
    fun clockAndLifecycleChangesRequestATimelineRebuild() {
        val actions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )

        actions.forEach { assertTrue(IslandRestoreReceiver.shouldRebuildForAction(it)) }
        assertFalse(IslandRestoreReceiver.shouldRebuildForAction("unrelated"))
    }
}
