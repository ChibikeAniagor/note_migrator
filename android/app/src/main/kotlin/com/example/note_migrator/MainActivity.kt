package com.example.note_migrator

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingShare: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNote" -> result.success(openNote(call))
                    "takeShared" -> {
                        val payload = pendingShare
                        pendingShare = null
                        result.success(payload)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShare(intent)
    }

    private fun openNote(call: MethodCall): String {
        val target = call.argument<String>("target") ?: return "failed"
        val title = call.argument<String>("title").orEmpty()
        val text = call.argument<String>("text").orEmpty()
        val packageName = when (target) {
            "miNotes" -> "com.miui.notes"
            "googleKeep" -> "com.google.android.keep"
            else -> return "failed"
        }
        val intents = when (target) {
            "miNotes" -> listOf(sendIntent(title, text, packageName))
            else -> listOf(
                keepIntent(title, text, packageName),
                keepIntent(title, text, null),
                sendIntent(title, keepShareText(title, text), packageName),
            )
        }
        for (intent in intents) {
            if (packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) == null) {
                continue
            }
            try {
                startActivity(intent)
                return "opened"
            } catch (_: ActivityNotFoundException) {
                continue
            } catch (_: Exception) {
                return "failed"
            }
        }
        return if (isInstalled(packageName)) "refused" else "missing"
    }

    private fun isInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun keepIntent(title: String, text: String, packageName: String?): Intent {
        return Intent(ACTION_CREATE_NOTE).apply {
            type = "text/plain"
            putExtra(EXTRA_NAME, title)
            putExtra(EXTRA_NOTE_TEXT, text)
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra(Intent.EXTRA_SUBJECT, title)
            if (packageName != null) setPackage(packageName)
        }
    }

    private fun sendIntent(title: String, text: String, packageName: String): Intent {
        return Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, title)
            putExtra(Intent.EXTRA_TITLE, title)
            putExtra(Intent.EXTRA_TEXT, text)
            setPackage(packageName)
        }
    }

    private fun keepShareText(title: String, text: String): String {
        if (title.isBlank()) return text
        if (text.startsWith(title)) return text
        if (text.isBlank()) return title
        return "$title\n\n$text"
    }

    private fun captureShare(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        if (intent.getBooleanExtra(CONSUMED, false)) return
        intent.putExtra(CONSUMED, true)
        val items = collectItems(intent)
        if (items.isEmpty()) return
        pendingShare = mapOf(
            "sender" to senderPackage(),
            "items" to items,
        )
    }

    private fun collectItems(intent: Intent): List<Map<String, Any?>> {
        val uris = linkedSetOf<Uri>()
        parcelableUri(intent, Intent.EXTRA_STREAM)?.let { uris.add(it) }
        parcelableUris(intent)?.let { uris.addAll(it) }
        val clip = intent.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let { uris.add(it) }
            }
        }
        if (uris.isNotEmpty()) {
            val files = mutableListOf<Map<String, Any?>>()
            for (uri in uris) {
                val bytes = readBytes(uri) ?: continue
                if (bytes.size > MAX_SHARE_BYTES) {
                    pendingShare = mapOf(
                        "error" to "That shared file is over 32 MB. Choose it from the import screen instead.",
                    )
                    return emptyList()
                }
                files.add(
                    mapOf(
                        "name" to displayName(uri),
                        "bytes" to bytes,
                    ),
                )
            }
            return files
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.take(MAX_TEXT)
        if (text.isNullOrBlank()) return emptyList()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            ?: intent.getStringExtra(Intent.EXTRA_TITLE)
        val body = if (!subject.isNullOrBlank() && !text.startsWith(subject)) {
            "$subject\n\n$text"
        } else {
            text
        }
        return listOf(mapOf("name" to "shared-note.txt", "text" to body))
    }

    private fun senderPackage(): String? {
        val host = referrer?.host ?: return null
        return when (host) {
            "com.google.android.keep", "com.miui.notes" -> host
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun parcelableUri(intent: Intent, name: String): Uri? {
        return intent.getParcelableExtra(name)
    }

    @Suppress("DEPRECATION")
    private fun parcelableUris(intent: Intent): ArrayList<Uri>? {
        return intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
    }

    private fun readBytes(uri: Uri): ByteArray? {
        return try {
            contentResolver.openInputStream(uri)?.use { input -> input.readBytes() }
        } catch (_: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String {
        val cursor = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val name = it.getString(index)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
        return uri.lastPathSegment ?: "shared-note.txt"
    }

    companion object {
        private const val CHANNEL = "note_migrator/handoff"
        private const val CONSUMED = "note_migrator_consumed"
        private const val ACTION_CREATE_NOTE = "com.google.android.gms.actions.CREATE_NOTE"
        private const val EXTRA_NAME = "com.google.android.gms.actions.extra.NAME"
        private const val EXTRA_NOTE_TEXT = "com.google.android.gms.actions.extra.TEXT"
        private const val MAX_SHARE_BYTES = 32 * 1024 * 1024
        private const val MAX_TEXT = 1_000_000
    }
}
