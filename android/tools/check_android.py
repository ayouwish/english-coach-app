#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Android 工程静态一致性检查（本机没有 Android SDK，无法编译，用这个兜底）。

检查项：
1. 每个 .kt 的 `package` 与目录路径一致；
2. `import top.dreamsearch...` 指向的声明存在（类/对象/接口/顶层函数/顶层 val）；
3. 花括号/圆括号是否配平（跳过字符串与注释）；
4. 是否残留 TODO/FIXME/空实现标记；
5. CONTRACT §5 要求的页面 composable 是否存在且签名含约定回调参数；
6. build.gradle.kts / settings / manifest 必须存在。

用法：python android/tools/check_android.py
退出码：0 全部通过（可能有警告），1 有错误。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # .../android
SRC = ROOT / "app" / "src" / "main" / "java"
BASE_PKG = "top.dreamsearch.englishcoach"

errors: list[str] = []
warnings: list[str] = []


def rel(p: Path) -> str:
    try:
        return str(p.relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(p)


# ---------------------------------------------------------------- 收集声明
DECL_RE = re.compile(
    r"^\s*(?:(?:public|internal|private|protected|open|abstract|sealed|data|enum|annotation|value|inline|suspend|operator|infix|tailrec|external|actual|expect)\s+)*"
    r"(class|interface|object|fun|val|var|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
PKG_RE = re.compile(r"^\s*package\s+([\w.]+)", re.MULTILINE)


def strip_noise(src: str) -> str:
    """去掉注释、字符串、字符字面量，便于做括号配平与声明扫描。"""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and nxt == "*":
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if src.startswith('"""', i):
            j = src.find('"""', i + 3)
            i = n if j < 0 else j + 3
            continue
        if c == '"':
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if c == "'":
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == "'":
                    i += 1
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


declarations: dict[str, set[str]] = {}   # package -> {name}
for path in SRC.rglob("*.kt"):
    raw = path.read_text(encoding="utf-8", errors="replace")
    clean = strip_noise(raw)
    m = PKG_RE.search(clean)
    if not m:
        errors.append(f"{rel(path)}: 缺少 package 声明")
        continue
    pkg = m.group(1)
    expect_dir = SRC / Path(*pkg.split("."))
    if path.parent != expect_dir:
        errors.append(f"{rel(path)}: package={pkg} 与目录不符（应在 {expect_dir.relative_to(ROOT)}）")
    names = declarations.setdefault(pkg, set())
    for kind, name in DECL_RE.findall(clean):
        names.add(name)
    # 括号配平
    for open_ch, close_ch, label in (("{", "}", "花括号"), ("(", ")", "圆括号"), ("[", "]", "方括号")):
        if clean.count(open_ch) != clean.count(close_ch):
            errors.append(
                f"{rel(path)}: {label}不配平（{clean.count(open_ch)} vs {clean.count(close_ch)}）"
            )
    # 残留标记
    for marker in ("TODO(", "FIXME(", "NotImplementedError"):
        if marker in raw:
            warnings.append(f"{rel(path)}: 含 {marker}")

# ---------------------------------------------------------------- 检查 import
IMPORT_RE = re.compile(r"^import\s+([\w.]+)(?:\.\*)?\s*$", re.MULTILINE)
for path in SRC.rglob("*.kt"):
    raw = path.read_text(encoding="utf-8", errors="replace")
    clean = strip_noise(raw)
    for imp in IMPORT_RE.findall(clean):
        if not imp.startswith(BASE_PKG + "."):
            continue
        target_pkg, _, name = imp.rpartition(".")
        if not target_pkg:
            continue
        if target_pkg not in declarations:
            errors.append(f"{rel(path)}: import {imp} —— 包不存在")
            continue
        # 顶层声明存在？
        if name in declarations[target_pkg]:
            continue
        # 可能是 import object 的成员（如 EcColor.primary 不会出现在 import）
        # 或者是嵌套类/枚举值：查同包文件中是否出现该标识符声明
        if name not in declarations[target_pkg]:
            hint = f"{rel(path)}: import {imp} —— {target_pkg} 下未找到声明 {name}"
            if any(name in open(p, encoding="utf-8", errors="replace").read()
                   for p in SRC.rglob("*.kt")):
                warnings.append(hint + "（符号在工程其它位置出现，可能是嵌套类型/成员）")
            else:
                errors.append(hint)

# ---------------------------------------------------------------- 检查必需文件
required = [
    "settings.gradle.kts",
    "build.gradle.kts",
    "gradle.properties",
    "gradle/libs.versions.toml",
    "app/build.gradle.kts",
    "app/src/main/AndroidManifest.xml",
    "CONTRACT.md",
]
for r in required:
    if not (ROOT / r).exists():
        errors.append(f"缺少必需文件：{r}")

# ---------------------------------------------------------------- 检查页面契约（CONTRACT §5）
PAGE_REQUIREMENTS = {
    "ui/page/practice/PracticeScreen.kt": [("fun PracticeTab(", [])],
    "ui/page/flow/FlowScreen.kt": [("fun FlowTab(", [])],
    "ui/page/chat/ChatScenariosScreen.kt": [("fun ChatScenariosTab(", [])],
    "ui/page/story/StoryHomeScreen.kt": [("fun StoryHomeTab(", [])],
    "ui/page/account/MeScreen.kt": [("fun MeTab(", ["onNavigate"])],
    "ui/page/auth/LoginScreen.kt": [("fun LoginScreen(", [])],
    "ui/page/practice/SentenceListScreen.kt": [("fun SentenceListScreen(", ["onBack"])],
    "ui/page/flow/FlowSummaryScreen.kt": [("fun FlowSummaryScreen(", ["onBack", "onOpenFlowTab"])],
    "ui/page/chat/ChatSessionScreen.kt": [("fun ChatSessionScreen(", ["onBack"])],
    "ui/page/chat/ChatHistoryScreen.kt": [("fun ChatHistoryScreen(", ["onBack", "onOpenDetail"])],
    "ui/page/chat/ChatDetailScreen.kt": [("fun ChatDetailScreen(", ["onBack"])],
    "ui/page/chat/ChatCustomScreen.kt": [("fun ChatCustomScreen(", ["onBack"])],
    "ui/page/story/StoryRecordScreen.kt": [("fun StoryRecordScreen(", ["onBack", "onOpenFlow"])],
    "ui/page/story/StoryDetailScreen.kt": [("fun StoryDetailScreen(", ["onBack", "onOpenFlow", "onOpenReview"])],
    "ui/page/story/StoryReviewScreen.kt": [("fun StoryReviewScreen(", ["onBack"])],
    "ui/page/stats/DiagnosisScreen.kt": [("fun DiagnosisScreen(", ["onBack", "onPracticeFocus"])],
    "ui/page/stats/ReviewScreen.kt": [("fun ReviewScreen(", ["onBack"])],
    "ui/page/stats/BlindTestScreen.kt": [("fun BlindTestScreen(", ["onBack"])],
    "ui/page/account/ParentScreen.kt": [("fun ParentScreen(", ["onBack", "onOpenFamily", "onOpenSuggestions"])],
    "ui/page/account/FamilyScreen.kt": [("fun FamilyScreen(", ["onBack"])],
    "ui/page/account/SuggestionsScreen.kt": [("fun SuggestionsScreen(", ["onBack"])],
    "ui/page/account/AvatarScreen.kt": [("fun AvatarScreen(", ["onBack"])],
    "ui/page/account/VoicesScreen.kt": [("fun VoicesScreen(", ["onBack"])],
    "ui/page/account/HealthScreen.kt": [("fun HealthScreen(", ["onBack"])],
    "ui/page/account/SettingsScreen.kt": [
        ("fun SettingsScreen(", ["onBack", "onOpenAvatar", "onOpenVoices", "onOpenHealth", "onOpenSuggestions", "onLogout"])
    ],
}
for relpath, requirements in PAGE_REQUIREMENTS.items():
    f = SRC / BASE_PKG.replace(".", "/") / relpath
    if not f.exists():
        errors.append(f"缺少页面文件：{relpath}（CONTRACT §5）")
        continue
    text = f.read_text(encoding="utf-8", errors="replace")
    for signature, params in requirements:
        idx = text.find(signature)
        if idx < 0:
            errors.append(f"{relpath}: 未找到 {signature}）")
            continue
        if params:
            head = text[idx: idx + 900]
            for p in params:
                if p not in head:
                    errors.append(f"{relpath}: {signature}) 签名缺少参数 {p}")

# ---------------------------------------------------------------- 汇总
print(f"Kotlin 文件：{len(list(SRC.rglob('*.kt')))} 个")
for w in warnings[:40]:
    print(f"[warn] {w}")
if warnings:
    print(f"警告 {len(warnings)} 条")
if errors:
    print()
    for e in errors[:80]:
        print(f"[ERROR] {e}")
    print(f"\n共 {len(errors)} 个错误")
    sys.exit(1)
print("静态检查通过 ✅")
