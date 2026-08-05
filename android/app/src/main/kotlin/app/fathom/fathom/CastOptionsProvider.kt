package app.fathom.fathom

import android.content.Context
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions

/// Configures the Google Cast SDK. Uses the Default Media Receiver, which plays
/// a plain media URL, so casting hands the Chromecast the Jellyfin HLS/mp4
/// stream URL and lets the device fetch it directly. Referenced from the
/// manifest via OPTIONS_PROVIDER_CLASS_NAME.
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions {
        val mediaOptions = CastMediaOptions.Builder()
            .setMediaSessionEnabled(true)
            .build()
        return CastOptions.Builder()
            .setReceiverApplicationId(
                CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
            )
            .setCastMediaOptions(mediaOptions)
            .setStopReceiverApplicationWhenEndingSession(true)
            .build()
    }

    override fun getAdditionalSessionProviders(
        context: Context
    ): List<SessionProvider>? = null
}
