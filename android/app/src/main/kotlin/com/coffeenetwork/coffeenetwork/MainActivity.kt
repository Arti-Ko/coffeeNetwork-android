package com.coffeenetwork.coffeenetwork

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.VpnService
import android.os.Build
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    private val channelName = "coffeenetwork/vpn"
    private val reqVpn = 0x2701
    private var pendingConfig: String? = null
    private var pendingExclude: ArrayList<String> = arrayListOf()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        App.init(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val link = call.argument<String>("link") ?: ""
                    val bypassRu = call.argument<Boolean>("bypassRu") ?: true
                    val exclude = call.argument<List<String>>("exclude") ?: emptyList()
                    val parsed = SingBoxConfig.parseLink(link)
                    if (parsed == null) {
                        result.error("parse", "Не удалось распознать ссылку сервера", null); return@setMethodCallHandler
                    }
                    val cfg = SingBoxConfig.build(parsed.outbound, bypassRu, filesDir.resolve("cache.db").path)
                    pendingConfig = cfg
                    pendingExclude = ArrayList(exclude)
                    // remember for the Quick Settings tile
                    getSharedPreferences("coffee", MODE_PRIVATE).edit()
                        .putString("link", link)
                        .putBoolean("bypassRu", bypassRu)
                        .putStringSet("exclude", exclude.toSet())
                        .apply()
                    val prepare = VpnService.prepare(this)
                    if (prepare != null) {
                        startActivityForResult(prepare, reqVpn)
                        result.success("consent")
                    } else {
                        startVpn(cfg, pendingExclude)
                        result.success("started")
                    }
                }
                "disconnect" -> {
                    startService(Intent(this, CoffeeVpnService::class.java).setAction(CoffeeVpnService.ACTION_STOP))
                    result.success(true)
                }
                "status" -> result.success(
                    JSONObject()
                        .put("running", CoffeeVpnService.running)
                        .put("error", CoffeeVpnService.lastError ?: JSONObject.NULL).toString()
                )
                "parse" -> {
                    val p = SingBoxConfig.parseLink(call.argument<String>("link") ?: "")
                    if (p == null) result.success(null)
                    else result.success(JSONObject()
                        .put("name", p.name).put("protocol", p.protocol)
                        .put("host", p.host).put("port", p.port).toString())
                }
                "traffic" -> result.success(traffic())
                "listApps" -> result.success(listApps())
                else -> result.notImplemented()
            }
        }
    }

    private fun startVpn(config: String, exclude: ArrayList<String>) {
        val intent = Intent(this, CoffeeVpnService::class.java)
            .setAction(CoffeeVpnService.ACTION_START)
            .putExtra(CoffeeVpnService.EXTRA_CONFIG, config)
            .putStringArrayListExtra(CoffeeVpnService.EXTRA_EXCLUDE, exclude)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqVpn && resultCode == Activity.RESULT_OK) {
            pendingConfig?.let { startVpn(it, pendingExclude) }
        }
    }

    private fun traffic(): String {
        return try {
            val conn = URL("http://127.0.0.1:19099/connections").openConnection() as HttpURLConnection
            conn.connectTimeout = 800
            conn.readTimeout = 1200
            val body = conn.inputStream.bufferedReader().readText()
            conn.disconnect()
            val v = JSONObject(body)
            JSONObject().put("up", v.optLong("uploadTotal")).put("down", v.optLong("downloadTotal")).toString()
        } catch (_: Exception) {
            """{"up":0,"down":0}"""
        }
    }

    private fun listApps(): String {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()
        val arr = JSONArray()
        for (ri in resolved) {
            val pkg = ri.activityInfo.packageName ?: continue
            if (pkg == packageName) continue
            if (!seen.add(pkg)) continue
            arr.put(
                JSONObject()
                    .put("name", ri.loadLabel(pm).toString())
                    .put("package", pkg)
                    .put("icon", runCatching { iconDataUri(ri.loadIcon(pm)) }.getOrNull() ?: JSONObject.NULL)
            )
        }
        return arr.toString()
    }

    private fun iconDataUri(d: Drawable, size: Int = 48): String {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, size, size)
        d.draw(Canvas(bmp))
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return "data:image/png;base64," + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
}
