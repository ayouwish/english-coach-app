package top.dreamsearch.englishcoach.core.audio

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

/**
 * 麦克风权限状态（对应 hos `AudioRecorder.ets` 里的 `MicPermission`，docs/audio.md §2）。
 *
 * 用法（页面）：第一次点录音时判断 [granted]：
 * - true  → 直接 `audio.startRecording()`
 * - false → 调用 [request]；返回后仍 false 就展示 `ApiErrorCode.MIC_DENIED` 文案。
 *
 * [request] 的行为：
 * 1. 已授权 → 不弹框，直接置 granted；
 * 2. 首次申请 / 还可再次询问 → 弹系统权限框；
 * 3. 已被「拒绝且不再询问」（或用户手工撤销）→ 直接拉起本应用的系统设置页，
 *    页面从设置返回时 [granted] 会在 ON_RESUME 自动刷新。
 */
class MicPermission(
    val granted: Boolean,
    val request: () -> Unit,
) {
    companion object {
        fun isGranted(context: Context): Boolean =
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }
}

/**
 * 记住麦克风权限 + 申请入口。
 *
 * - **不在启动时申请**，只有页面第一次点录音（调用 `request()`）才弹框；
 * - 从系统设置返回（ON_RESUME）自动重新检查，用户授权后无需重启页面。
 */
@Composable
fun rememberMicPermission(): MicPermission {
    val context = LocalContext.current
    var granted by remember { mutableStateOf(MicPermission.isGranted(context)) }
    var requestedOnce by remember { mutableStateOf(false) }

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { result ->
        requestedOnce = true
        granted = result || MicPermission.isGranted(context)
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                granted = MicPermission.isGranted(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    return MicPermission(granted = granted) {
        when {
            MicPermission.isGranted(context) -> granted = true
            else -> {
                val activity = context.findActivity()
                val permanentlyDenied = requestedOnce && activity != null &&
                    !activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
                if (permanentlyDenied) {
                    openAppSettings(context)
                } else {
                    launcher.launch(Manifest.permission.RECORD_AUDIO)
                }
            }
        }
    }
}

/** 从任意 Context 找到宿主 Activity（权限 rationale 判断需要 Activity）。 */
private fun Context.findActivity(): Activity? {
    var candidate: Context = this
    while (candidate is ContextWrapper) {
        if (candidate is Activity) return candidate
        candidate = candidate.baseContext
    }
    return null
}

/** 打开本应用的系统设置页（用户手动授权麦克风）。 */
private fun openAppSettings(context: Context) {
    val intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context.packageName, null),
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
}
