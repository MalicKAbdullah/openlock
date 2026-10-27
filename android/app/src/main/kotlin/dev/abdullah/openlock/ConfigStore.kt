package dev.abdullah.openlock

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * The enforcement config the native monitor reads, plus the intruder log,
 * stored in EncryptedSharedPreferences (androidx.security.crypto). The Flutter
 * app is the source of truth and pushes the enforcement subset here via the
 * MethodChannel; the service only ever reads it.
 *
 * One instance per process ([get]): building EncryptedSharedPreferences
 * (MasterKey lookup + Tink keyset decrypts through the Keystore) is the
 * expensive part, and the monitor service, the notification listener, the
 * lock overlay and the Flutter plugin all run in this process. Because every write to the prefs file goes
 * through this instance, the parsed config can be cached and replaced on
 * [saveConfig].
 */
class ConfigStore private constructor(context: Context) {

    private val prefs: SharedPreferences = createPrefs(context)

    @Volatile
    private var config: JSONObject? = parse(prefs.getString(KEY_CONFIG, null))

    private fun createPrefs(context: Context): SharedPreferences {
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (e: Exception) {
            // Extremely rare keystore failure — degrade to private prefs so the
            // app still functions rather than crashing the service.
            context.getSharedPreferences("${PREFS_NAME}_fallback", Context.MODE_PRIVATE)
        }
    }

    fun saveConfig(json: String) {
        prefs.edit().putString(KEY_CONFIG, json).apply()
        config = parse(json)
    }

    private fun parse(raw: String?): JSONObject? {
        if (raw == null) return null
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            null
        }
    }

    fun hasConfig(): Boolean = config != null

    fun lockedPackages(): Set<String> {
        val array = config?.optJSONArray("lockedPackages") ?: return emptySet()
        val set = HashSet<String>(array.length())
        for (i in 0 until array.length()) set.add(array.optString(i))
        return set
    }

    fun schedules(): JSONArray = config?.optJSONArray("schedules") ?: JSONArray()

    fun relockMode(): String = config?.optString("relockMode", "immediately") ?: "immediately"

    fun relockTimeoutMinutes(): Int = config?.optInt("relockTimeoutMinutes", 1) ?: 1

    fun randomizeKeypad(): Boolean = config?.optBoolean("randomizeKeypad", false) ?: false

    fun intruderCaptureEnabled(): Boolean =
        config?.optBoolean("intruderCaptureEnabled", false) ?: false

    fun intruderThreshold(): Int = config?.optInt("intruderThreshold", 3) ?: 3

    fun fakeCoverEnabled(): Boolean = config?.optBoolean("fakeCoverEnabled", false) ?: false

    fun preventUninstall(): Boolean = config?.optBoolean("preventUninstall", false) ?: false

    /** Global default for hiding locked apps' notification content. */
    fun hideNotifications(): Boolean = config?.optBoolean("hideNotifications", false) ?: false

    /** Per-package explicit overrides of [hideNotifications]; package → on/off. */
    private fun notificationOverrides(): Map<String, Boolean> {
        val obj = config?.optJSONObject("notificationOverrides") ?: return emptyMap()
        val map = HashMap<String, Boolean>(obj.length())
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = obj.optBoolean(key)
        }
        return map
    }

    /**
     * Whether the notification listener should redact notifications from [pkg].
     * Only locked apps qualify; the per-app override wins over the global flag.
     * Mirror of the Dart `LockConfig.hidesNotificationsFor`.
     */
    fun shouldHideNotificationsFor(pkg: String): Boolean {
        if (!lockedPackages().contains(pkg)) return false
        return notificationOverrides()[pkg] ?: hideNotifications()
    }

    fun biometricEnabled(): Boolean = config?.optBoolean("biometricEnabled", false) ?: false

    fun pinHash(): String? = config?.optString("pinHash")?.ifBlank { null }

    fun pinSalt(): String? = config?.optString("pinSalt")?.ifBlank { null }

    fun pinIterations(): Int = config?.optInt("pinIterations", 120000) ?: 120000

    // --- Intruder log -------------------------------------------------------

    private fun intruderArray(): JSONArray {
        val raw = prefs.getString(KEY_INTRUDERS, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (e: Exception) {
            JSONArray()
        }
    }

    fun addIntruder(packageName: String, timestamp: Long, photoPath: String?) {
        val array = intruderArray()
        val entry = JSONObject().apply {
            put("id", UUID.randomUUID().toString())
            put("package", packageName)
            put("timestamp", timestamp)
            put("photoPath", photoPath ?: JSONObject.NULL)
        }
        array.put(entry)
        prefs.edit().putString(KEY_INTRUDERS, array.toString()).apply()
    }

    fun intruderRecords(): List<Map<String, Any?>> {
        val array = intruderArray()
        val list = ArrayList<Map<String, Any?>>(array.length())
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            list.add(
                mapOf(
                    "id" to obj.optString("id"),
                    "package" to obj.optString("package"),
                    "timestamp" to obj.optLong("timestamp"),
                    "photoPath" to obj.opt("photoPath").let {
                        if (it == JSONObject.NULL) null else it as? String
                    },
                ),
            )
        }
        return list
    }

    fun deleteIntruder(id: String) {
        val array = intruderArray()
        val kept = JSONArray()
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            if (obj.optString("id") != id) {
                kept.put(obj)
            } else {
                (obj.opt("photoPath") as? String)?.let { path ->
                    runCatching { java.io.File(path).delete() }
                }
            }
        }
        prefs.edit().putString(KEY_INTRUDERS, kept.toString()).apply()
    }

    fun clearIntruders() {
        val array = intruderArray()
        for (i in 0 until array.length()) {
            (array.optJSONObject(i)?.opt("photoPath") as? String)?.let { path ->
                runCatching { java.io.File(path).delete() }
            }
        }
        prefs.edit().remove(KEY_INTRUDERS).apply()
    }

    companion object {
        @Volatile
        private var instance: ConfigStore? = null

        fun get(context: Context): ConfigStore =
            instance ?: synchronized(this) {
                instance ?: ConfigStore(context.applicationContext).also { instance = it }
            }

        private const val PREFS_NAME = "openlock_enforcement"
        private const val KEY_CONFIG = "config"
        private const val KEY_INTRUDERS = "intruders"
    }
}
