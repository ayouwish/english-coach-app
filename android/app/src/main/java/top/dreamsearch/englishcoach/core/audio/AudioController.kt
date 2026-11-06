package top.dreamsearch.englishcoach.core.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.util.FileUtil
import top.dreamsearch.englishcoach.core.util.Logx
import java.io.File

/**
 * 录音结果（上传需要的全部信息；对应 hos `AudioRecorder.RecordingResult`）。
 *
 * @property file 本地 m4a 文件（`filesDir/recordings/`）
 * @property durationMs 实际录音时长（毫秒，用 elapsedRealtime 差值，不用文件大小反推）
 * @property sizeBytes 文件字节数
 */
data class RecordingResult(
    val file: File,
    val durationMs: Long,
    val sizeBytes: Long,
)

/**
 * 录音 / 播放协调器（移植 hos `core/audio/AudioController.ets`，docs/audio.md §5）。
 *
 * 通用约定：
 * - 任何时刻最多一个录音器、一个播放器；
 * - **录音前自动 [stopPlayback]**（蓝牙 HFP 铁律：先停播放再开麦，否则录音发闷）；
 * - 录音中不允许播放（抛 [ApiErrorCode.PLAYBACK_FAILED]，提示「先说完这一句」）；
 * - 页面销毁/切后台调用 [release]（丢弃录音 + 停播放）。
 *
 * 录音参数（CONTRACT §4.1 / docs/audio.md §3.1）：
 * **m4a / AAC-LC / 16 kHz / 单声道 / 64 kbps**，无降码率分支。
 *
 * 错误约定：本地失败统一抛 [ApiError]（status = 0），页面用 `ErrorMapper` 转中文文案：
 * - 未授权 → `mic_denied`；
 * - 创建/准备失败 → `record_failed`；
 * - start 被占用 → `mic_unavailable`；
 * - 停止后 <0.6s → `record_too_short`（此时文件已删除，页面无需再清理）；
 * - >12MB → `record_too_large`；
 * - 播放失败 → `playback_failed`。
 *
 * 时长上限 60s 说明：`RecordingResult.durationMs` 会给页面，页面计时器到 60s 调
 * [stopRecording]；这里不再抛「太长」错误（CONTRACT §4.1 允许页面判断）。12MB 只是兜底。
 *
 * 所有方法应在主线程调用（MediaPlayer/MediaRecorder 的状态机在同一线程上最稳）。
 */
class AudioController(context: Context) {

    private val appContext: Context = context.applicationContext

    private val _recording = MutableStateFlow(false)
    private val _playing = MutableStateFlow(false)

    /** 是否正在录音（页面用它切按钮文案/计时）。 */
    val recording: StateFlow<Boolean> = _recording.asStateFlow()

    /** 是否正在播放（页面用它切「播放中… / 停止」）。 */
    val playing: StateFlow<Boolean> = _playing.asStateFlow()

    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var recordingStartedAtElapsed: Long = 0L

    private var player: MediaPlayer? = null

    // ------------------------------------------------------------------ 录音

    /**
     * 开始录音并返回目标文件（失败抛 [ApiError]）。
     *
     * 顺序：权限检查 → 停播放（铁律）→ 建文件 → 配置并启动 MediaRecorder。
     *
     * @param prefix 文件名前缀（如跟读 rec、对话 chat），保证同目录不重名
     */
    @Synchronized
    fun startRecording(prefix: String = "rec"): File {
        if (!MicPermission.isGranted(appContext)) {
            throw ApiError(ApiErrorCode.MIC_DENIED, 0, "麦克风未授权")
        }
        if (_recording.value) {
            throw ApiError(ApiErrorCode.RECORD_FAILED, 0, "当前已经在录音了")
        }
        // 铁律：录音前必须停播放，否则蓝牙会切 HFP，录出来的声音发闷
        stopPlayback()

        val dir = File(appContext.filesDir, "recordings")
        FileUtil.ensureDir(dir)
        val safePrefix = prefix
            .filter { it.isLetterOrDigit() || it == '_' || it == '-' }
            .ifEmpty { "rec" }
        val file = File(dir, "${safePrefix}_${System.currentTimeMillis()}.m4a")

        val recorder = try {
            createRecorder()
        } catch (e: Exception) {
            Logx.e(TAG, "create MediaRecorder failed", e)
            throw ApiError(ApiErrorCode.RECORD_FAILED, 0, "录音功能暂时不可用，请重启 App 后再试")
        }

        try {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioSamplingRate(SAMPLE_RATE)
            recorder.setAudioChannels(CHANNELS)
            recorder.setAudioEncodingBitRate(BITRATE)
            recorder.setOutputFile(file.absolutePath)
            recorder.prepare()
        } catch (e: SecurityException) {
            releaseQuietly(recorder)
            file.delete()
            throw ApiError(ApiErrorCode.MIC_DENIED, 0, "麦克风未授权")
        } catch (e: Exception) {
            Logx.e(TAG, "prepare recorder failed", e)
            releaseQuietly(recorder)
            file.delete()
            throw ApiError(ApiErrorCode.RECORD_FAILED, 0, "录音功能暂时不可用，请重启 App 后再试")
        }

        try {
            recorder.start()
        } catch (e: SecurityException) {
            releaseQuietly(recorder)
            file.delete()
            throw ApiError(ApiErrorCode.MIC_DENIED, 0, "麦克风未授权")
        } catch (e: Exception) {
            Logx.e(TAG, "start recorder failed", e)
            releaseQuietly(recorder)
            file.delete()
            throw ApiError(ApiErrorCode.MIC_UNAVAILABLE, 0, "麦克风被占用了，请关闭其他录音应用后重试")
        }

        this.recorder = recorder
        this.recordingFile = file
        this.recordingStartedAtElapsed = SystemClock.elapsedRealtime()
        _recording.value = true
        Logx.d(TAG, "startRecording file=${file.name}")
        return file
    }

