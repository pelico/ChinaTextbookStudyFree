package com.cstf.app

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Bundle
import android.view.GestureDetector
import android.view.KeyEvent
import android.view.MotionEvent
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.GestureDetectorCompat
import androidx.core.view.WindowCompat
import androidx.webkit.ServiceWorkerClientCompat
import androidx.webkit.ServiceWorkerControllerCompat
import androidx.webkit.WebViewFeature

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var settingsView: LinearLayout
    private lateinit var urlEditText: EditText
    private lateinit var errorText: TextView
    private lateinit var loadingView: LinearLayout
    private lateinit var loadingProgress: ProgressBar
    private lateinit var webContainer: FrameLayout

    private val PREFS_NAME = "CSTFSettings"
    private val KEY_SERVER_URL = "server_url"

    // 三击检测
    private var tripleTapDetector: GestureDetectorCompat? = null
    private var tripleTapCount = 0
    private var tripleTapFirstTime = 0L

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, true)

        // 读取保存的服务器地址
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val savedUrl = prefs.getString(KEY_SERVER_URL, "")?.trim() ?: ""

        if (savedUrl.isNotEmpty()) {
            setupWebView()
            loadServer(savedUrl)
        } else {
            showSettingsPage()
        }
    }

    /**
     * 显示服务器地址设置页面
     */
    @SuppressLint("SetTextI18n")
    private fun showSettingsPage(editMode: Boolean = false, currentUrl: String = "") {
        settingsView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(64, 128, 64, 64)
            setBackgroundColor(Color.parseColor("#F7F7F7"))
        }

        val titleView = TextView(this).apply {
            text = if (editMode) "设置服务器地址" else "欢迎使用"
            textSize = 28f
            setTextColor(Color.parseColor("#1A1A1A"))
            setPadding(0, 0, 0, 16)
        }

        val subtitleView = TextView(this).apply {
            text = "请填写你部署的容器地址"
            textSize = 14f
            setTextColor(Color.parseColor("#888888"))
            setPadding(0, 0, 0, 48)
        }

        val labelView = TextView(this).apply {
            text = "服务器地址"
            textSize = 14f
            setTextColor(Color.parseColor("#1A1A1A"))
            setPadding(0, 0, 0, 12)
        }

        urlEditText = EditText(this).apply {
            hint = "例如：http://192.168.1.100:5230"
            textSize = 16f
            setText(if (currentUrl.isNotEmpty()) currentUrl else "https://xx.111312.xyz")
            setTextColor(Color.parseColor("#1A1A1A"))
            setBackgroundColor(Color.parseColor("#FFFFFF"))
            setPadding(48, 40, 48, 40)
            setSingleLine()
            background = null
            val shape = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#FFFFFF"))
                cornerRadius = 32f
                setStroke(4, Color.parseColor("#E5E5E5"))
            }
            setBackgroundDrawable(shape)
        }

        errorText = TextView(this).apply {
            text = ""
            textSize = 12f
            setTextColor(Color.parseColor("#FF4B4B"))
            setPadding(0, 16, 0, 0)
        }

        val connectBtn = Button(this).apply {
            text = if (editMode) "保存并重连" else "连接"
            textSize = 16f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#58CC02"))
            setPadding(0, 48, 0, 48)
            isAllCaps = false
            val shape = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#58CC02"))
                cornerRadius = 32f
            }
            setBackgroundDrawable(shape)
            setOnClickListener {
                val url = urlEditText.text.toString().trim()
                if (validateUrl(url)) {
                    saveUrl(url)
                    setupWebView()
                    loadServer(url)
                }
            }
        }

        val hintView = TextView(this).apply {
            text = "\n提示：\n• 地址格式：http://IP:端口 或 https://域名\n• 确保手机和容器在同一网络\n• 地址会保存在本地，下次自动连接\n• 连接成功后，三击屏幕左上角可重新设置\n• 白屏/黑屏？先点下方「清除缓存」试试"
            textSize = 12f
            setTextColor(Color.parseColor("#888888"))
            setPadding(0, 32, 0, 0)
        }

        val clearCacheBtn = Button(this).apply {
            text = "清除缓存并重连"
            textSize = 14f
            setTextColor(Color.parseColor("#FF4B4B"))
            setBackgroundColor(Color.parseColor("#FFFFFF"))
            setPadding(0, 36, 0, 36)
            isAllCaps = false
            val shape = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#FFFFFF"))
                cornerRadius = 32f
                setStroke(4, Color.parseColor("#FF4B4B"))
            }
            setBackgroundDrawable(shape)
            setOnClickListener {
                // 清除所有 WebView 数据
                if (::webView.isInitialized) {
                    webView.clearCache(true)
                    webView.clearHistory()
                    webView.clearFormData()
                }
                android.webkit.WebStorage.getInstance().deleteAllData()
                android.webkit.CookieManager.getInstance().removeAllCookies(null)
                Toast.makeText(this@MainActivity, "缓存已清除", Toast.LENGTH_SHORT).show()
                val url = urlEditText.text.toString().trim()
                if (validateUrl(url)) {
                    saveUrl(url)
                    setupWebView()
                    loadServer(url)
                }
            }
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            params.topMargin = 24
            layoutParams = params
        }

        val btnContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 48, 0, 0)
            addView(connectBtn)
            addView(clearCacheBtn)
        }

        settingsView.addView(titleView)
        settingsView.addView(subtitleView)
        settingsView.addView(labelView)
        settingsView.addView(urlEditText)
        settingsView.addView(errorText)
        settingsView.addView(btnContainer)
        settingsView.addView(hintView)

        setContentView(settingsView)
    }

    /**
     * 验证 URL 格式
     */
    private fun validateUrl(url: String): Boolean {
        if (url.isEmpty()) {
            errorText.text = "请输入服务器地址"
            return false
        }
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            errorText.text = "地址必须以 http:// 或 https:// 开头"
            return false
        }
        return true
    }

    /**
     * 保存服务器地址
     */
    private fun saveUrl(url: String) {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(KEY_SERVER_URL, url.trimEnd('/'))
            .apply()
    }

    /**
     * 获取保存的服务器地址
     */
    private fun getSavedUrl(): String {
        return getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getString(KEY_SERVER_URL, "") ?: ""
    }

    /**
     * 配置 WebView
     */
    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webContainer = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#FFFFFF"))
        }

        webView = WebView(this).apply {
            setBackgroundColor(Color.parseColor("#FFFFFF"))

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = true
                allowContentAccess = true
                mediaPlaybackRequiresUserGesture = false
                cacheMode = WebSettings.LOAD_NO_CACHE
                setSupportMultipleWindows(false)
                javaScriptCanOpenWindowsAutomatically = false
                mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                userAgentString = userAgentString + " ChinaStudyFree/1.0 (Android)"
                useWideViewPort = true
                loadWithOverviewMode = true
                textZoom = 100
                setSupportZoom(true)
                builtInZoomControls = false
            }

            // 注入 JS Bridge，让 Web 端可以控制后台播放保活
            addJavascriptInterface(AudioBridge(), "CSTFAndroid")

            webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                    super.onPageStarted(view, url, favicon)
                    // 页面开始加载时立刻注入：禁用 Service Worker 注册，防止坏缓存导致白屏
                    view?.evaluateJavascript(
                        """
                        (function() {
                            try {
                                if (navigator.serviceWorker) {
                                    // 禁用 register，阻止任何新的 SW 注册
                                    navigator.serviceWorker.register = function() {
                                        return Promise.reject(new Error('Service Worker disabled in app'));
                                    };
                                    // 注销已有的所有 SW 注册
                                    navigator.serviceWorker.getRegistrations().then(function(regs) {
                                        regs.forEach(function(r) { r.unregister(); });
                                    }).catch(function() {});
                                }
                            } catch(e) {}
                        })();
                        """.trimIndent(),
                        null
                    )
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    hideLoading()
                    // 页面加载完成后再注销一次 Service Worker（双重保险）
                    view?.evaluateJavascript(
                        """
                        (function() {
                            try {
                                if (navigator.serviceWorker) {
                                    navigator.serviceWorker.getRegistrations().then(function(regs) {
                                        regs.forEach(function(r) { r.unregister(); });
                                    });
                                }
                            } catch(e) {}
                        })();
                        """.trimIndent(),
                        null
                    )
                    // 注入音频监听脚本：用事件捕获代替原型 hook，更安全
                    view?.evaluateJavascript(
                        """
                        (function() {
                            try {
                                if (window.__cstfAudioInjected) return;
                                window.__cstfAudioInjected = true;
                                var playingCount = 0;
                                document.addEventListener('play', function() {
                                    playingCount++;
                                    if (playingCount === 1 && window.CSTFAndroid) {
                                        window.CSTFAndroid.startPlayback();
                                    }
                                }, true);
                                document.addEventListener('pause', function() {
                                    if (playingCount > 0) playingCount--;
                                    if (playingCount === 0 && window.CSTFAndroid) {
                                        window.CSTFAndroid.stopPlayback();
                                    }
                                }, true);
                                document.addEventListener('ended', function() {
                                    if (playingCount > 0) playingCount--;
                                    if (playingCount === 0 && window.CSTFAndroid) {
                                        window.CSTFAndroid.stopPlayback();
                                    }
                                }, true);
                            } catch(e) {
                                console.warn('CSTF audio listener failed:', e);
                            }
                        })();
                        """.trimIndent(),
                        null
                    )
                }

                override fun onReceivedError(
                    view: WebView?,
                    errorCode: Int,
                    description: String?,
                    failingUrl: String?
                ) {
                    super.onReceivedError(view, errorCode, description, failingUrl)
                    runOnUiThread {
                        hideLoading()
                        if (::webView.isInitialized && webView.parent != null) {
                            showSettingsPage(true, getSavedUrl())
                            errorText.text = "连接失败：$description\n请检查地址是否正确，容器是否正常运行"
                        }
                    }
                }
            }

            // 添加 WebChromeClient 以支持 JS console 和对话框
            webChromeClient = object : android.webkit.WebChromeClient() {
                override fun onConsoleMessage(consoleMessage: android.webkit.ConsoleMessage): Boolean {
                    android.util.Log.d("CSTF-Web", consoleMessage.message())
                    return true
                }
            }
        }

        // 三击左上角呼出设置
        tripleTapDetector = GestureDetectorCompat(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                val x = e.rawX
                val y = e.rawY
                val displayMetrics = resources.displayMetrics
                val tapAreaWidth = displayMetrics.widthPixels * 0.15f  // 左上角 15% 区域
                val tapAreaHeight = displayMetrics.heightPixels * 0.1f // 顶部 10% 区域

                if (x < tapAreaWidth && y < tapAreaHeight) {
                    val now = System.currentTimeMillis()
                    if (now - tripleTapFirstTime > 800) {
                        tripleTapCount = 1
                        tripleTapFirstTime = now
                    } else {
                        tripleTapCount++
                        if (tripleTapCount >= 3) {
                            tripleTapCount = 0
                            runOnUiThread {
                                showSettingsPage(true, getSavedUrl())
                                Toast.makeText(this@MainActivity, "已进入设置模式", Toast.LENGTH_SHORT).show()
                            }
                        }
                    }
                }
                return super.onSingleTapUp(e)
            }
        })

        webContainer.addView(webView)

        // 每次创建 WebView 时清除旧的缓存和历史
        webView.clearCache(true)
        webView.clearHistory()
        // 清除 Service Worker 缓存
        webView.clearFormData()
        android.webkit.WebStorage.getInstance().deleteAllData()

        WebView.setWebContentsDebuggingEnabled(true)

        // 禁用 Service Worker —— APP 是实时加载服务器内容的，不需要离线缓存
        // Service Worker 缓存坏页面会导致白屏/黑屏且难以清除（按域名隔离）
        if (WebViewFeature.isFeatureSupported(WebViewFeature.SERVICE_WORKER_BASIC_USAGE)) {
            try {
                val swController = ServiceWorkerControllerCompat.getInstance()
                // 拦截所有 Service Worker 脚本请求，返回空，阻止 SW 注册
                swController.setServiceWorkerClient(object : ServiceWorkerClientCompat() {
                    override fun shouldInterceptRequest(request: WebResourceRequest): android.webkit.WebResourceResponse? {
                        val url = request.url.toString()
                        // 如果请求的是 sw.js 或 service-worker 相关脚本，返回 404 阻止注册
                        if (url.contains("sw.js") || url.contains("service-worker")) {
                            return android.webkit.WebResourceResponse("text/plain", "utf-8", null)
                        }
                        return null
                    }
                })
                val swSettings = swController.serviceWorkerWebSettings
                swSettings.allowContentAccess = false
                swSettings.allowFileAccess = false
                // 禁止 Service Worker 缓存
                swSettings.cacheMode = WebSettings.LOAD_NO_CACHE
            } catch (_: Exception) {}
        }
    }

    /**
     * 加载服务器
     */
    private fun loadServer(url: String) {
        showLoading()

        val cleanUrl = url.trimEnd('/')
        webView.loadUrl(cleanUrl + "/")
        setContentView(webContainer)
    }

    /**
     * 显示加载中
     */
    private fun showLoading() {
        if (!::loadingView.isInitialized) {
            loadingView = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = android.view.Gravity.CENTER
                setBackgroundColor(Color.parseColor("#F7F7F7"))
            }
            loadingProgress = ProgressBar(this).apply {
                setPadding(0, 0, 0, 32)
            }
            val loadingText = TextView(this).apply {
                text = "正在连接..."
                textSize = 14f
                setTextColor(Color.parseColor("#888888"))
                gravity = android.view.Gravity.CENTER
            }
            loadingView.addView(loadingProgress)
            loadingView.addView(loadingText)
        }
        if (::webContainer.isInitialized) {
            webContainer.addView(loadingView)
        }
    }

    private fun hideLoading() {
        if (::loadingView.isInitialized && loadingView.parent != null) {
            (loadingView.parent as android.view.ViewGroup).removeView(loadingView)
        }
    }

    /**
     * 触摸事件分发：三击检测
     */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        tripleTapDetector?.onTouchEvent(ev)
        return super.dispatchTouchEvent(ev)
    }

    /**
     * 双击返回键退出，单击返回上一页
     */
    private var lastBackTime = 0L

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (::webView.isInitialized && webView.canGoBack() && webView.parent != null) {
                webView.goBack()
                return true
            }
            // 如果在设置页面，直接退出
            if (!::webView.isInitialized || webView.parent == null) {
                return super.onKeyDown(keyCode, event)
            }
            // 双击退出
            val now = System.currentTimeMillis()
            if (now - lastBackTime < 2000) {
                return super.onKeyDown(keyCode, event)
            }
            lastBackTime = now
            Toast.makeText(this, "再按一次退出应用", Toast.LENGTH_SHORT).show()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onPause() {
        super.onPause()
        if (::webView.isInitialized) webView.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (::webView.isInitialized) webView.onResume()
    }

    override fun onDestroy() {
        AudioPlaybackService.stop(this)
        if (::webView.isInitialized) webView.destroy()
        super.onDestroy()
    }

    /**
     * JS Bridge：让 Web 页面可以控制后台播放保活服务
     */
    inner class AudioBridge {
        @JavascriptInterface
        fun startPlayback() {
            AudioPlaybackService.start(this@MainActivity, "正在播放")
        }

        @JavascriptInterface
        fun stopPlayback() {
            AudioPlaybackService.stop(this@MainActivity)
        }
    }
}
