package com.coffeenetwork.coffeenetwork

import android.net.Uri
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

/**
 * sing-box config generator — Kotlin port of the desktop `singbox.rs`.
 * Parses a share link into a proxy outbound and assembles a full config
 * (TUN inbound for Android VpnService, sing-box 1.12+ DNS format, RU split,
 * cache_file + clash_api). Validated config shape mirrors the desktop client.
 */
object SingBoxConfig {

    const val PROXY = "proxy"
    private const val RS_GEOSITE_RU =
        "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs"
    private const val RS_GEOIP_RU =
        "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs"
    private const val RS_GEOSITE_PRIVATE =
        "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-private.srs"

    data class Parsed(val name: String, val protocol: String, val host: String, val port: Int, val outbound: JSONObject)

    /** Parse one share link into an outbound + metadata, or null if unsupported. */
    fun parseLink(raw: String): Parsed? {
        val link = raw.trim()
        val scheme = link.substringBefore("://", "").lowercase()
        return try {
            when (scheme) {
                "hysteria2", "hy2" -> parseHysteria2(link)
                "vless" -> parseVless(link)
                "trojan" -> parseTrojan(link)
                "vmess" -> parseVmess(link)
                "ss" -> parseShadowsocks(link)
                "tuic" -> parseTuic(link)
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun nameFrom(uri: Uri, fallback: String): String {
        val frag = uri.fragment
        return if (!frag.isNullOrBlank()) Uri.decode(frag) else fallback
    }

    private fun parseHysteria2(link: String): Parsed {
        val uri = Uri.parse(link)
        val host = uri.host ?: error("no host")
        val port = if (uri.port > 0) uri.port else 443
        val password = uri.userInfo ?: ""
        val sni = uri.getQueryParameter("sni") ?: host
        val insecure = uri.getQueryParameter("insecure") == "1"
        val obfs = uri.getQueryParameter("obfs")
        val obfsPass = uri.getQueryParameter("obfs-password")

        val tls = JSONObject()
            .put("enabled", true)
            .put("server_name", sni)
            .put("insecure", insecure)
        val ob = JSONObject()
            .put("type", "hysteria2")
            .put("tag", PROXY)
            .put("server", host)
            .put("server_port", port)
            .put("password", password)
            .put("tls", tls)
        if (!obfs.isNullOrBlank() && !obfsPass.isNullOrBlank()) {
            ob.put("obfs", JSONObject().put("type", obfs).put("password", obfsPass))
        }
        return Parsed(nameFrom(uri, "HY2 $host"), "hysteria2", host, port, ob)
    }

    private fun parseVless(link: String): Parsed {
        val uri = Uri.parse(link)
        val host = uri.host ?: error("no host")
        val port = if (uri.port > 0) uri.port else 443
        val uuid = uri.userInfo ?: ""
        val security = uri.getQueryParameter("security") ?: "none"
        val sni = uri.getQueryParameter("sni") ?: uri.getQueryParameter("host") ?: host
        val flow = uri.getQueryParameter("flow")
        val ob = JSONObject()
            .put("type", "vless")
            .put("tag", PROXY)
            .put("server", host)
            .put("server_port", port)
            .put("uuid", uuid)
        if (!flow.isNullOrBlank()) ob.put("flow", flow)
        if (security == "tls" || security == "reality") {
            val tls = JSONObject().put("enabled", true).put("server_name", sni)
            val fp = uri.getQueryParameter("fp")
            if (!fp.isNullOrBlank()) tls.put("utls", JSONObject().put("enabled", true).put("fingerprint", fp))
            if (security == "reality") {
                val pbk = uri.getQueryParameter("pbk") ?: ""
                val sid = uri.getQueryParameter("sid") ?: ""
                tls.put("reality", JSONObject().put("enabled", true).put("public_key", pbk).put("short_id", sid))
            }
            ob.put("tls", tls)
        }
        val type = uri.getQueryParameter("type")
        if (type == "ws") {
            val path = uri.getQueryParameter("path") ?: "/"
            ob.put("transport", JSONObject().put("type", "ws").put("path", path))
        }
        return Parsed(nameFrom(uri, "VLESS $host"), "vless", host, port, ob)
    }

    private fun parseTrojan(link: String): Parsed {
        val uri = Uri.parse(link)
        val host = uri.host ?: error("no host")
        val port = if (uri.port > 0) uri.port else 443
        val sni = uri.getQueryParameter("sni") ?: host
        val ob = JSONObject()
            .put("type", "trojan")
            .put("tag", PROXY)
            .put("server", host)
            .put("server_port", port)
            .put("password", uri.userInfo ?: "")
            .put("tls", JSONObject().put("enabled", true).put("server_name", sni))
        return Parsed(nameFrom(uri, "Trojan $host"), "trojan", host, port, ob)
    }

    private fun b64(s: String): String {
        var t = s.trim().replace('-', '+').replace('_', '/')
        while (t.length % 4 != 0) t += "="
        return String(Base64.decode(t, Base64.DEFAULT))
    }

    private fun parseVmess(link: String): Parsed {
        val json = JSONObject(b64(link.substringAfter("://")))
        val host = json.getString("add")
        val port = json.optString("port", "443").toIntOrNull() ?: 443
        val ob = JSONObject()
            .put("type", "vmess").put("tag", PROXY).put("server", host).put("server_port", port)
            .put("uuid", json.getString("id"))
            .put("alter_id", json.optString("aid", "0").toIntOrNull() ?: 0)
            .put("security", json.optString("scy", "auto").ifEmpty { "auto" })
        if (json.optString("tls") == "tls") {
            val sni = json.optString("sni").ifEmpty { json.optString("host").ifEmpty { host } }
            ob.put("tls", JSONObject().put("enabled", true).put("server_name", sni))
        }
        if (json.optString("net") == "ws") {
            val t = JSONObject().put("type", "ws").put("path", json.optString("path", "/").ifEmpty { "/" })
            val h = json.optString("host")
            if (h.isNotEmpty()) t.put("headers", JSONObject().put("Host", h))
            ob.put("transport", t)
        }
        return Parsed(json.optString("ps").ifEmpty { "VMess $host" }, "vmess", host, port, ob)
    }

    private fun parseShadowsocks(link: String): Parsed {
        val noScheme = link.substringAfter("://")
        val frag = noScheme.substringAfter("#", "")
        val body = noScheme.substringBefore("#").substringBefore("?")
        val method: String; val password: String; val host: String; val port: Int
        if (body.contains("@")) {
            val userPart = body.substringBefore("@")
            val hostPart = body.substringAfter("@")
            val creds = if (userPart.contains(":")) userPart else b64(userPart)
            method = creds.substringBefore(":")
            password = creds.substringAfter(":")
            host = hostPart.substringBefore(":")
            port = hostPart.substringAfter(":").toInt()
        } else {
            val dec = b64(body) // method:password@host:port
            method = dec.substringBefore(":")
            val rest = dec.substringAfter(":")
            password = rest.substringBeforeLast("@")
            val hp = rest.substringAfterLast("@")
            host = hp.substringBefore(":")
            port = hp.substringAfter(":").toInt()
        }
        val ob = JSONObject().put("type", "shadowsocks").put("tag", PROXY)
            .put("server", host).put("server_port", port).put("method", method).put("password", password)
        return Parsed(if (frag.isNotEmpty()) Uri.decode(frag) else "SS $host", "shadowsocks", host, port, ob)
    }

    private fun parseTuic(link: String): Parsed {
        val uri = Uri.parse(link)
        val host = uri.host ?: error("no host")
        val port = if (uri.port > 0) uri.port else 443
        val info = uri.userInfo ?: ""
        val uuid = info.substringBefore(":")
        val password = if (info.contains(":")) info.substringAfter(":") else ""
        val sni = uri.getQueryParameter("sni") ?: host
        val tls = JSONObject().put("enabled", true).put("server_name", sni)
        if (uri.getQueryParameter("allow_insecure") == "1" || uri.getQueryParameter("insecure") == "1") tls.put("insecure", true)
        uri.getQueryParameter("alpn")?.takeIf { it.isNotBlank() }?.let { a ->
            tls.put("alpn", JSONArray().apply { a.split(",").forEach { put(it) } })
        }
        val ob = JSONObject().put("type", "tuic").put("tag", PROXY).put("server", host).put("server_port", port)
            .put("uuid", uuid).put("password", password)
            .put("congestion_control", uri.getQueryParameter("congestion_control") ?: "bbr")
            .put("tls", tls)
        return Parsed(nameFrom(uri, "TUIC $host"), "tuic", host, port, ob)
    }

    // download_detour MUST stay "direct": routing through "proxy" creates a
    // start-up dependency cycle on a fresh install (router needs the rule-sets →
    // rule-sets download through the proxy → proxy isn't up until the router
    // starts), which makes the VPN fail to start. Direct download breaks the
    // cycle. (Trade-off: where GitHub is blocked the RU rule-sets may load late.)
    private fun ruleSet(tag: String, url: String) = JSONObject()
        .put("type", "remote").put("tag", tag).put("format", "binary")
        .put("url", url).put("download_detour", "direct").put("update_interval", "72h")

    /** Build the full sing-box config (Android TUN) for [outbound]. */
    fun build(outbound: JSONObject, bypassRu: Boolean, cachePath: String): String {
        val proxy = JSONObject(outbound.toString()).put("tag", PROXY)

        val dnsRules = JSONArray()
        if (bypassRu) {
            dnsRules.put(JSONObject().put("rule_set", JSONArray().put("geosite-category-ru")).put("server", "local-ru"))
        }
        val dns = JSONObject()
            .put("servers", JSONArray()
                .put(JSONObject().put("type", "https").put("tag", "remote").put("server", "1.1.1.1").put("detour", PROXY))
                .put(JSONObject().put("type", "https").put("tag", "local-ru").put("server", "77.88.8.8")))
            .put("rules", dnsRules)
            .put("final", "remote")
            .put("strategy", "prefer_ipv4")
            .put("independent_cache", true)

        val inbounds = JSONArray().put(JSONObject()
            .put("type", "tun")
            .put("tag", "tun-in")
            .put("address", JSONArray().put("172.19.0.1/30").put("fdfe:dcba:9876::1/126"))
            .put("auto_route", true)
            .put("strict_route", true)
            .put("stack", "system"))

        val routeRules = JSONArray()
            .put(JSONObject().put("action", "sniff"))
            .put(JSONObject().put("protocol", "dns").put("action", "hijack-dns"))
            .put(JSONObject().put("ip_is_private", true).put("outbound", "direct"))
            .put(JSONObject().put("rule_set", JSONArray().put("geosite-private")).put("outbound", "direct"))
        val ruleSets = JSONArray().put(ruleSet("geosite-private", RS_GEOSITE_PRIVATE))
        if (bypassRu) {
            routeRules.put(JSONObject().put("rule_set", JSONArray().put("geosite-category-ru").put("geoip-ru")).put("outbound", "direct"))
            ruleSets.put(ruleSet("geosite-category-ru", RS_GEOSITE_RU))
            ruleSets.put(ruleSet("geoip-ru", RS_GEOIP_RU))
        }
        val route = JSONObject()
            .put("rules", routeRules)
            .put("rule_set", ruleSets)
            .put("final", PROXY)
            .put("auto_detect_interface", true)
            .put("default_domain_resolver", JSONObject().put("server", "local-ru"))

        val experimental = JSONObject()
            .put("cache_file", JSONObject().put("enabled", true).put("store_rdrc", true).put("path", cachePath))
            .put("clash_api", JSONObject().put("external_controller", "127.0.0.1:19099"))

        return JSONObject()
            .put("log", JSONObject().put("level", "warn").put("timestamp", true))
            .put("dns", dns)
            .put("inbounds", inbounds)
            .put("outbounds", JSONArray().put(proxy).put(JSONObject().put("type", "direct").put("tag", "direct")))
            .put("route", route)
            .put("experimental", experimental)
            .toString()
    }
}
