package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius

/** 状态标签色调（对应 hos `Chip.tone`；INFO 用主色浅底表达「提示/链接」）。 */
enum class PillTone { NEUTRAL, GOOD, WARN, BAD, INFO }

private fun toneBackground(tone: PillTone): Color = when (tone) {
    PillTone.NEUTRAL -> EcColor.surfaceAlt
    PillTone.GOOD -> EcColor.goodBg
    PillTone.WARN -> EcColor.warnBg
    PillTone.BAD -> EcColor.badBg
    PillTone.INFO -> EcColor.primarySoft
}

private fun toneForeground(tone: PillTone): Color = when (tone) {
    PillTone.NEUTRAL -> EcColor.muted
    PillTone.GOOD -> EcColor.goodText
    PillTone.WARN -> EcColor.warnText
    PillTone.BAD -> EcColor.badText
    PillTone.INFO -> EcColor.primary
}

private fun toneIcon(tone: PillTone): String = when (tone) {
    PillTone.NEUTRAL -> "·"
    PillTone.GOOD -> "✓"
    PillTone.WARN -> "!"
    PillTone.BAD -> "!"
    PillTone.INFO -> "ⓘ"
}

/**
 * 小标签（等级 / 音素 / 状态；移植 hos `Chip` 的显示形态）。
 * 只做展示，不可点击 —— 需要可选择时用 [EcChip]。
 */
@Composable
fun EcPill(text: String, tone: PillTone = PillTone.NEUTRAL) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(EcRadius.sm))
            .background(toneBackground(tone))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    ) {
        Text(
            text = text,
            fontSize = EcFont.micro,
            color = toneForeground(tone),
        )
    }
}

/**
 * 页内提示条（degraded / 提醒 / 说明；对应 hos 的浅色提示块）。
 * 语气色只用于「底色 + 小图标 + 文字」，不遮断主内容。
 */
@Composable
fun EcInlineNotice(text: String, tone: PillTone = PillTone.WARN) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(toneBackground(tone))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = toneIcon(tone),
            fontSize = EcFont.caption,
            fontWeight = FontWeight.Bold,
            color = toneForeground(tone),
        )
        Text(
            text = text,
            fontSize = EcFont.caption,
            color = toneForeground(tone),
            modifier = Modifier.weight(1f),
        )
    }
}

/** 可选中的胶囊标签（等级 A1/A2/B1/B2、音色筛选等）；点击区 ≥48dp。 */
@Composable
fun EcChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(EcRadius.pill)
    Box(
        modifier = Modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(if (selected) EcColor.primarySoft else EcColor.surface)
            .border(1.dp, if (selected) EcColor.primary else EcColor.border, shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            fontSize = EcFont.caption,
            fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
            color = if (selected) EcColor.primary else EcColor.muted,
        )
    }
}

/**
 * 单行/多行输入框（对应 hos 页面里的 TextInput/TextArea 统一样式）。
 * 样式全部取 token，页面不再写输入框外观。
 */
@Composable
fun EcTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    placeholder: String = "",
    password: Boolean = false,
    singleLine: Boolean = true,
    enabled: Boolean = true,
    keyboardType: KeyboardType = KeyboardType.Text,
    modifier: Modifier = Modifier,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        enabled = enabled,
        label = { Text(text = label, fontSize = EcFont.caption) },
        placeholder = {
            if (placeholder.isNotEmpty()) {
                Text(text = placeholder, fontSize = EcFont.body, color = EcColor.muted)
            }
        },
        singleLine = singleLine,
        visualTransformation = if (password) {
            PasswordVisualTransformation()
        } else {
            VisualTransformation.None
        },
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        shape = RoundedCornerShape(EcRadius.md),
        textStyle = TextStyle(fontSize = EcFont.body, color = EcColor.ink),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = EcColor.primary,
            unfocusedBorderColor = EcColor.border,
            disabledBorderColor = EcColor.border,
            cursorColor = EcColor.primary,
            focusedLabelColor = EcColor.primary,
            unfocusedLabelColor = EcColor.muted,
            focusedContainerColor = EcColor.surface,
            unfocusedContainerColor = EcColor.surface,
            disabledContainerColor = EcColor.surfaceAlt,
            focusedTextColor = EcColor.ink,
            unfocusedTextColor = EcColor.ink,
        ),
    )
}

/** 开关行：左标题/副标题，右 Switch；整行可点，点击区 ≥48dp。 */
@Composable
fun EcSwitchRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    subtitle: String? = null,
    enabled: Boolean = true,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(enabled = enabled) { onCheckedChange(!checked) }
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = title,
                fontSize = EcFont.body,
                color = if (enabled) EcColor.ink else EcColor.muted,
            )
            if (!subtitle.isNullOrEmpty()) {
                Text(text = subtitle, fontSize = EcFont.caption, color = EcColor.muted)
            }
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled)
    }
}

/**
 * 通用弹层（替代 hos 的 `CustomDialog`/AlertDialog 用法）。
 *
 * 内容由调用方用 `ColumnScope` 自由组合（说明文字、按钮等）；
 * 标题右侧自带「✕」，点遮罩也能关。
 */
@Composable
fun EcDialog(
    title: String,
    onDismiss: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    Dialog(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(EcRadius.xl))
                .background(EcColor.surface)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = title,
                    modifier = Modifier.weight(1f),
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.SemiBold,
                    color = EcColor.ink,
                )
                Text(
                    text = "✕",
                    fontSize = EcFont.h3,
                    color = EcColor.muted,
                    modifier = Modifier
                        .clickable(onClick = onDismiss)
                        .padding(4.dp),
                )
            }
            content()
        }
    }
}
