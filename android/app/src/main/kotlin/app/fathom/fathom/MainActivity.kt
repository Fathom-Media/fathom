package app.fathom.fathom

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaCodecList
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends AudioServiceActivity (not FlutterActivity) so media-button intents and
// the audio_service media session route to the Flutter engine correctly.
//
// Also wires system Picture-in-Picture: while a video is playing (the Flutter
// side flags it via [pipActive]), pressing Home floats the video into a PiP
// window, and PiP-mode changes are reported back so the player can hide its
// controls.
class MainActivity : AudioServiceActivity() {
    private var pipActive = false
    private var channel: MethodChannel? = null

    private var castBridge: CastBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native Media3 ExoPlayer video surface (the tunneled Android TV backend,
        // selectable alongside media_kit).
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ExoVideoPlayerFactory.VIEW_TYPE,
            ExoVideoPlayerFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
        // Native Google Cast bridge (Chromecast).
        castBridge = CastBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.fathom.player/pip",
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setActive" -> {
                    pipActive = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "enter" -> {
                    enterPip()
                    result.success(null)
                }
                "isTelevision" -> {
                    // UiModeManager.currentModeType is the "official" TV signal but
                    // it is unreliable on cold boot for some (cheap Amlogic) TV boxes
                    // — it can report NORMAL before the system settles, which made the
                    // app start up in phone/desktop mode (wrong sidebar, no D-pad
                    // handlers). FEATURE_LEANBACK is a STATIC device feature (Google's
                    // recommended Android-TV check) that is correct even during boot,
                    // so treat either signal as "this is a TV".
                    val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    val pm = packageManager
                    val isTv =
                        ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                            pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                            pm.hasSystemFeature("android.hardware.type.television")
                    result.success(isTv)
                }
                "hardwareVideoCodecs" -> {
                    result.success(hardwareVideoCodecs())
                }
                else -> result.notImplemented()
            }
        }
    }

    // The Jellyfin (ffmpeg) codec names for which this device has a HARDWARE
    // video decoder. The Dart side uses this to advertise only these codecs as
    // direct-play, so anything without hardware support (notably AV1 on cheaper
    // TV sticks) transcodes to h264 server-side instead of grinding through a
    // software decoder and stuttering.
    private fun hardwareVideoCodecs(): List<String> {
        // MediaCodec MIME -> ffmpeg/Jellyfin codec name.
        val mimeToCodec = mapOf(
            "video/avc" to "h264",
            "video/hevc" to "hevc",
            "video/x-vnd.on2.vp8" to "vp8",
            "video/x-vnd.on2.vp9" to "vp9",
            "video/av01" to "av1",
            "video/mpeg2" to "mpeg2video",
            "video/mp4v-es" to "mpeg4",
        )
        val supported = mutableSetOf<String>()
        try {
            val codecs = MediaCodecList(MediaCodecList.ALL_CODECS)
            for (info in codecs.codecInfos) {
                if (info.isEncoder) continue
                // API 29+ reports this directly; below that, treat known
                // software decoders (Google/"sw"/OMX.google) as non-hardware.
                val isHardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    info.isHardwareAccelerated
                } else {
                    val n = info.name.lowercase()
                    !n.contains("google") && !n.contains(".sw.") && !n.startsWith("omx.google")
                }
                if (!isHardware) continue
                for (type in info.supportedTypes) {
                    mimeToCodec[type.lowercase()]?.let { supported.add(it) }
                }
            }
        } catch (_: Exception) {
        }
        return supported.toList()
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            @Suppress("DEPRECATION")
            enterPictureInPictureMode(params)
        }
    }

    // Fired when the user leaves the app (e.g. Home). Enter PiP if a video is
    // active, so playback floats instead of pausing/backgrounding.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipActive) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }
}
