package com.videosaver.video_downloader

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Menerima dokumen dari aplikasi lain ("Buka dengan" / "Bagikan ke").
 * File dari content:// URI disalin ke penyimpanan aplikasi karena izin baca
 * URI hanya berlaku sementara, lalu path-nya dikirim ke Flutter.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initialUri: Uri? = null
    private var initialMime: String? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Saat activity dibuat ulang (mis. ganti tema), intent lama jangan diproses lagi
        if (savedInstanceState == null) {
            initialUri = documentUri(intent)
            initialMime = intent?.type
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        val uri = initialUri
                        val mime = initialMime
                        initialUri = null
                        if (uri == null) {
                            result.success(null)
                        } else {
                            copyAsync(uri, mime) { file, error ->
                                if (error != null) result.error("COPY_FAILED", error, null)
                                else result.success(file)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = documentUri(intent) ?: return
        copyAsync(uri, intent.type) { file, _ ->
            if (file != null) channel?.invokeMethod("onFile", file)
        }
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    private fun documentUri(intent: Intent?): Uri? = when (intent?.action) {
        Intent.ACTION_VIEW -> intent.data
        Intent.ACTION_SEND ->
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        else -> null
    }

    private fun copyAsync(
        uri: Uri,
        mime: String?,
        done: (Map<String, String>?, String?) -> Unit,
    ) {
        io.execute {
            try {
                val file = copyToAppStorage(uri, mime)
                main.post { done(mapOf("path" to file.absolutePath, "name" to file.name), null) }
            } catch (e: Exception) {
                main.post { done(null, e.message ?: e.toString()) }
            }
        }
    }

    private fun copyToAppStorage(uri: Uri, mime: String?): File {
        if (uri.scheme == "file") {
            val path = uri.path ?: throw IllegalArgumentException("Invalid file URI")
            val src = File(path)
            if (src.canRead()) return src
        }

        var name = displayName(uri) ?: uri.lastPathSegment?.substringAfterLast('/') ?: "document"
        name = name.replace(Regex("[\\\\/:*?\"<>|]"), "_").take(120)
        // Tambahkan ekstensi dari MIME jika nama tidak punya ekstensi
        if (!name.contains('.')) {
            val type = mime ?: contentResolver.getType(uri)
            val ext = type?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
            if (ext != null) name = "$name.$ext"
        }

        val dir = File(filesDir, "opened").apply { mkdirs() }
        prune(dir)
        val tmp = File(dir, ".incoming-${System.nanoTime()}")
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Cannot open the file")
        input.use { src -> tmp.outputStream().use { dst -> src.copyTo(dst) } }
        return placeUnique(dir, name, tmp)
    }

    /**
     * File dengan nama sama tapi isi berbeda tidak boleh saling menimpa
     * (Recent akan menunjuk ke isi yang salah): beri nama "laporan (2).docx".
     * Jika isinya identik, salinan lama dipakai ulang.
     */
    private fun placeUnique(dir: File, name: String, tmp: File): File {
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var n = 1
        while (true) {
            val candidate = File(dir, if (n == 1) name else "$base ($n)$ext")
            if (!candidate.exists()) {
                if (!tmp.renameTo(candidate)) {
                    tmp.copyTo(candidate)
                    tmp.delete()
                }
                return candidate
            }
            if (sameContent(candidate, tmp)) {
                tmp.delete()
                candidate.setLastModified(System.currentTimeMillis())
                return candidate
            }
            n++
        }
    }

    private fun sameContent(a: File, b: File): Boolean {
        if (a.length() != b.length()) return false
        DataInputStream(a.inputStream().buffered()).use { x ->
            DataInputStream(b.inputStream().buffered()).use { y ->
                val bx = ByteArray(64 * 1024)
                val by = ByteArray(64 * 1024)
                var left = a.length()
                while (left > 0) {
                    val n = minOf(left, bx.size.toLong()).toInt()
                    x.readFully(bx, 0, n)
                    y.readFully(by, 0, n)
                    if (!bx.contentEquals(by)) {
                        for (i in 0 until n) if (bx[i] != by[i]) return false
                    }
                    left -= n
                }
            }
        }
        return true
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0) c.getString(i) else null
                } else null
            }
    } catch (_: Exception) {
        null
    }

    /** Simpan maksimal [MAX_FILES] dokumen terakhir agar storage tidak membengkak. */
    private fun prune(dir: File) {
        val files = dir.listFiles()?.filter { !it.name.startsWith(".incoming-") }
            ?.sortedByDescending { it.lastModified() } ?: return
        files.drop(MAX_FILES - 1).forEach { it.delete() }
    }

    companion object {
        private const val CHANNEL = "superapp/open_with"
        private const val MAX_FILES = 50
    }
}
