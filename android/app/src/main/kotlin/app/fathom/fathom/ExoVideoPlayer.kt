package app.fathom.fathom

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.text.CueGroup
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.hls.playlist.DefaultHlsPlaylistParserFactory
import androidx.media3.exoplayer.hls.playlist.HlsMediaPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsMultivariantPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsPlaylistParserFactory
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.ParsingLoadable
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.TsExtractor
import java.io.InputStream
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/// Factory Flutter uses to create one native ExoPlayer view per player screen.
/// Registered in MainActivity under the view-type id [VIEW_TYPE].
class ExoVideoPlayerFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        const val VIEW_TYPE = "app.fathom.player/exo_video"
    }

    @OptIn(UnstableApi::class)
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val tunneling = (params?.get("tunneling") as? Boolean) ?: true
        return ExoVideoPlayer(context, messenger, viewId, tunneling)
    }
}

/// A native Media3 ExoPlayer rendering to a TextureView, controlled from Dart
/// over a per-view MethodChannel and reporting state over an EventChannel.
///
/// Renders through a TextureView, not a SurfaceView: a SurfaceView is its own
/// compositor layer, and on this class of Amlogic TV GPU some broadcast formats
/// (raw MPEG-2/interlaced live TV) can't be allocated as an overlay buffer
/// (`mali_gralloc: Unrecognized format`), which wedges the whole compositor until
/// a reboot. A TextureView composites through Flutter's GL texture, sidestepping
/// that for any codec — at the cost of the tunneling/HDR fast path a SurfaceView
/// would allow. Live TV is also always force-transcoded to h264 (belt-and-braces).
@OptIn(UnstableApi::class)
class ExoVideoPlayer(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    tunnelingEnabled: Boolean,
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val videoView = TextureView(context)
    private val methodChannel =
        MethodChannel(messenger, "app.fathom.player/exo_$viewId")
    private val eventChannel =
        EventChannel(messenger, "app.fathom.player/exo_${viewId}_events")
    private var events: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())

    private val trackSelector = DefaultTrackSelector(context).apply {
        setParameters(
            buildUponParameters()
                .setTunnelingEnabled(tunnelingEnabled)
                .setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
        )
    }

    private val player: ExoPlayer

    // Kept so load() can build merged (video-only + audio-only) sources for
    // YouTube's adaptive streams, which are delivered as two separate URLs.
    private val dataSourceFactory: DefaultDataSource.Factory

    // Builds the video source when a sideloaded subtitle is attached: parses the
    // WebVTT into cues during extraction (the path 1.4+ requires), so the text
    // renderer accepts it. Lazy — dataSourceFactory is set in init.
    private val subtitleSourceFactory: DefaultMediaSourceFactory by lazy {
        DefaultMediaSourceFactory(dataSourceFactory)
            .experimentalParseSubtitlesDuringExtraction(true)
    }

    // Poll position/buffer ~4x/sec so the Flutter scrubber stays live.
    private val ticker = object : Runnable {
        override fun run() {
            pushState()
            handler.postDelayed(this, 250)
        }
    }

    init {
        val renderers = DefaultRenderersFactory(context)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            .setEnableDecoderFallback(true)

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
        val dataSource = DefaultDataSource.Factory(context, httpFactory)
        dataSourceFactory = dataSource

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()

        // Broadcast (live TV) captions ride inside the video as CEA-608 messages,
        // not their own stream. The TS extractor only surfaces them when the
        // stream announces them in a caption service descriptor — but Jellyfin's
        // ffmpeg remux carries the captions and writes no descriptor, so ExoPlayer
        // hides them and no CC track appears. Handing the extractor a fallback
        // CEA-608 CC1 format tells it to look anyway (a real descriptor still
        // wins). This is what makes live captions selectable — the piece the
        // media_kit/mpv path could never do. (Idea from Moonfin's Media3 backend.)
        val extractorsFactory = DefaultExtractorsFactory()
            .setTsExtractorMode(TsExtractor.MODE_SINGLE_PMT)
            .setTsSubtitleFormats(
                listOf(
                    Format.Builder()
                        .setSampleMimeType(MimeTypes.APPLICATION_CEA608)
                        .setAccessibilityChannel(1)
                        .build(),
                ),
            )

        player = ExoPlayer.Builder(context, renderers)
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(dataSource, extractorsFactory),
            )
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .build()

        player.setVideoTextureView(videoView)
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                pushState(); updateScreenOn()
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                pushState(); updateScreenOn()
            }
            override fun onPlayWhenReadyChanged(p: Boolean, reason: Int) {
                pushState(); updateScreenOn()
            }
            override fun onVideoSizeChanged(videoSize: VideoSize) = pushState()
            override fun onTracksChanged(tracks: Tracks) = pushTracks(tracks)
            // We render video straight to a SurfaceView (no PlayerView), so
            // there's no built-in SubtitleView. Forward the active cue text to
            // Flutter, which draws the subtitle overlay itself.
            override fun onCues(cueGroup: CueGroup) {
                val text = cueGroup.cues
                    .mapNotNull { it.text?.toString() }
                    .joinToString("\n")
                events?.success(mapOf("event" to "cues", "text" to text))
            }
            override fun onPlayerError(error: PlaybackException) {
                events?.success(
                    mapOf(
                        "event" to "error",
                        "message" to (error.message ?: "Playback error"),
                    )
                )
            }
        })

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        handler.post(ticker)
    }

    override fun getView(): View = videoView

    override fun dispose() {
        handler.removeCallbacks(ticker)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        player.release()
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        pushState()
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> {
                val url = call.argument<String>("url")
                // Optional separate audio track. YouTube exposes anything above
                // ~720p as adaptive video-only + audio-only URLs; we merge them.
                val audioUrl = call.argument<String>("audioUrl")
                // Optional sideloaded subtitle (YouTube captions: a separate WebVTT
                // URL — YouTube's adaptive streams carry no embedded text track).
                val subtitleUrl = call.argument<String>("subtitleUrl")
                val subtitleLang = call.argument<String>("subtitleLang")
                val subtitleLabel = call.argument<String>("subtitleLabel")
                val subtitleMime = call.argument<String>("subtitleMime") ?: MimeTypes.TEXT_VTT
                val startMs = (call.argument<Number>("startPositionMs"))?.toLong() ?: 0L
                val play = call.argument<Boolean>("play") ?: true
                if (url == null) {
                    result.error("no_url", "load requires a url", null)
                    return
                }
                val isHls = url.contains(".m3u8") || url.contains("streamMode=hls")

                // A sideloaded subtitle (YouTube WebVTT). Attached as a
                // SubtitleConfiguration and built through a DefaultMediaSourceFactory
                // with parse-during-extraction ON, so Media3 turns the VTT into cues
                // (the modern path) instead of the legacy text-sample decode, which
                // 1.4+ disables by default ("can't handle text/vtt samples"). Flagged
                // DEFAULT so it shows without a separate track-select; "off" is a
                // reload with no subtitle. Not for HLS (its captions are in-manifest).
                val subtitleConfig: MediaItem.SubtitleConfiguration? =
                    if (!subtitleUrl.isNullOrEmpty() && !isHls) {
                        MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitleUrl))
                            .setMimeType(subtitleMime)
                            .setLanguage(subtitleLang)
                            .setLabel(subtitleLabel)
                            .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                            .build()
                    } else {
                        null
                    }
                // A prior "off" may have disabled the text renderer; re-enable it so a
                // freshly merged subtitle can be selected.
                if (subtitleConfig != null) {
                    trackSelector.setParameters(
                        trackSelector.parameters.buildUpon()
                            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                            .build()
                    )
                }

                if (!audioUrl.isNullOrEmpty() && !isHls) {
                    // Video (+ optional parsed subtitle) as one source, then merge the
                    // separate audio-only track.
                    val videoItem = MediaItem.Builder().setUri(url).apply {
                        if (subtitleConfig != null) {
                            setSubtitleConfigurations(listOf(subtitleConfig))
                        }
                    }.build()
                    val videoSource = subtitleSourceFactory.createMediaSource(videoItem)
                    val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(audioUrl))
                    player.setMediaSource(
                        MergingMediaSource(videoSource, audioSource), startMs)
                } else if (subtitleConfig != null) {
                    val item = MediaItem.Builder().setUri(url)
                        .setSubtitleConfigurations(listOf(subtitleConfig))
                        .build()
                    player.setMediaSource(
                        subtitleSourceFactory.createMediaSource(item), startMs)
                } else if (isHls) {
                    // Live TV arrives as HLS whose multivariant playlist omits any
                    // CLOSED-CAPTIONS declaration, so Media3 won't expose the CEA-608
                    // captions embedded in the h264 TS segments. Inject a CC1
                    // declaration into the playlist (see the parser factory) so the
                    // caption track appears and decodes — then our overlay draws it.
                    val hlsSource = HlsMediaSource.Factory(dataSourceFactory)
                        .setPlaylistParserFactory(
                            CaptionInjectingHlsPlaylistParserFactory(),
                        )
                        .setAllowChunklessPreparation(true)
                        .createMediaSource(MediaItem.fromUri(url))
                    player.setMediaSource(hlsSource, startMs)
                } else {
                    player.setMediaItem(MediaItem.fromUri(url), startMs)
                }
                player.prepare()
                player.playWhenReady = play
                result.success(null)
            }
            "play" -> { player.play(); result.success(null) }
            "pause" -> { player.pause(); result.success(null) }
            "seekTo" -> {
                val ms = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                player.seekTo(ms)
                result.success(null)
            }
            "setVolume" -> {
                val v = (call.argument<Number>("volume"))?.toFloat() ?: 1f
                player.volume = v.coerceIn(0f, 1f)
                result.success(null)
            }
            "setSpeed" -> {
                val s = (call.argument<Number>("speed"))?.toFloat() ?: 1f
                player.setPlaybackSpeed(s.coerceIn(0.25f, 4f))
                result.success(null)
            }
            "setAudioTrack" -> {
                selectTrack(C.TRACK_TYPE_AUDIO, call.argument<Int>("index") ?: -1)
                result.success(null)
            }
            "setSubtitleTrack" -> {
                selectTrack(C.TRACK_TYPE_TEXT, call.argument<Int>("index") ?: -1)
                result.success(null)
            }
            "position" -> result.success(player.currentPosition)
            "dispose" -> { dispose(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    // Selects the nth track group of [type] (as listed in the "tracks" event),
    // or disables that track type when index < 0.
    private fun selectTrack(type: Int, index: Int) {
        val builder = trackSelector.parameters.buildUpon()
        builder.setTrackTypeDisabled(type, index < 0)
        if (index >= 0) {
            val groups = typedGroups(type)
            groups.getOrNull(index)?.let { group ->
                builder.setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
            }
        } else {
            builder.clearOverridesOfType(type)
        }
        trackSelector.setParameters(builder.build())
    }

    private fun typedGroups(type: Int): List<Tracks.Group> =
        player.currentTracks.groups.filter { it.type == type }

    private fun pushTracks(tracks: Tracks) {
        fun list(type: Int) = tracks.groups.filter { it.type == type }.mapIndexed { i, g ->
            val fmt = g.mediaTrackGroup.getFormat(0)
            mapOf(
                "index" to i,
                "label" to (fmt.label ?: fmt.language ?: "Track ${i + 1}"),
                "language" to (fmt.language ?: ""),
                "selected" to g.isSelected,
            )
        }
        events?.success(
            mapOf(
                "event" to "tracks",
                "audio" to list(C.TRACK_TYPE_AUDIO),
                "text" to list(C.TRACK_TYPE_TEXT),
            )
        )
    }

    // Hold the screen awake while the player is actively playing (or buffering
    // toward play). Rendering to a bare SurfaceView means there's no PlayerView
    // to manage this for us, so without it the TV screensaver kicks in mid-video
    // (no remote input registers as "idle"). keepScreenOn maps to the window's
    // FLAG_KEEP_SCREEN_ON and is released automatically when the view detaches.
    private fun updateScreenOn() {
        val keep = player.playWhenReady &&
            player.playbackState != Player.STATE_ENDED &&
            player.playbackState != Player.STATE_IDLE
        videoView.keepScreenOn = keep
    }

    private fun pushState() {
        val sink = events ?: return
        // Format/counter details for the Playback Info panel (parity with the
        // media_kit player's stats). Any that ExoPlayer hasn't resolved yet come
        // through as null / -1 and the Flutter side shows a dash.
        val vf = player.videoFormat
        val af = player.audioFormat
        val vc = player.videoDecoderCounters
        sink.success(
            mapOf(
                "event" to "state",
                "position" to player.currentPosition,
                "duration" to (if (player.duration == C.TIME_UNSET) 0L else player.duration),
                "buffered" to player.bufferedPosition,
                "playing" to player.isPlaying,
                "buffering" to (player.playbackState == Player.STATE_BUFFERING),
                "ended" to (player.playbackState == Player.STATE_ENDED),
                "width" to player.videoSize.width,
                "height" to player.videoSize.height,
                "videoCodec" to (vf?.sampleMimeType ?: vf?.codecs),
                "frameRate" to (vf?.frameRate ?: -1f),
                "videoBitrate" to (vf?.bitrate ?: -1),
                "audioCodec" to (af?.sampleMimeType ?: af?.codecs),
                "audioChannels" to (af?.channelCount ?: -1),
                "audioSampleRate" to (af?.sampleRate ?: -1),
                "audioBitrate" to (af?.bitrate ?: -1),
                "droppedFrames" to (vc?.droppedBufferCount ?: 0),
            )
        )
    }
}

/// Wraps Media3's HLS playlist parser to inject a CEA-608 CC1 closed-caption
/// declaration into a multivariant playlist that has none. Jellyfin's live TV
/// HLS carries the broadcast captions inside the h264 TS segments but writes no
/// CLOSED-CAPTIONS tag, so Media3 hides them. Adding the declaration makes the
/// CC1 track selectable, and Media3 then decodes it from the segments. A playlist
/// that already declares captions is passed through untouched.
@androidx.media3.common.util.UnstableApi
private class CaptionInjectingHlsPlaylistParserFactory(
    private val delegate: HlsPlaylistParserFactory = DefaultHlsPlaylistParserFactory(),
) : HlsPlaylistParserFactory {
    override fun createPlaylistParser(): ParsingLoadable.Parser<HlsPlaylist> =
        InjectingParser(delegate.createPlaylistParser())

    override fun createPlaylistParser(
        multivariantPlaylist: HlsMultivariantPlaylist,
        previousMediaPlaylist: HlsMediaPlaylist?,
    ): ParsingLoadable.Parser<HlsPlaylist> =
        InjectingParser(
            delegate.createPlaylistParser(multivariantPlaylist, previousMediaPlaylist),
        )

    private class InjectingParser(
        private val delegate: ParsingLoadable.Parser<HlsPlaylist>,
    ) : ParsingLoadable.Parser<HlsPlaylist> {
        override fun parse(uri: android.net.Uri, inputStream: InputStream): HlsPlaylist {
            val text = inputStream.bufferedReader(Charsets.UTF_8).readText()
            val patched =
                if (text.contains("#EXT-X-STREAM-INF") &&
                    !text.contains("CLOSED-CAPTIONS")
                ) {
                    inject(text)
                } else {
                    text
                }
            return delegate.parse(uri, patched.byteInputStream(Charsets.UTF_8))
        }

        private fun inject(text: String): String {
            val ccTag =
                "#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID=\"cc\"," +
                    "NAME=\"CC1\",INSTREAM-ID=\"CC1\",AUTOSELECT=YES,DEFAULT=NO"
            val lines = text.replace("\r\n", "\n").split("\n").toMutableList()
            for (i in lines.indices) {
                if (lines[i].startsWith("#EXT-X-STREAM-INF") &&
                    !lines[i].contains("CLOSED-CAPTIONS")
                ) {
                    lines[i] = lines[i].trimEnd() + ",CLOSED-CAPTIONS=\"cc\""
                }
            }
            val header = lines.indexOfFirst { it.startsWith("#EXTM3U") }
            lines.add(if (header >= 0) header + 1 else 0, ccTag)
            return lines.joinToString("\n")
        }
    }
}
