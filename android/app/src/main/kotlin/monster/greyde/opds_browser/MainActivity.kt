package monster.greyde.opds_browser

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "monster.greyde.opds_browser/open_file",
        ).setMethodCallHandler { call, result ->
            if (call.method == "openFile") {
                val uri = call.argument<String>("uri")
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                if (uri == null) {
                    result.error("NULL_URI", "uri argument is required", null)
                    return@setMethodCallHandler
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(Uri.parse(uri), mimeType)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(null)
                } catch (e: ActivityNotFoundException) {
                    result.error("NO_APP", "No app found to open this file type", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
