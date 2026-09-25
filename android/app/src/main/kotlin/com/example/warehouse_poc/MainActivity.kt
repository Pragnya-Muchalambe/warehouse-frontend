package com.example.warehouse_poc

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newCachedThreadPool()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "warehouse/http")
            .setMethodCallHandler { call, result ->
                if (call.method != "send") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                @Suppress("UNCHECKED_CAST")
                val arguments = call.arguments as Map<String, Any?>
                executor.execute {
                    try {
                        val response = send(arguments)
                        runOnUiThread { result.success(response) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("HTTP_ERROR", error.message, null) }
                    }
                }
            }
    }

    private fun send(arguments: Map<String, Any?>): Map<String, Any?> {
        val url = arguments["url"] as String
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = arguments["method"] as String
        connection.connectTimeout = 30_000
        connection.readTimeout = 30_000
        // API redirects are not followed so credentials cannot cross origins.
        connection.instanceFollowRedirects = false

        @Suppress("UNCHECKED_CAST")
        val headers = arguments["headers"] as Map<String, String>
        headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.getCookie(url)?.takeIf { it.isNotBlank() }?.let {
            connection.setRequestProperty("Cookie", it)
        }

        val body = arguments["body"] as ByteArray
        if (body.isNotEmpty()) {
            connection.doOutput = true
            connection.outputStream.use { it.write(body) }
        }

        val statusCode = connection.responseCode
        connection.headerFields.forEach { (name, values) ->
            if (name.equals("Set-Cookie", ignoreCase = true)) {
                values.forEach { cookieManager.setCookie(url, it) }
            }
        }
        cookieManager.flush()

        val responseHeaders = mutableMapOf<String, String>()
        connection.headerFields.forEach { (name, values) ->
            if (name != null && !name.equals("Set-Cookie", ignoreCase = true)) {
                responseHeaders[name] = values.joinToString(",")
            }
        }
        val stream = if (statusCode >= 400) connection.errorStream else connection.inputStream
        val responseBody = stream?.use { it.readBytes() } ?: ByteArray(0)
        val response = mapOf(
            "statusCode" to statusCode,
            "reasonPhrase" to connection.responseMessage,
            "headers" to responseHeaders,
            "body" to responseBody,
        )
        connection.disconnect()
        return response
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}
