package app.fathom.fathom

import android.content.Context
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.CastDevice
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.common.images.WebImage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/// Native Google Cast bridge. Discovers Chromecast devices with MediaRouter
/// (streamed to Flutter so the device picker renders in-app, avoiding the
/// AppCompat-only route dialog), selects a route to start a session, and loads
/// the Jellyfin stream URL onto the Default Media Receiver.
///
/// Untested end-to-end without a Cast device; the discovery/session/load flow
/// follows the standard Cast SDK pattern and is wired here to iterate against a
/// real Chromecast.
class CastBridge(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext
    private var castContext: CastContext? = null
    private val mediaRouter = MediaRouter.getInstance(appContext)
    private val selector = MediaRouteSelector.Builder()
        .addControlCategory(
            CastMediaControlIntent.categoryForCast(
                CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
            )
        )
        .build()

    private var events: EventChannel.EventSink? = null
    private var pending: MediaLoadRequestData? = null

    init {
        try {
            castContext = CastContext.getSharedInstance(appContext)
        } catch (_: Throwable) {
            // Google Play Services / Cast unavailable on this device.
            castContext = null
        }

        MethodChannel(messenger, "app.fathom.player/cast").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(castContext != null)
                "startDiscovery" -> { startDiscovery(); result.success(null) }
                "stopDiscovery" -> { stopDiscovery(); result.success(null) }
                "selectRoute" -> {
                    selectRoute(call.argument<String>("id"))
                    result.success(null)
                }
                "loadMedia" -> {
                    loadMedia(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "loadQueue" -> {
                    loadQueue(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "queueNext" -> { remoteClient()?.queueNext(null); result.success(null) }
                "queuePrev" -> { remoteClient()?.queuePrev(null); result.success(null) }
                "play" -> { remoteClient()?.play(); result.success(null) }
                "pause" -> { remoteClient()?.pause(); result.success(null) }
                "stop" -> { remoteClient()?.stop(); result.success(null) }
                "seek" -> {
                    val pos = (call.argument<Number>("position")?.toLong()) ?: 0L
                    remoteClient()?.seek(
                        com.google.android.gms.cast.MediaSeekOptions.Builder()
                            .setPosition(pos).build()
                    )
                    result.success(null)
                }
                "setVolume" -> {
                    val v = (call.argument<Number>("volume")?.toDouble() ?: 1.0)
                        .coerceIn(0.0, 1.0)
                    try {
                        castContext?.sessionManager?.currentCastSession?.volume = v
                    } catch (_: Exception) {}
                    result.success(null)
                }
                "endSession" -> {
                    castContext?.sessionManager?.endCurrentSession(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "app.fathom.player/cast/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                    castContext?.sessionManager?.addSessionManagerListener(
                        sessionListener, CastSession::class.java
                    )
                    if (castContext != null) {
                        // Passive (flag 0): track route availability for the
                        // button's show/hide without an active scan.
                        mediaRouter.addCallback(selector, availabilityCallback, 0)
                    }
                    emitAvailability()
                    emitSession()
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                    castContext?.sessionManager?.removeSessionManagerListener(
                        sessionListener, CastSession::class.java
                    )
                    mediaRouter.removeCallback(availabilityCallback)
                }
            }
        )
    }

    private fun remoteClient() =
        castContext?.sessionManager?.currentCastSession?.remoteMediaClient

    // Streams the cast device's playback state to Flutter so the app's transport
    // controls can reflect and drive the receiver (not local playback).
    private val mediaCallback =
        object : com.google.android.gms.cast.framework.media.RemoteMediaClient.Callback() {
            override fun onStatusUpdated() = emitMedia()
        }
    private val progressListener =
        com.google.android.gms.cast.framework.media.RemoteMediaClient.ProgressListener { pos, dur ->
            val c = remoteClient()
            events?.success(
                mapOf(
                    "type" to "media",
                    "playing" to (c?.isPlaying ?: false),
                    "position" to pos,
                    "duration" to dur,
                    "currentUrl" to c?.mediaInfo?.contentId,
                    "volume" to (castContext?.sessionManager
                        ?.currentCastSession?.volume ?: 1.0)
                )
            )
        }

    private fun emitMedia() {
        val c = remoteClient() ?: return
        events?.success(
            mapOf(
                "type" to "media",
                "playing" to c.isPlaying,
                "position" to c.approximateStreamPosition,
                "duration" to c.streamDuration,
                // The item the receiver is actually playing, so the app can sync
                // its now-playing display as the queue auto-advances on device.
                "currentUrl" to c.mediaInfo?.contentId,
                "volume" to (castContext?.sessionManager
                    ?.currentCastSession?.volume ?: 1.0)
            )
        )
    }

    private fun attachMediaListeners(client: com.google.android.gms.cast.framework.media.RemoteMediaClient) {
        client.registerCallback(mediaCallback)
        client.addProgressListener(progressListener, 1000)
    }

    private fun detachMediaListeners() {
        remoteClient()?.let {
            it.unregisterCallback(mediaCallback)
            it.removeProgressListener(progressListener)
        }
    }

    private val routerCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(r: MediaRouter, route: MediaRouter.RouteInfo) = emitDevices()
        override fun onRouteRemoved(r: MediaRouter, route: MediaRouter.RouteInfo) = emitDevices()
        override fun onRouteChanged(r: MediaRouter, route: MediaRouter.RouteInfo) = emitDevices()
    }

    // Persistent PASSIVE callback used only to know whether any Cast device is
    // reachable, so the cast button can hide when there's none (off Wi-Fi, no
    // Chromecast on the LAN) — exactly how the Cast SDK's own MediaRouteButton
    // decides its visibility. Passive discovery is low-power; the high-power
    // active scan still runs only while the picker is open (startDiscovery).
    private val availabilityCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(r: MediaRouter, route: MediaRouter.RouteInfo) = emitAvailability()
        override fun onRouteRemoved(r: MediaRouter, route: MediaRouter.RouteInfo) = emitAvailability()
        override fun onRouteChanged(r: MediaRouter, route: MediaRouter.RouteInfo) = emitAvailability()
    }

    private fun emitAvailability() {
        val available = try {
            mediaRouter.isRouteAvailable(
                selector, MediaRouter.AVAILABILITY_FLAG_IGNORE_DEFAULT_ROUTE
            )
        } catch (_: Throwable) {
            false
        }
        events?.success(mapOf("type" to "availability", "available" to available))
    }

    private fun startDiscovery() {
        mediaRouter.addCallback(
            selector, routerCallback,
            MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY
        )
        emitDevices()
    }

    private fun stopDiscovery() = mediaRouter.removeCallback(routerCallback)

    private fun emitDevices() {
        // Report every Cast route with a `video` flag. The caller filters: the
        // video player shows only video-capable receivers, while music can cast
        // to audio-only devices (Nest/Home Mini, speaker groups) too.
        val devices = mediaRouter.routes
            .filter { it.matchesSelector(selector) && !it.isDefaultOrBluetooth }
            .map { route ->
                val cd = CastDevice.getFromBundle(route.extras)
                mapOf(
                    "id" to route.id,
                    "name" to route.name,
                    "video" to (cd?.hasCapability(CastDevice.CAPABILITY_VIDEO_OUT) ?: false)
                )
            }
        events?.success(mapOf("type" to "devices", "devices" to devices))
    }

    private val MediaRouter.RouteInfo.isDefaultOrBluetooth: Boolean
        get() = isDefault || isBluetooth

    private fun selectRoute(id: String?) {
        val route = mediaRouter.routes.firstOrNull { it.id == id }
        if (route == null) {
            logEvent("selectRoute: route not found for id=$id")
            return
        }
        logEvent("selectRoute: selecting ${route.name} (connecting=${route.connectionState})")
        mediaRouter.selectRoute(route)
    }

    private fun loadMedia(args: Map<*, *>?) {
        if (args == null) return
        val url = args["url"] as? String ?: return
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE)
        (args["title"] as? String)?.let { metadata.putString(MediaMetadata.KEY_TITLE, it) }
        (args["subtitle"] as? String)?.let {
            metadata.putString(MediaMetadata.KEY_SUBTITLE, it)
        }
        (args["image"] as? String)?.let {
            metadata.addImage(WebImage(android.net.Uri.parse(it)))
        }
        val info = MediaInfo.Builder(url)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(args["contentType"] as? String ?: "application/x-mpegurl")
            .setMetadata(metadata)
            .build()
        val request = MediaLoadRequestData.Builder()
            .setMediaInfo(info)
            .setAutoplay(true)
            .setCurrentTime((args["position"] as? Number)?.toLong() ?: 0L)
            .build()
        val client = remoteClient()
        if (client != null) {
            doLoad(client, request)
        } else {
            // No session yet; load once the selected route connects.
            pending = request
        }
    }

    private fun doLoad(client: com.google.android.gms.cast.framework.media.RemoteMediaClient, request: MediaLoadRequestData) {
        client.load(request).setResultCallback { result ->
            if (!result.status.isSuccess) {
                events?.success(
                    mapOf(
                        "type" to "error",
                        "message" to "load failed code=${result.status.statusCode} ${result.status.statusMessage}"
                    )
                )
            } else {
                events?.success(mapOf("type" to "error", "message" to "load ok"))
            }
        }
    }

    // The whole queue is handed to the receiver so it plays through and skip
    // advances on the device (queueNext/queuePrev), the way major cast apps do.
    private var pendingQueue: Triple<Array<MediaQueueItem>, Int, Long>? = null

    private fun loadQueue(args: Map<*, *>?) {
        if (args == null) return
        val itemMaps = (args["items"] as? List<*>) ?: return
        val startIndex = (args["startIndex"] as? Number)?.toInt() ?: 0
        val position = (args["position"] as? Number)?.toLong() ?: 0L
        val items = itemMaps.mapNotNull { it as? Map<*, *> }.mapNotNull { m ->
            val url = m["url"] as? String ?: return@mapNotNull null
            val md = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK)
            (m["title"] as? String)?.let { md.putString(MediaMetadata.KEY_TITLE, it) }
            (m["subtitle"] as? String)?.let {
                md.putString(MediaMetadata.KEY_ARTIST, it)
            }
            (m["image"] as? String)?.let {
                md.addImage(WebImage(android.net.Uri.parse(it)))
            }
            val info = MediaInfo.Builder(url)
                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                .setContentType(m["contentType"] as? String ?: "audio/mpeg")
                .setMetadata(md)
                .build()
            MediaQueueItem.Builder(info).build()
        }.toTypedArray()
        if (items.isEmpty()) return
        val client = remoteClient()
        if (client != null) {
            doLoadQueue(client, items, startIndex, position)
        } else {
            pendingQueue = Triple(items, startIndex, position)
        }
    }

    private fun doLoadQueue(
        client: com.google.android.gms.cast.framework.media.RemoteMediaClient,
        items: Array<MediaQueueItem>,
        startIndex: Int,
        position: Long,
    ) {
        client.queueLoad(
            items, startIndex, MediaStatus.REPEAT_MODE_REPEAT_OFF, position, null
        ).setResultCallback { result ->
            events?.success(
                mapOf(
                    "type" to "error",
                    "message" to if (result.status.isSuccess) "queue ok"
                    else "queue failed code=${result.status.statusCode}"
                )
            )
        }
    }

    private fun emitSession() {
        val session = castContext?.sessionManager?.currentCastSession
        val connected = session?.isConnected == true
        events?.success(
            mapOf(
                "type" to "session",
                "connected" to connected,
                "device" to session?.castDevice?.friendlyName
            )
        )
    }

    private fun logEvent(msg: String) {
        events?.success(mapOf("type" to "error", "message" to msg))
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            logEvent("session started: ${session.castDevice?.friendlyName}")
            session.remoteMediaClient?.let { attachMediaListeners(it) }
            pending?.let { req ->
                session.remoteMediaClient?.let { doLoad(it, req) }
                pending = null
            }
            pendingQueue?.let { (items, idx, pos) ->
                session.remoteMediaClient?.let { doLoadQueue(it, items, idx, pos) }
                pendingQueue = null
            }
            emitSession()
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            logEvent("session resumed")
            emitSession()
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            logEvent("session ended code=$error")
            detachMediaListeners()
            emitSession()
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {
            logEvent("session suspended reason=$reason")
            emitSession()
        }
        override fun onSessionStarting(session: CastSession) {
            logEvent("session starting…")
        }
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            logEvent("session START FAILED code=$error")
            emitSession()
        }
        override fun onSessionEnding(session: CastSession) {
            logEvent("session ending")
        }
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            logEvent("session resume failed code=$error")
            emitSession()
        }
    }

    // Unused but kept for parity with a JSON payload path if needed later.
    @Suppress("unused")
    private fun toJson(map: Map<String, Any?>): String = JSONObject(map).toString()
}
