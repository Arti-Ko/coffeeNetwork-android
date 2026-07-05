package com.coffeenetwork.coffeenetwork

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    private val channelName = "coffeenetwork/vpn"
    private val reqVpn = 0x2701
    private var pendingConfig: String? = null
    private var pendingExclude: ArrayList<String> = arrayListOf()
    private var progressSink: EventChannel.EventSink? = null
    private var importChannel: MethodChannel? = null
    private var pendingImportUrl: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        extractCoffeeUrl(intent)?.let { deliverImport(it) }
    }

    private fun extractCoffeeUrl(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        if (uri.scheme != "coffee") return null
        return uri.toString()
    }

    private fun deliverImport(url: String) {
        val ch = importChannel
        if (ch == null) {
            pendingImportUrl = url
        } else {
            runOnUiThread { ch.invokeMethod("importBundle", mapOf("url" to url)) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        App.init(this)
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coffeenetwork/import")
        pendingImportUrl?.let { url ->
            pendingImportUrl = null
            runOnUiThread { importChannel?.invokeMethod("importBundle", mapOf("url" to url)) }
        }
        extractCoffeeUrl(intent)?.let { deliverImport(it) }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "coffeenetwork/update_progress")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { progressSink = events }
                override fun onCancel(arguments: Any?) { progressSink = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val link = call.argument<String>("link") ?: ""
                    val mobileLink = call.argument<String>("mobileLink") ?: ""
                    val bypassRu = call.argument<Boolean>("bypassRu") ?: true
                    val exclude = call.argument<List<String>>("exclude") ?: emptyList()
                    val isMobile = isCellular()
                    val usingMobile = isMobile && mobileLink.isNotBlank()
                    val activeLink = if (usingMobile) mobileLink else link
                    val parsed = SingBoxConfig.parseLink(activeLink)
                    Log.i("CoffeeVpn", "connect: cellular=$isMobile protocol=${parsed?.protocol} mobileLink=$usingMobile server=${parsed?.host}:${parsed?.port}")
                    if (parsed == null) {
                        result.error("parse", "Не удалось распознать ссылку сервера", null); return@setMethodCallHandler
                    }
                    val cfg = SingBoxConfig.build(parsed.outbound, bypassRu, filesDir.resolve("cache.db").path, isMobile, filesDir.resolve("sing-box.log").path)
                    pendingConfig = cfg
                    pendingExclude = ArrayList(exclude)
                    // remember for the Quick Settings tile and network-type reconnect
                    getSharedPreferences("coffee", MODE_PRIVATE).edit()
                        .putString("link", link)
                        .putString("mobile_link", mobileLink)
                        .putBoolean("bypassRu", bypassRu)
                        .putStringSet("exclude", exclude.toSet())
                        .putString("active_protocol", parsed.protocol)
                        .putString("active_host", parsed.host)
                        .putInt("active_port", parsed.port)
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
                "status" -> {
                    val sp = getSharedPreferences("coffee", MODE_PRIVATE)
                    result.success(
                        JSONObject()
                            .put("running", CoffeeVpnService.running)
                            .put("error", CoffeeVpnService.lastError ?: JSONObject.NULL)
                            .put("activeProtocol", sp.getString("active_protocol", null) ?: JSONObject.NULL)
                            .put("activeHost", sp.getString("active_host", null) ?: JSONObject.NULL)
                            .put("activePort", sp.getInt("active_port", 0))
                            .toString()
                    )
                }
                "parse" -> {
                    val p = SingBoxConfig.parseLink(call.argument<String>("link") ?: "")
                    if (p == null) result.success(null)
                    else result.success(JSONObject()
                        .put("name", p.name).put("protocol", p.protocol)
                        .put("host", p.host).put("port", p.port).toString())
                }
                "getLog" -> {
                    val logFile = filesDir.resolve("sing-box.log")
                    result.success(if (logFile.exists()) logFile.readText() else "")
                }
                "clearLog" -> {
                    filesDir.resolve("sing-box.log").delete()
                    result.success(null)
                }
                "traffic" -> result.success(traffic())
                "listApps" -> result.success(listApps())
                "appVersion" -> result.success(
                    try { packageManager.getPackageInfo(packageName, 0).versionName } catch (_: Exception) { null }
                )
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("openUrl", e.message, null)
                    }
                }
                // Download the update APK to cacheDir (progress → update_progress
                // EventChannel) and hand it to the system installer. Requires the
                // user to allow "install unknown apps" once (we route them there).
                "installUpdate" -> {
                    val url = call.argument<String>("url") ?: ""
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (_: Exception) {}
                        result.success("permission")
                    } else {
                        result.success("downloading")
                        Thread { downloadAndInstall(url) }.start()
                    }
                }
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

    /// Stream the APK to cacheDir, reporting percent over the EventChannel, then
    /// launch the system package installer via FileProvider.
    private fun downloadAndInstall(url: String) {
        try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 15000
            conn.readTimeout = 30000
            conn.connect()
            val total = conn.contentLength.toLong()
            val apk = File(cacheDir, "update.apk")
            conn.inputStream.use { input ->
                apk.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    var done = 0L
                    var lastPct = -1
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        output.write(buf, 0, n)
                        done += n
                        if (total > 0) {
                            val pct = (done * 100 / total).toInt()
                            if (pct != lastPct) {
                                lastPct = pct
                                runOnUiThread { progressSink?.success(pct) }
                            }
                        }
                    }
                }
            }
            conn.disconnect()
            runOnUiThread { progressSink?.success(100) }
            installApk(apk)
        } catch (e: Exception) {
            runOnUiThread { progressSink?.error("download", e.message ?: "download failed", null) }
        }
    }

    /**
     * Returns true when the best available physical (non-VPN) network is cellular.
     * WiFi takes priority: if WiFi is up alongside cellular, returns false.
     */
    private fun isCellular(): Boolean {
        val cm = App.connectivity
        var hasCellular = false
        for (net in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(net) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return false
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) hasCellular = true
        }
        return hasCellular
    }

    private fun installApk(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
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
