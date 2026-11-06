package top.dreamsearch.englishcoach.ui.page.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.WordText
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcScore
import top.dreamsearch.englishcoach.ui.design.EcSpace

/**
 * 对话训练的共享组件（会话页 / 历史详情页共用）。
 *
 * 对应 hos：`pages/ChatSessionPage.ets` 里的 `ChatBubbleView` 与 `ChatReplayCard`。
 * 组件只依赖 primitives + 回调（不 import service），状态由调用方传入。
 */

// ---------------------------------------------------------------------------
// 消息气泡
// ---------------------------------------------------------------------------

/** 一条消息气泡：用户右侧（主题浅底）/ 助手左侧（白底 + 细边）。 */
@Composable
fun ChatBubble(
    msg: ChatMessageUi,
    isChild: Boolean,
    wordsExpanded: Boolean,
    onPlayTap: () -> Unit,
    onWordsTap: () -> Unit,
) {
    val shape = RoundedCornerShape(EcRadius.lg)
    val bubbleBg = if (msg.isUser) EcColor.primarySoft else EcColor.surface
    // 气泡宽度：内容自适应，最宽 90%（等价 hos `constraintSize({maxWidth:'88%'})`）
    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
        val bubbleMaxWidth = maxWidth * 0.9f
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = if (msg.isUser) Arrangement.End else Arrangement.Start,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = bubbleMaxWidth)
                    .clip(shape)
                    .background(bubbleBg)
                    .then(if (msg.isUser) Modifier else Modifier.border(1.dp, EcColor.border, shape))
                    .padding(EcSpace.x3),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                // 英文正文：所有英文都走 WordText（成人可点词看音标，儿童自动退化纯文本）
                WordText(text = msg.text, isChild = isChild, showIpa = true)

                if (msg.textZh.isNotEmpty()) {
                    Text(
                        text = msg.textZh,
                        fontSize = EcFont.caption,
                        color = EcColor.muted,
                    )
                }

                if (msg.hasCorrection) {
                    CorrectionBlock(msg = msg, isChild = isChild)
                }

                if (msg.unsafeFiltered) {
                    Text(
                        text = "（内容已按儿童安全规则替换）",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }

                // 播放 / 回放：失败也保留出口（点一下重试），不静默
                val playLabel = playLabelOf(msg, isChild)
                Text(
                    text = playLabel,
                    fontSize = EcFont.caption,
                    fontWeight = FontWeight.Medium,
                    color = if (msg.playState == ChatPlayState.FAILED) EcColor.badText else EcColor.primary,
                    modifier = Modifier
                        .clickable(onClick = onPlayTap)
                        .padding(vertical = 2.dp),
                )

                val pronLine = pronLineFor(msg, isChild)
                if (pronLine.isNotEmpty()) {
                    Text(
                        text = pronLine,
                        fontSize = EcFont.micro,
                        color = if (msg.isUser) EcColor.primary else EcColor.muted,
                    )
                }

                // 逐词小分：仅成人（儿童不落数字）
                if (!isChild && msg.wordTexts.isNotEmpty()) {
                    Text(
                        text = if (wordsExpanded) "收起逐词" else "看逐词（${msg.wordTexts.size} 个词）",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                        modifier = Modifier
                            .clickable(onClick = onWordsTap)
                            .padding(vertical = 2.dp),
                    )
                    if (wordsExpanded) {
                        WordScoreFlow(msg = msg)
                    }
                }
            }
        }
    }
}

/** 「更自然」提示：成人给完整校正；儿童只给一句温和替换。 */
@Composable
private fun CorrectionBlock(msg: ChatMessageUi, isChild: Boolean) {
    val bg = if (isChild) EcColor.goodBg else EcColor.warnBg
    val fg = if (isChild) EcColor.goodText else EcColor.warnText
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.sm))
            .background(bg)
            .padding(EcSpace.x2),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            text = (if (isChild) "可以这样说：" else "更自然：") + msg.better,
            fontSize = EcFont.caption,
            fontWeight = FontWeight.Medium,
            color = fg,
        )
        if (msg.explainZh.isNotEmpty()) {
            Text(
                text = msg.explainZh,
                fontSize = EcFont.micro,
                color = fg,
            )
        }
        if (isChild) {
            Text(
                text = "这样说会更棒哦，慢慢来 💪",
                fontSize = EcFont.micro,
                color = fg,
            )
        }
    }
}

