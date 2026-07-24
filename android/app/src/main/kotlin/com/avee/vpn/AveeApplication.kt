package com.avee.vpn;

import android.app.Application
import android.content.Context
import androidx.lifecycle.Observer
import com.avee.vpn.widgets.AveeWidgetProvider

class AveeApplication : Application() {
    companion object {
        private lateinit var instance: AveeApplication
        fun getAppContext(): Context {
            return instance.applicationContext
        }
    }

    private val widgetObserver = Observer<RunState> {
        AveeWidgetProvider.updateAllWidgets(this)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        GlobalState.runState.observeForever(widgetObserver)
    }
}