    /**
     * 停止录音并返回结果；空文件/过短/超大都在这里拦掉（文件已删除，不提交评测）。
     */
    @Synchronized
    fun stopRecording(): RecordingResult {
        val recorder = this.recorder
        val file = this.recordingFile
        if (recorder == null || file == null || !_recording.value) {
            throw ApiError(ApiErrorCode.RECORD_FAILED, 0, "当前没有在录音")
        }
        val durationMs = (SystemClock.elapsedRealtime() - recordingStartedAtElapsed).coerceAtLeast(0L)

        var stopFailure: Throwable? = null
        try {
            recorder.stop()
        } catch (e: RuntimeException) {
            // 刚 start 就 stop（没录到数据）会抛；文件不可用
            stopFailure = e
            Logx.w(TAG, "MediaRecorder.stop failed", e)
        }
        releaseQuietly(recorder)
        clearRecordingState()

        val sizeBytes = if (file.exists()) file.length() else 0L
        if (stopFailure != null) {
            file.delete()
            if (durationMs < MIN_DURATION_MS) {
                throw ApiError(ApiErrorCode.RECORD_TOO_SHORT, 0, "录音太短（少于 0.6 秒），请读完整句后重试")
            }
            throw ApiError(ApiErrorCode.RECORD_FAILED, 0, "录音没有录到声音，请重试")
        }
        if (sizeBytes <= 0L) {
            file.delete()
            throw ApiError(ApiErrorCode.RECORD_FAILED, 0, "录音文件为空，请重试")
        }
        if (durationMs < MIN_DURATION_MS) {
            file.delete()
            throw ApiError(ApiErrorCode.RECORD_TOO_SHORT, 0, "录音太短（少于 0.6 秒），请读完整句后重试")
        }
        if (sizeBytes > MAX_SIZE_BYTES) {
            file.delete()
            throw ApiError(ApiErrorCode.RECORD_TOO_LARGE, 0, "录音超过 12MB，请缩短录音")
        }
        Logx.d(TAG, "stopRecording duration=${durationMs}ms size=$sizeBytes")
        return RecordingResult(file = file, durationMs = durationMs, sizeBytes = sizeBytes)
    }

    /** 取消录音：停止（尽力）、删除文件、释放；可重复调用。 */
    @Synchronized
    fun cancelRecording() {
        val recorder = this.recorder
        val file = this.recordingFile
        if (recorder != null) {
            try {
                recorder.stop()
            } catch (e: RuntimeException) {
                Logx.d(TAG, "cancelRecording: stop ignored (${e.message})")
            }
            releaseQuietly(recorder)
        }
        clearRecordingState()
        file?.delete()
    }

    // ------------------------------------------------------------------ 播放

    /**
     * 播放本地文件（m4a/wav/mp3…）；同一时刻只保留一个播放器。
     *
     * @param onComplete 播放**自然结束**时在主线程回调；停止/出错不回调（页面看 [playing]
     *   或自己的状态即可）。蓝牙铁律的另一半：录音中不允许播放。
     */
    @Synchronized
    fun playFile(file: File, onComplete: (() -> Unit)? = null) {
        if (_recording.value) {
            throw ApiError(ApiErrorCode.PLAYBACK_FAILED, 0, "正在录音，先说完这一句")
        }
        if (!file.exists() || file.length() <= 0L) {
            throw ApiError(ApiErrorCode.PLAYBACK_FAILED, 0, "音频文件不存在")
        }
        stopPlayback()

        val mediaPlayer = MediaPlayer()
        try {
            mediaPlayer.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            mediaPlayer.setDataSource(file.absolutePath)
            mediaPlayer.setOnCompletionListener { mp -> handleCompletion(mp, onComplete) }
            mediaPlayer.setOnErrorListener { mp, what, extra ->
                Logx.w(TAG, "MediaPlayer error what=$what extra=$extra")
                handlePlaybackError(mp)
                true
            }
            mediaPlayer.prepare()
            mediaPlayer.start()
        } catch (e: Exception) {
            Logx.e(TAG, "play failed", e)
            releaseQuietly(mediaPlayer)
            throw ApiError(ApiErrorCode.PLAYBACK_FAILED, 0, "声音播放失败，请再试一次")
        }

        player = mediaPlayer
        _playing.value = true
        Logx.d(TAG, "play file=${file.name} size=${file.length()}")
    }

