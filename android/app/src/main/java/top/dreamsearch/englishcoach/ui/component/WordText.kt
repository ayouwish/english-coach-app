package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 可点单词正文（移植 hos `components/WordText.ets`，签名按 android/CONTRACT.md §4）。
 *
 * - 点单词只弹「单词 + /音标/」弹层，不发音、不调 TTS；
 * - 儿童模式（[LocalIsChild]）或 `showIpa = false` 时退化为普通整段文字，不出现下划线；
 * - 音标查询走 `AppGraph.container.dictionary.wordIpa(word)`，本地 LRU（500 词）避免重复请求；
 *   查不到（null）也缓存，弹层显示「暂无音标」；
 * - 保留原文空格与标点，渲染后与原文一致。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WordText(
    text: String,
    isChild: Boolean = LocalIsChild.current,
    showIpa: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val enableIpa = showIpa && !isChild
    val bodySize = if (isChild) EcFont.childBody else EcFont.body
    // 行高按 docs/design-system.md §2.2：body 16/24、child_body 19/28
    val lineHeight = if (isChild) 28.sp else 24.sp

    if (!enableIpa) {
        Text(
            text = text,
            modifier = modifier.fillMaxWidth(),
            fontSize = bodySize,
            lineHeight = lineHeight,
            color = EcColor.ink,
        )
        return
    }

    val tokens = remember(text) { tokenize(text) }
    val scope = rememberCoroutineScope()
    var popup by remember { mutableStateOf<IpaPopup?>(null) }

    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        tokens.forEach { token ->
            if (token.isWord) {
                Box(
                    modifier = Modifier
                        .drawBehind {
                            val y = size.height - 3.dp.toPx()
                            drawLine(
                                color = EcColor.border,
                                start = Offset(0f, y),
                                end = Offset(size.width, y),
                                strokeWidth = 1.dp.toPx(),
                            )
                        }
                        .clickable {
                            val word = token.text
                            popup = IpaPopup(word = word, ipa = null, loading = true)
                            scope.launch {
                                val ipa = resolveIpa(word)
                                popup = IpaPopup(word = word, ipa = ipa, loading = false)
                            }
                        },
                ) {
                    Text(
                        text = token.text,
                        fontSize = bodySize,
                        lineHeight = bodySize,
                        color = EcColor.ink,
                    )
                }
            } else {
                Text(
                    text = token.text,
                    fontSize = bodySize,
                    lineHeight = bodySize,
                    color = EcColor.ink,
                )
            }
        }
    }

    popup?.let { state ->
        EcDialog(title = state.word, onDismiss = { popup = null }) {
            Text(
                text = when {
                    state.loading -> "查询中…"
                    state.ipa.isNullOrEmpty() -> "暂无音标"
                    else -> "/" + state.ipa + "/"
                },
                modifier = Modifier.fillMaxWidth(),
                fontSize = EcFont.body,
                color = EcColor.ink,
            )
            EcButton(
                label = "知道了",
                onClick = { popup = null },
                kind = EcButtonKind.SECONDARY,
                fullWidth = true,
            )
        }
    }
}

/** 音标弹层的一次展示状态（loading 时先占位，避免点了没反应）。 */
private data class IpaPopup(
    val word: String,
    val ipa: String?,
    val loading: Boolean,
)

/** 单词 / 非单词切分结果（保留标点与空格，渲染后与原文一致）。 */
private data class WordToken(val text: String, val isWord: Boolean)

/** 按字母/撇号/连字符切词，其余字符（空格、标点）原样保留（照抄 hos 规则）。 */
private fun tokenize(value: String): List<WordToken> {
    val out = ArrayList<WordToken>()
    var plain = StringBuilder()
    var word = StringBuilder()
    for (ch in value) {
        val code = ch.code
        val isLetter = (code in 65..90) || (code in 97..122)
        val isJoiner = ch == '\'' || ch == '’' || ch == '-'
        if (isLetter || (isJoiner && word.isNotEmpty() && plain.isEmpty())) {
            if (plain.isNotEmpty()) {
                out.add(WordToken(plain.toString(), false))
                plain = StringBuilder()
            }
            word.append(ch)
        } else {
            if (word.isNotEmpty()) {
                out.add(WordToken(word.toString(), true))
                word = StringBuilder()
            }
            plain.append(ch)
        }
    }
    if (word.isNotEmpty()) out.add(WordToken(word.toString(), true))
    if (plain.isNotEmpty()) out.add(WordToken(plain.toString(), false))
    return out
}

/**
 * 音标查询：先查本地 LRU，再走 DictionaryService；结果（含 null）都写入缓存。
 * 数据层不可用时静默返回 null（弹层显示「暂无音标」），不阻塞正文渲染。
 */
private suspend fun resolveIpa(word: String): String? {
    val key = word.lowercase()
    if (IpaCache.contains(key)) {
        return IpaCache.get(key)?.takeIf { it.isNotEmpty() }
    }
    val ipa = runCatching { AppGraph.container.dictionary.wordIpa(word) }.getOrNull()
    IpaCache.put(key, ipa)
    return ipa
}

/**
 * 音标本地 LRU（最多 500 词，accessOrder = true 的 LinkedHashMap）。
 * 空串表示「已查询过、服务端无音标」，避免同一单词反复请求。
 */
private object IpaCache {
    private const val MAX_ENTRIES = 500

    private val entries = object : LinkedHashMap<String, String>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>?): Boolean =
            size > MAX_ENTRIES
    }

    @Synchronized
    fun contains(word: String): Boolean = entries.containsKey(word)

    @Synchronized
    fun get(word: String): String? = entries[word]

    @Synchronized
    fun put(word: String, ipa: String?) {
        entries[word] = ipa ?: ""
    }
}
