package com.dedem.fatkatalog

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Dart tarafındaki `NativeBridge` (lib/platform/native_bridge.dart) için platform kanalı:
 * okutma geri bildirimi (bip + titreşim), sürüm bilgisi ve Download klasörüne kaydetme.
 */
class MainActivity : FlutterActivity() {

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var tone: ToneGenerator? = null

    /** Android 8–9: "Farklı kaydet" penceresinin sonucu bekleniyor. */
    private var pendingSave: PendingSave? = null

    /** Yedek dosyası seçme penceresinin sonucu bekleniyor. */
    private var pendingPick: MethodChannel.Result? = null

    private class PendingSave(val source: File, val result: MethodChannel.Result)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "feedback" -> {
                        feedback(call.arguments as? String ?: "error")
                        result.success(null)
                    }
                    "appVersion" -> result.success(appVersion())
                    "hasCameraPermission" -> result.success(
                        checkSelfPermission(Manifest.permission.CAMERA) ==
                            PackageManager.PERMISSION_GRANTED,
                    )
                    "openAppSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null),
                            ),
                        )
                        result.success(null)
                    }
                    "saveToDownloads" -> saveToDownloads(
                        source = File(call.argument<String>("sourcePath")!!),
                        fileName = call.argument<String>("fileName")!!,
                        mimeType = call.argument<String>("mimeType")!!,
                        result = result,
                    )
                    "pickFile" -> pickFile(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        tone?.release()
        tone = null
        io.shutdown()
        super.onDestroy()
    }

    // --- Geri bildirim ---------------------------------------------------------------------

    private fun feedback(kind: String) {
        when (kind) {
            "success" -> {
                vibrate(longArrayOf(0, 80))
                beep()
            }
            // Tekrar: iki uzun darbe; hata: tek uzun darbe.
            "warning" -> vibrate(longArrayOf(0, 300, 150, 300))
            else -> vibrate(longArrayOf(0, 600))
        }
    }

    private fun beep() {
        try {
            val generator = tone ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 100)
                .also { tone = it }
            generator.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
        } catch (e: RuntimeException) {
            // Ses donanımı meşgulse sessiz geç; titreşim yine çalışır.
        }
    }

    private fun vibrate(pattern: LongArray) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
    }

    private fun appVersion(): String {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
        return info.versionName ?: "?"
    }

    // --- Download klasörüne kaydetme ------------------------------------------------------

    private fun saveToDownloads(
        source: File,
        fileName: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            io.execute {
                try {
                    val savedName = saveWithMediaStore(source, fileName, mimeType)
                    main.post { result.success("İndirilenler/$DOWNLOAD_SUBDIR/$savedName") }
                } catch (e: Exception) {
                    main.post { result.error("save_failed", e.message, null) }
                }
            }
        } else {
            // Android 8–9: izin istemeden sistemin "Farklı kaydet" penceresi.
            if (pendingSave != null) {
                result.error("busy", "Başka bir kaydetme işlemi sürüyor", null)
                return
            }
            pendingSave = PendingSave(source, result)
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_CREATE_DOCUMENT)
        }
    }

    /** Android 10+: Download/FATKatalog/ altına yazar; aynı ad varsa sistem yeni ad verir. */
    private fun saveWithMediaStore(source: File, fileName: String, mimeType: String): String {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/$DOWNLOAD_SUBDIR",
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Download klasöründe dosya oluşturulamadı")
        try {
            copyTo(source, uri)
            contentResolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        return displayName(uri) ?: fileName
    }

    // --- Yedek dosyası seçme ---------------------------------------------------------------

    /**
     * Sistemin dosya seçicisini açar ve seçilen dosyayı uygulamanın cache
     * klasörüne kopyalayıp yolunu döndürür; kullanıcı vazgeçerse `null`.
     *
     * Tür süzgeci bilerek her dosyaya açık: yedek dosyaları WhatsApp/e-posta
     * üzerinden gelince çoğu zaman `text/csv` yerine
     * `application/octet-stream` görünüyor ve dar bir süzgeç dosyayı
     * seçilemez yapıyor. İçerik Dart tarafında doğrulanır.
     */
    private fun pickFile(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "Başka bir dosya seçimi sürüyor", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_OPEN_DOCUMENT)
    }

    @Deprecated("startActivityForResult ile eşleşen eski API; FlutterActivity bir ComponentActivity değil.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_CREATE_DOCUMENT -> onSaveResult(resultCode, data?.data)
            REQUEST_OPEN_DOCUMENT -> onPickResult(resultCode, data?.data)
        }
    }

    private fun onSaveResult(resultCode: Int, uri: Uri?) {
        val pending = pendingSave ?: return
        pendingSave = null
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.result.success(null) // kullanıcı vazgeçti
            return
        }
        io.execute {
            try {
                copyTo(pending.source, uri)
                val name = displayName(uri) ?: uri.lastPathSegment ?: ""
                main.post { pending.result.success(name) }
            } catch (e: Exception) {
                main.post { pending.result.error("save_failed", e.message, null) }
            }
        }
    }

    private fun onPickResult(resultCode: Int, uri: Uri?) {
        val pending = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null) // kullanıcı vazgeçti
            return
        }
        io.execute {
            try {
                // Sabit ad: seçilen dosyanın adı yol ayracı içerebilir, işimize
                // de yaramıyor; yalnızca içeriği okuyacağız.
                val dir = File(cacheDir, IMPORT_DIR)
                dir.deleteRecursively()
                dir.mkdirs()
                val target = File(dir, "yedek.csv")
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { input.copyTo(it) }
                } ?: throw IllegalStateException("Seçilen dosya açılamadı")
                main.post { pending.success(target.absolutePath) }
            } catch (e: Exception) {
                main.post { pending.error("pick_failed", e.message, null) }
            }
        }
    }

    private fun copyTo(source: File, uri: Uri) {
        val out = contentResolver.openOutputStream(uri, "w")
            ?: throw IllegalStateException("Hedef dosya açılamadı")
        out.use { stream -> source.inputStream().use { it.copyTo(stream) } }
    }

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    private companion object {
        const val CHANNEL = "com.dedem.fatkatalog/native"
        const val DOWNLOAD_SUBDIR = "FATKatalog"
        const val IMPORT_DIR = "import"
        const val REQUEST_CREATE_DOCUMENT = 4711
        const val REQUEST_OPEN_DOCUMENT = 4712
    }
}
