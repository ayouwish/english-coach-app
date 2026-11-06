package top.dreamsearch.englishcoach.ui.design

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight

/** 当前是否儿童模式：由 [EcTheme] 注入，组件（分数组件、WordText）据此隐藏 IPA/低分。 */
val LocalIsChild = staticCompositionLocalOf { false }

private val LightColors = lightColorScheme(
    primary = EcColor.primary,
    onPrimary = Color.White,
    primaryContainer = EcColor.primarySoft,
    onPrimaryContainer = EcColor.primaryPressed,
    secondary = EcColor.info,
    onSecondary = Color.White,
    background = EcColor.bg,
    onBackground = EcColor.ink,
    surface = EcColor.surface,
    onSurface = EcColor.ink,
    surfaceVariant = EcColor.surfaceAlt,
    onSurfaceVariant = EcColor.muted,
    outline = EcColor.border,
    outlineVariant = EcColor.border,
    error = EcColor.bad,
    onError = Color.White,
    errorContainer = EcColor.badBg,
    onErrorContainer = EcColor.badText,
)

private val EcTypography = Typography(
    displaySmall = TextStyle(fontSize = EcFont.display, fontWeight = FontWeight.Bold, color = EcColor.ink),
    headlineMedium = TextStyle(fontSize = EcFont.h1, fontWeight = FontWeight.Bold, color = EcColor.ink),
    headlineSmall = TextStyle(fontSize = EcFont.h2, fontWeight = FontWeight.SemiBold, color = EcColor.ink),
    titleLarge = TextStyle(fontSize = EcFont.h3, fontWeight = FontWeight.SemiBold, color = EcColor.ink),
    titleMedium = TextStyle(fontSize = EcFont.body, fontWeight = FontWeight.Medium, color = EcColor.ink),
    bodyLarge = TextStyle(fontSize = EcFont.body, color = EcColor.ink),
    bodyMedium = TextStyle(fontSize = EcFont.body, color = EcColor.ink),
    bodySmall = TextStyle(fontSize = EcFont.caption, color = EcColor.muted),
    labelSmall = TextStyle(fontSize = EcFont.micro, color = EcColor.muted),
)

/** 全局主题：浅色为主（docs/design-system.md §9：M1 不做深色模式）。 */
@Composable
fun EcTheme(isChild: Boolean = false, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalIsChild provides isChild) {
        MaterialTheme(
            colorScheme = LightColors,
            typography = EcTypography,
            content = content,
        )
    }
}
