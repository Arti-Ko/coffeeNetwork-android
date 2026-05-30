package com.coffeenetwork.coffeenetwork

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.IpPrefix
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.OsConstants
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import kotlinx.coroutines.runBlocking
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.security.KeyStore
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

class CoffeeVpnService : VpnService(), PlatformInterface, CommandServerHandler {

    companion object {
        const val ACTION_START = "com.coffeenetwork.START"
        const val ACTION_STOP = "com.coffeenetwork.STOP"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_EXCLUDE = "exclude"
        private const val TAG = "CoffeeVpn"
        private const val CHANNEL = "coffeenetwork-vpn"
        private const val NOTIF_ID = 1

        @Volatile var running = false
            private set
        @Volatile var lastError: String? = null
        private var libboxSetup = false
    }

    private var commandServer: CommandServer? = null
    private var pfd: ParcelFileDescriptor? = null
    private var excludePackages: List<String> = emptyList()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        App.init(this)
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                return START_NOT_STICKY
            }
            else -> {
                val config = intent?.getStringExtra(EXTRA_CONFIG)
                excludePackages = intent?.getStringArrayListExtra(EXTRA_EXCLUDE) ?: emptyList()
                if (config.isNullOrBlank()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForegroundNotif()
                Thread { startVpn(config) }.start()
            }
        }
        return START_STICKY
    }

    private fun startVpn(config: String) {
        try {
            lastError = null
            if (!libboxSetup) {
                val base = filesDir.apply { mkdirs() }
                val work = (getExternalFilesDir(null) ?: filesDir).apply { mkdirs() }
                val tmp = cacheDir.apply { mkdirs() }
                Libbox.setup(SetupOptions().apply {
                    basePath = base.path
                    workingPath = work.path
                    tempPath = tmp.path
                    logMaxLines = 3000
                })
                libboxSetup = true
            }
            runBlocking { DefaultNetworkMonitor.start() }
            val server = CommandServer(this, this)
            server.start()
            commandServer = server
            val override = OverrideOptions().apply {
                if (excludePackages.isNotEmpty()) {
                    excludePackage = StringArray(excludePackages + packageName)
                }
            }
            server.startOrReloadService(config, override)
            running = true
        } catch (e: Exception) {
            Log.e(TAG, "startVpn", e)
            lastError = e.message ?: e.toString()
            stopVpn()
        }
    }

    private fun stopVpn() {
        running = false
        try { commandServer?.closeService() } catch (_: Exception) {}
        try { runBlocking { DefaultNetworkMonitor.stop() } } catch (_: Exception) {}
        try { commandServer?.close() } catch (_: Exception) {}
        commandServer = null
        try { pfd?.close() } catch (_: Exception) {}
        pfd = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    // ---- foreground notification (Android requires one for a VPN) ----
    private fun startForegroundNotif() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notif: Notification = Notification.Builder(this, CHANNEL)
            .setContentTitle("coffeeNetwork")
            .setContentText("VPN активен")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    // ===================== PlatformInterface =====================
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("missing vpn permission")
        val builder = Builder().setSession("coffeeNetwork").setMtu(options.mtu)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val v4 = options.inet4Address
        while (v4.hasNext()) { val a = v4.next(); builder.addAddress(a.address(), a.prefix()) }
        val v6 = options.inet6Address
        while (v6.hasNext()) { val a = v6.next(); builder.addAddress(a.address(), a.prefix()) }

        if (options.autoRoute) {
            val dns = options.dnsServerAddress
            while (dns.hasNext()) {
                try { builder.addDnsServer(dns.next()) } catch (_: Exception) {}
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r4 = options.inet4RouteAddress
                if (r4.hasNext()) { while (r4.hasNext()) builder.addRoute(r4.next().toIpPrefix()) }
                else if (options.inet4Address.hasNext()) builder.addRoute("0.0.0.0", 0)
                val r6 = options.inet6RouteAddress
                if (r6.hasNext()) { while (r6.hasNext()) builder.addRoute(r6.next().toIpPrefix()) }
                else if (options.inet6Address.hasNext()) builder.addRoute("::", 0)
                val e4 = options.inet4RouteExcludeAddress
                while (e4.hasNext()) builder.excludeRoute(e4.next().toIpPrefix())
                val e6 = options.inet6RouteExcludeAddress
                while (e6.hasNext()) builder.excludeRoute(e6.next().toIpPrefix())
            } else {
                val r4 = options.inet4RouteRange
                while (r4.hasNext()) { val a = r4.next(); builder.addRoute(a.address(), a.prefix()) }
                val r6 = options.inet6RouteRange
                while (r6.hasNext()) { val a = r6.next(); builder.addRoute(a.address(), a.prefix()) }
            }
            // per-app split: allowed apps use the tunnel, disallowed bypass it
            val incl = options.includePackage
            while (incl.hasNext()) { try { builder.addAllowedApplication(incl.next()) } catch (_: Exception) {} }
            val excl = options.excludePackage
            while (excl.hasNext()) {
                val pkg = excl.next()
                try { builder.addDisallowedApplication(pkg) } catch (e: Exception) { Log.w(TAG, "disallow $pkg failed", e) }
            }
        }
        val p = builder.establish() ?: error("android: the application is not prepared or revoked")
        pfd = p
        return p.fd
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int, sourceAddress: String, sourcePort: Int,
        destinationAddress: String, destinationPort: Int
    ): ConnectionOwner {
        val uid = App.connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort)
        )
        if (uid == Process.INVALID_UID) error("connection owner not found")
        val packages = App.packageManager.getPackagesForUid(uid)
        return ConnectionOwner().apply {
            userId = uid
            userName = packages?.firstOrNull() ?: ""
            setAndroidPackageNames(StringArray(packages?.toList() ?: emptyList()))
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(null)
    }

    @SuppressLint("MissingPermission")
    override fun getInterfaces(): NetworkInterfaceIterator {
        val networks = App.connectivity.allNetworks
        val sysIfaces = NetworkInterface.getNetworkInterfaces().toList()
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        for (network in networks) {
            val lp = App.connectivity.getLinkProperties(network) ?: continue
            val caps = App.connectivity.getNetworkCapabilities(network) ?: continue
            val sysIf = sysIfaces.find { it.name == lp.interfaceName } ?: continue
            val bi = LibboxNetworkInterface()
            bi.name = lp.interfaceName
            bi.dnsServer = StringArray(lp.dnsServers.mapNotNull { it.hostAddress })
            bi.type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            bi.index = sysIf.index
            runCatching { bi.mtu = sysIf.mtu }
            bi.addresses = StringArray(sysIf.interfaceAddresses.mapNotNull { it.toPrefix() })
            var flags = 0
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) flags = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            if (sysIf.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (sysIf.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (sysIf.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
            bi.flags = flags
            bi.metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            interfaces.add(bi)
        }
        return InterfaceArray(interfaces.iterator())
    }

    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun clearDNSCache() {}
    override fun readWIFIState(): WIFIState? = null
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification?) {}
    override fun startNeighborMonitor(listener: NeighborUpdateListener?) {}
    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) {}
    override fun registerMyInterface(name: String?) {}

    override fun systemCertificates(): StringIterator {
        val certs = mutableListOf<String>()
        try {
            val ks = KeyStore.getInstance("AndroidCAStore")
            ks?.load(null, null)
            val aliases = ks.aliases()
            while (aliases.hasMoreElements()) {
                val cert = ks.getCertificate(aliases.nextElement())
                certs.add("-----BEGIN CERTIFICATE-----\n" +
                    android.util.Base64.encodeToString(cert.encoded, android.util.Base64.NO_WRAP) +
                    "\n-----END CERTIFICATE-----")
            }
        } catch (_: Exception) {}
        return StringArray(certs)
    }

    // ===================== CommandServerHandler =====================
    override fun serviceReload() {}
    override fun serviceStop() { stopVpn() }
    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus().apply { available = false }
    override fun setSystemProxyEnabled(isEnabled: Boolean) {}
    override fun triggerNativeCrash() {}
    override fun writeDebugMessage(message: String?) { Log.d(TAG, message ?: "") }
    override fun connectSSHAgent(): Int = -1

    // ---- helpers ----
    private fun io.nekohasekai.libbox.RoutePrefix.toIpPrefix() =
        IpPrefix(java.net.InetAddress.getByName(address()), prefix())

    private fun InterfaceAddress.toPrefix(): String =
        if (address is Inet6Address) "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
        else "${address.hostAddress}/$networkPrefixLength"

    // NB: len() MUST return the real count — libbox's Go side preallocates from
    // it before iterating, so returning 0 silently drops every element (this is
    // what broke per-app exclusions / excludePackage).
    class StringArray(private val items: List<String>) : StringIterator {
        private val it = items.iterator()
        override fun len(): Int = items.size
        override fun hasNext(): Boolean = it.hasNext()
        override fun next(): String = it.next()
    }

    private class InterfaceArray(private val it: Iterator<LibboxNetworkInterface>) : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = it.hasNext()
        override fun next(): LibboxNetworkInterface = it.next()
    }
}