/** 逐词分数（成人）：词 + 分数，颜色取分数语义色。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WordScoreFlow(msg: ChatMessageUi) {
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        msg.wordTexts.forEachIndexed { index, word ->
            val score = msg.wordScores.getOrNull(index)
            val color = EcScore.color(score, false)
            Text(
                text = word + " " + (score?.let { ChatFormat.scoreText(it) } ?: "—"),
                fontSize = EcFont.micro,
                color = color,
                modifier = Modifier
                    .clip(RoundedCornerShape(EcRadius.sm))
                    .background(EcColor.surfaceAlt)
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }
}

/** 播放按钮文案（对应 hos `ChatBubbleView.playLabel`；儿童文案更口语）。 */
private fun playLabelOf(msg: ChatMessageUi, isChild: Boolean): String {
    if (msg.role == "assistant") {
        return when (msg.playState) {
            ChatPlayState.LOADING -> "⏳ 语音生成中…（通常几秒）"
            ChatPlayState.PLAYING -> "🔊 正在说话…（点一下停）"
            ChatPlayState.FAILED -> if (isChild) "⚠️ 声音没出来，点这里再试试" else "⚠️ 语音没出来，点这里重试"
            ChatPlayState.NONE -> "🔊 再听一遍"
        }
    }
    return when (msg.playState) {
        ChatPlayState.LOADING -> "⏳ 正在取录音…"
        ChatPlayState.PLAYING -> "⏸ 正在回放…（点一下停）"
        ChatPlayState.FAILED -> if (isChild) "▶ 点这里再听一次" else "▶ 录音没取到，点这里重试"
        ChatPlayState.NONE -> "🔁 回放我刚才说的话"
    }
}

// ---------------------------------------------------------------------------
// 整段回放卡
// ---------------------------------------------------------------------------

/**
 * 整段对话回放（§2.8）：
 * - loading / building → 「正在生成整段回放…（可以先看文字）」，可重试（服务端 auto_retry=false 时只能用户点）；
 * - ready → 播放按钮 + 总时长；
 * - failed → 服务端 error + 「🔄 重新生成」。
 */
@Composable
fun ChatReplayCard(
    status: ChatReplayStatus,
    errorText: String,
    isChild: Boolean,
    playing: Boolean,
    durationText: String,
    onPlayTap: () -> Unit,
    onRegenerateTap: () -> Unit,
) {
    val shape = RoundedCornerShape(EcRadius.md)
    when (status) {
        ChatReplayStatus.IDLE -> Unit

        ChatReplayStatus.LOADING, ChatReplayStatus.BUILDING -> Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(EcColor.surfaceAlt)
                .padding(EcSpace.x3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                color = EcColor.primary,
                strokeWidth = 2.dp,
            )
            Text(
                text = "🎧 正在生成整段回放…（可以先看文字）",
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
        }

        ChatReplayStatus.READY -> Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(EcColor.surface)
                .border(1.dp, EcColor.border, shape)
                .padding(EcSpace.x3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = if (isChild) "🎧 听一听我们的对话" else "🎧 回放整段对话",
                    fontSize = EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                )
                Text(
                    text = if (durationText.isNotEmpty()) "总长约 $durationText" else "整段回放已经准备好啦",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            EcButton(
                label = if (playing) "⏸ 暂停" else "▶ 播放",
                onClick = onPlayTap,
                kind = EcButtonKind.SECONDARY,
            )
        }

        ChatReplayStatus.FAILED -> Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(EcColor.warnBg)
                .padding(EcSpace.x3),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = "🎧 整段回放还没好",
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
            Text(
                text = errorText,
                fontSize = EcFont.caption,
                color = EcColor.warnText,
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "🔄 重新生成",
                    onClick = onRegenerateTap,
                    kind = EcButtonKind.SECONDARY,
                )
                Text(
                    text = "可以先看文字记录",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }
    }
}

/** 供页面复用的浅色提示行（限额 / 降级 / 语音失败），避免重复铺 EcInlineNotice 参数。 */
@Composable
fun ChatWarnLine(text: String, icon: String = "⚠️") {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.warnBg)
            .padding(EcSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(text = icon, fontSize = EcFont.caption)
        Text(
            text = text,
            fontSize = EcFont.caption,
            color = EcColor.warnText,
            modifier = Modifier.weight(1f),
        )
    }
}

/** 供页面复用的「只读提示」行（assistant 色系，非警告）。 */
@Composable
fun ChatInfoLine(text: String, icon: String = "💡", color: Color = EcColor.primarySoft) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(color)
            .padding(EcSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(text = icon, fontSize = EcFont.caption)
        Text(
            text = text,
            fontSize = EcFont.caption,
            color = EcColor.primary,
            modifier = Modifier.weight(1f),
        )
    }
}
