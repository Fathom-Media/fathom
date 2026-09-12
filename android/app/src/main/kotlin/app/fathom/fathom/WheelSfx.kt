package app.fathom.fathom

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Short, rapid-fire sound effects (the wheel's peg ticks), which the app's
// media_kit player cannot serve well on Android: it holds one stream, so every
// tick is a seek-to-zero plus play against an output buffer sized for media
// playback. At one tick per 50ms the restarts smear into each other and lag
// behind the wheel, while the same code on the desktop gives a crisp rattle.
//
// SoundPool is Android's answer for this: the clip is decoded once into memory,
// each play is a new mixed stream (so overlapping ticks layer instead of
// cutting each other off), and latency is a few milliseconds.
class WheelSfx(context: Context, messenger: BinaryMessenger, loader: FlutterLoader) {
    private val pool: SoundPool = SoundPool.Builder()
        // Several may overlap while the wheel is at full speed.
        .setMaxStreams(6)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()

    // Asset path -> loaded sound id, and whether the pool has finished decoding
    // it (playing before that silently does nothing).
    private val sounds = HashMap<String, Int>()
    private val ready = HashSet<Int>()
    private val channel = MethodChannel(messenger, "app.fathom.player/sfx")

    init {
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) ready.add(sampleId)
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> {
                    val asset = call.argument<String>("asset")
                    if (asset == null) {
                        result.error("args", "asset required", null)
                    } else {
                        try {
                            val key = loader.getLookupKeyForAsset(asset)
                            val fd = context.assets.openFd(key)
                            val id = pool.load(fd, 1)
                            fd.close()
                            sounds[asset] = id
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("load", e.message, null)
                        }
                    }
                }
                "play" -> {
                    val asset = call.argument<String>("asset")
                    val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    val id = sounds[asset]
                    if (id == null || !ready.contains(id)) {
                        result.success(false)
                    } else {
                        pool.play(id, volume, volume, 1, 0, 1f)
                        result.success(true)
                    }
                }
                "dispose" -> {
                    pool.release()
                    sounds.clear()
                    ready.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