    /**
     * 播放内存字节（TTS 响应）：先原子写到 `cacheDir/audio/` 再走 [playFile]。
     * 文件名由 hint + 内容哈希决定，同一段音频重复播放命中缓存。
     */
    @Synchronized
    fun playBytes(bytes: ByteArray, fileNameHint: String = "tts.wav") {
        if (bytes.isEmpty()) {
            throw ApiError(ApiErrorCode.PLAYBACK_FAILED, 0, "音频内容为空")
        }
        val dir = File(appContext.cacheDir, "audio")
        FileUtil.ensureDir(dir)
        val extension = audioExtensionOf(fileNameHint)
        val file = File(
            dir,
            FileUtil.safeName("${fileNameHint}_${bytes.size}_${bytes.contentHashCode()}") + "." + extension,
        )
        if (!file.exists() || file.length() != bytes.size.toLong()) {
            try {
                FileUtil.writeBytesAtomic(file, bytes)
            } catch (e: Exception) {
                Logx.e(TAG, "write audio cache failed", e)
                throw ApiError(ApiErrorCode.PLAYBACK_FAILED, 0, "音频缓存失败，请重试")
            }
        }
        playFile(file)
    }

    /** 停止播放（幂等；不触发 onComplete）。 */
    @Synchronized
    fun stopPlayback() {
        val mediaPlayer = player
        player = null
        _playing.value = false
        if (mediaPlayer != null) {
            runCatching { mediaPlayer.setOnCompletionListener(null) }
            runCatching { mediaPlayer.setOnErrorListener(null) }
            runCatching { if (mediaPlayer.isPlaying) mediaPlayer.stop() }
            runCatching { mediaPlayer.reset() }
            runCatching { mediaPlayer.release() }
        }
    }

    /** 页面销毁/切后台：丢弃录音 + 停止播放。之后仍可继续使用（下次会重新创建）。 */
    @Synchronized
    fun release() {
        cancelRecording()
        stopPlayback()
    }

    // ------------------------------------------------------------------ 内部实现

    private fun handleCompletion(mediaPlayer: MediaPlayer, onComplete: (() -> Unit)?) {
        // 已被 stop/新播放替换时忽略旧回调，避免误回调上一段的 onComplete
        if (player !== mediaPlayer) return
        player = null
        _playing.value = false
        releaseQuietly(mediaPlayer)
        onComplete?.invoke()
    }

    private fun handlePlaybackError(mediaPlayer: MediaPlayer) {
        if (player !== mediaPlayer) return
        player = null
        _playing.value = false
        releaseQuietly(mediaPlayer)
    }

    private fun clearRecordingState() {
        recorder = null
        recordingFile = null
        recordingStartedAtElapsed = 0L
        _recording.value = false
    }

    private fun releaseQuietly(mediaRecorder: MediaRecorder) {
        runCatching { mediaRecorder.release() }
    }

    private fun releaseQuietly(mediaPlayer: MediaPlayer) {
        runCatching { mediaPlayer.release() }
    }

    @Suppress("DEPRECATION")
    private fun createRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(appContext)
        } else {
            MediaRecorder()
        }

    private fun audioExtensionOf(fileNameHint: String): String {
        val extension = fileNameHint.substringAfterLast('.', "").lowercase()
        return if (extension in AUDIO_EXTENSIONS) extension else "wav"
    }

    companion object {
        private const val TAG = "Audio"

        /** 录音采样率（Hz）：与服务端 16k 处理管线一致，少一次重采样。 */
        const val SAMPLE_RATE = 16_000

        /** 单声道。 */
        const val CHANNELS = 1

        /** 码率（bps）：16k 语音的舒适码率，60s 约 0.49MB。 */
        const val BITRATE = 64_000

        /** 最短录音时长（ms）：低于则丢弃，不提交评测。 */
        const val MIN_DURATION_MS = 600L

        /** 最长录音时长（ms）：页面计时器到点调 [stopRecording]。 */
        const val MAX_DURATION_MS = 60_000L

        /** 录音大小兜底上限（12MB，服务端限制）。 */
        const val MAX_SIZE_BYTES = 12L * 1024 * 1024

        private val AUDIO_EXTENSIONS = setOf("wav", "mp3", "m4a", "aac", "ogg", "webm", "flac")
    }
}
