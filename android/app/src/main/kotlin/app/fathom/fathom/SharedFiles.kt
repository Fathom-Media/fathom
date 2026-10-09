package app.fathom.fathom

import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Puts finished downloads where the rest of the phone can see them, and opens
// or shares a file with other apps.
//
// Fathom downloads into its own folder (Android/data/...), which Android 11+
// hides from every other app, so a finished video never appeared in the Files
// app or the gallery. publish copies it into MediaStore under a public folder
// (Movies/Fathom and Music/Fathom by default) and returns the new path, which
// Fathom can still read directly because it owns the file.
//
// Android 10 and older keep the old behavior (canPublish is false): reading a
// shared file back by its path there needs storage permissions Fathom doesn't
// hold, so publishing would lose track of the download.
//
// Registered with every new activity (see MainActivity), so the handler always
// has a live activity to launch from.
class SharedFiles(private val activity: Activity, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canPublish" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                "publish", "move" -> {
                    val path = call.argument<String>("path")!!
                    val dir = call.argument<String>("relativeDir")!!
                    val mime = call.argument<String>("mime")!!
                    val method = call.method
                    // Can copy a large video: off the main thread, answered on it.
                    Thread {
                        try {
                            val done = if (method == "move") move(path, dir, mime)
                            else publish(path, dir, mime)
                            main.post { result.success(done) }
                        } catch (e: Exception) {
                            main.post { result.error(method, e.toString(), null) }
                        }
                    }.start()
                }
                "open", "share" -> {
                    try {
                        val path = call.argument<String>("path")!!
                        val mime = call.argument<String>("mime")!!
                        if (call.method == "open") open(path, mime) else share(path, mime)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error(call.method, e.toString(), null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun publish(path: String, relativeDir: String, mime: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            throw IllegalStateException("Publishing needs Android 11 or newer")
        }
        val src = File(path)
        val top = relativeDir.substringBefore('/')
        val volume = MediaStore.VOLUME_EXTERNAL_PRIMARY
        // Each collection only accepts its own top-level folders; MediaStore
        // refuses the insert otherwise, which the caller answers by falling
        // back to the default folder.
        val collection = when {
            top.equals("Download", ignoreCase = true) ->
                MediaStore.Downloads.getContentUri(volume)
            mime.startsWith("audio/") -> MediaStore.Audio.Media.getContentUri(volume)
            else -> MediaStore.Video.Media.getContentUri(volume)
        }
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, src.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativeDir.trim('/') + "/")
            // Hidden from other apps until the copy is complete.
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore refused $relativeDir")
        try {
            resolver.openOutputStream(uri)!!.use { out ->
                src.inputStream().use { it.copyTo(out, 1 shl 20) }
            }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        // The real path, which may differ from the name asked for: MediaStore
        // adds " (1)" when the folder already has a file by that name.
        @Suppress("DEPRECATION")
        val published = resolver.query(
            uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null,
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        if (published == null || !File(published).exists()) {
            resolver.delete(uri, null, null)
            throw IllegalStateException("Published file can't be found")
        }
        src.delete()
        return published
    }

    // Moves a file Fathom already published to another shared folder. Tries a
    // rename first (MediaStore just updates its folder, instant for any size),
    // and falls back to publishing a copy there and deleting this one, for
    // moves MediaStore won't do in place (into another collection's folder)
    // or a file that isn't in MediaStore at all yet.
    private fun move(path: String, relativeDir: String, mime: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            throw IllegalStateException("Moving needs Android 11 or newer")
        }
        val resolver = activity.contentResolver
        val files = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        @Suppress("DEPRECATION")
        val id = resolver.query(
            files,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DATA} = ?",
            arrayOf(path),
            null,
        )?.use { c -> if (c.moveToFirst()) c.getLong(0) else null }
        if (id != null) {
            val uri = ContentUris.withAppendedId(files, id)
            try {
                val changed = resolver.update(
                    uri,
                    ContentValues().apply {
                        put(MediaStore.MediaColumns.RELATIVE_PATH, relativeDir.trim('/') + "/")
                    },
                    null,
                    null,
                )
                @Suppress("DEPRECATION")
                val moved = if (changed > 0) resolver.query(
                    uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null,
                )?.use { c -> if (c.moveToFirst()) c.getString(0) else null } else null
                if (moved != null && moved != path && File(moved).exists()) return moved
            } catch (_: Exception) {
                // Not allowed in place; copy instead, below.
            }
        }
        return publish(path, relativeDir, mime)
    }

    private fun contentUri(path: String) =
        FileProvider.getUriForFile(activity, "${activity.packageName}.files", File(path))

    private fun open(path: String, mime: String) {
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(contentUri(path), mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(view, null))
    }

    private fun share(path: String, mime: String) {
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime)
            .putExtra(Intent.EXTRA_STREAM, contentUri(path))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(send, null))
    }

    companion object {
        const val CHANNEL = "app.fathom.player/files"
    }
}
