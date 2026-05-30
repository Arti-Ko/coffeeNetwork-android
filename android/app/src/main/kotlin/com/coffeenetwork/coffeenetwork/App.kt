package com.coffeenetwork.coffeenetwork

import android.content.Context
import android.net.ConnectivityManager
import androidx.core.content.getSystemService

/** Process-wide context holder for the native VPN layer. */
object App {
    lateinit var context: Context
        private set

    fun init(c: Context) {
        if (!::context.isInitialized) context = c.applicationContext
    }

    val connectivity: ConnectivityManager by lazy { context.getSystemService()!! }
    val packageManager get() = context.packageManager
}
