package com.cstf.app

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.webkit.WebViewAssetLoader

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, true)

        val assetLoader = WebViewAssetLoader.Builder()
            .setDomain("appassets.androidplatform.net")
            .addPathHandler("/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        webView = WebView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = true
                allowContentAccess = true
                mediaPlaybackRequiresUserGesture = false
                cacheMode = android.webkit.WebSettings.LOAD_DEFAULT
                userAgentString = userAgentString + " ChinaStudyFree/1.0"
                useWideViewPort = true
                loadWithOverviewMode = true
            }

            webViewClient = AppWebViewClient(assetLoader)

            loadUrl("https://appassets.androidplatform.net/index.html")
        }

        setContentView(webView)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && webView.canGoBack()) {
            webView.goBack()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onPause() {
        super.onPause()
        webView.onPause()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }

    private inner class AppWebViewClient(
        private val assetLoader: WebViewAssetLoader,
    ) : WebViewClient() {

        override fun shouldInterceptRequest(
            view: WebView?,
            request: WebResourceRequest?,
        ): WebResourceResponse? {
            return assetLoader.shouldInterceptRequest(view, request)
        }

        override fun onReceivedError(
            view: WebView?,
            request: WebResourceRequest?,
            error: android.webkit.WebResourceError?,
        ) {
            // 加载本地错误页或忽略
        }
    }
}
