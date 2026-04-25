package com.hijricalendar.hijri_calendar

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "hijri_calendar/notifications"
    private var previewPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setNotificationVolume" -> {
                        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                        try {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val max = am.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION)
                            val target = (max * volume).toInt().coerceIn(0, max)
                            am.setStreamVolume(
                                AudioManager.STREAM_NOTIFICATION,
                                target,
                                0
                            )
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.success(false)
                        } catch (e: Exception) {
                            result.error("VOLUME_ERROR", e.message, null)
                        }
                    }

                    "previewSound" -> {
                        val sound = call.argument<String>("sound") ?: "brightline"
                        val customPath = call.argument<String>("customPath")
                        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                        try {
                            stopPreview()
                            val uri: Uri = when (sound) {
                                "custom" -> {
                                    if (customPath.isNullOrEmpty()) {
                                        rawUri("brightline")
                                    } else {
                                        Uri.parse(
                                            if (customPath.startsWith("/")) "file://$customPath"
                                            else customPath
                                        )
                                    }
                                }
                                else -> rawUri(sound)
                            }
                            previewPlayer = MediaPlayer().apply {
                                setAudioAttributes(
                                    AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                        .build()
                                )
                                setDataSource(applicationContext, uri)
                                setVolume(volume, volume)
                                setOnCompletionListener { stopPreview() }
                                prepare()
                                start()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PREVIEW_ERROR", e.message, null)
                        }
                    }

                    "stopPreview" -> {
                        stopPreview()
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun rawUri(name: String): Uri {
        val resId = resources.getIdentifier(name, "raw", packageName)
        return if (resId != 0) {
            Uri.parse("android.resource://$packageName/$resId")
        } else {
            Uri.parse("android.resource://$packageName/raw/brightline")
        }
    }

    private fun stopPreview() {
        try {
            previewPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {
        }
        previewPlayer = null
    }

    override fun onDestroy() {
        stopPreview()
        super.onDestroy()
    }
}
