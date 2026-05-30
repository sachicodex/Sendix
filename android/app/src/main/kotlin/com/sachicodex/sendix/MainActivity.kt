package com.sachicodex.sendix

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  private val channelName = "sendix/installed_apps"
  private val shareChannelName = "sendix/share_events"
  private var shareSink: EventChannel.EventSink? = null
  private val pendingShares = ArrayList<String>()

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "list" -> {
            Thread {
              try {
                val pm = applicationContext.packageManager
                val installed = pm.getInstalledApplications(0)
                val out = ArrayList<HashMap<String, Any?>>(installed.size)

                for (appInfo in installed) {
                  if (pm.getLaunchIntentForPackage(appInfo.packageName) == null) continue
                  val label = pm.getApplicationLabel(appInfo).toString()
                  val iconDrawable = try {
                    appInfo.loadIcon(pm)
                  } catch (_: Exception) {
                    null
                  }
                  val iconBytes = iconDrawable?.let { drawableToPng(it) }

                  val item = hashMapOf<String, Any?>(
                    "appName" to label,
                    "packageName" to appInfo.packageName,
                    "apkPath" to appInfo.sourceDir,
                    "icon" to iconBytes
                  )
                  out.add(item)
                }

                out.sortBy { (it["appName"] as? String)?.lowercase() ?: "" }

                Handler(Looper.getMainLooper()).post {
                  result.success(out)
                }
              } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                  result.error("LIST_FAILED", e.message, null)
                }
              }
            }.start()
          }

          else -> result.notImplemented()
        }
      }

    EventChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
      .setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          shareSink = events
          if (pendingShares.isNotEmpty()) {
            events?.success(pendingShares.toList())
            pendingShares.clear()
          }
        }

        override fun onCancel(arguments: Any?) {
          shareSink = null
        }
      })

    handleShareIntent(intent)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleShareIntent(intent)
  }

  private fun drawableToPng(drawable: Drawable): ByteArray {
    val bitmap = when (drawable) {
      is BitmapDrawable -> drawable.bitmap
      else -> {
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
        val b = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        drawable.setBounds(0, 0, c.width, c.height)
        drawable.draw(c)
        b
      }
    }

    val stream = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
    return stream.toByteArray()
  }

  private fun handleShareIntent(intent: Intent?) {
    if (intent == null) return
    val action = intent.action ?: return
    if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

    val paths = ArrayList<String>()
    if (action == Intent.ACTION_SEND) {
      val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
      if (uri != null) {
        copyUriToCache(uri)?.let { paths.add(it) }
      } else {
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!text.isNullOrBlank()) {
          writeSharedText(text)?.let { paths.add(it) }
        }
      }
    } else {
      val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
      if (uris != null) {
        for (uri in uris) {
          copyUriToCache(uri)?.let { paths.add(it) }
        }
      }
    }

    if (paths.isNotEmpty()) {
      deliverSharedPaths(paths)
    }
  }

  private fun deliverSharedPaths(paths: List<String>) {
    val sink = shareSink
    if (sink != null) {
      sink.success(paths)
    } else {
      pendingShares.addAll(paths)
    }
  }

  private fun copyUriToCache(uri: Uri): String? {
    return try {
      val name = queryDisplayName(uri) ?: uri.lastPathSegment ?: "share"
      val safeName = name.replace(Regex("[\\\\/:*?\"<>|]+"), "_")
      val outFile = File(cacheDir, "sendix_share_${System.currentTimeMillis()}_$safeName")
      contentResolver.openInputStream(uri)?.use { input ->
        FileOutputStream(outFile).use { output ->
          input.copyTo(output)
        }
      } ?: return null
      outFile.absolutePath
    } catch (_: Exception) {
      null
    }
  }

  private fun writeSharedText(text: String): String? {
    return try {
      val outFile = File(cacheDir, "sendix_text_${System.currentTimeMillis()}.txt")
      outFile.writeText(text)
      outFile.absolutePath
    } catch (_: Exception) {
      null
    }
  }

  private fun queryDisplayName(uri: Uri): String? {
    return try {
      contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { cursor ->
          if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    } catch (_: Exception) {
      null
    }
  }
}

