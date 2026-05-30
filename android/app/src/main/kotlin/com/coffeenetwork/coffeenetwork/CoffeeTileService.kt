package com.coffeenetwork.coffeenetwork

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile (sits next to WiFi/Bluetooth). Toggles the VPN:
 * - running  -> stop
 * - stopped  -> start with the last-used server (needs prior VPN consent;
 *               otherwise opens the app to grant it).
 */
class CoffeeTileService : TileService() {

    override fun onStartListening() {
        updateTile()
    }

    override fun onClick() {
        if (CoffeeVpnService.running) {
            startService(Intent(this, CoffeeVpnService::class.java).setAction(CoffeeVpnService.ACTION_STOP))
            updateTile(forceOff = true)
            return
        }
        val prefs = getSharedPreferences("coffee", MODE_PRIVATE)
        val link = prefs.getString("link", null)
        if (link.isNullOrBlank()) {
            openApp()
            return
        }
        if (VpnService.prepare(this) != null) {
            // consent not granted yet — must go through the app/Activity
            openApp()
            return
        }
        val bypass = prefs.getBoolean("bypassRu", true)
        val exclude = prefs.getStringSet("exclude", emptySet())?.toList() ?: emptyList()
        val parsed = SingBoxConfig.parseLink(link) ?: run { openApp(); return }
        val cfg = SingBoxConfig.build(parsed.outbound, bypass, filesDir.resolve("cache.db").path)
        val intent = Intent(this, CoffeeVpnService::class.java)
            .setAction(CoffeeVpnService.ACTION_START)
            .putExtra(CoffeeVpnService.EXTRA_CONFIG, cfg)
            .putStringArrayListExtra(CoffeeVpnService.EXTRA_EXCLUDE, ArrayList(exclude))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
        updateTile(forceOn = true)
    }

    private fun openApp() {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(android.app.PendingIntent.getActivity(
                this, 0, launch,
                android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
            ))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launch)
        }
    }

    private fun updateTile(forceOn: Boolean = false, forceOff: Boolean = false) {
        val tile = qsTile ?: return
        val on = forceOn || (CoffeeVpnService.running && !forceOff)
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "coffeeNetwork"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (on) "Подключено" else "Отключено"
        }
        tile.updateTile()
    }
}
