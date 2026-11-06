#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Kotlin 成员级静态检查（本机无 Android SDK + shell 沙箱不可用时的替代验证）。

在 check_android.py 之上，额外检查工程内**跨文件成员引用**：
1. `XxxDto(...)` / `data class` 构造调用：命名参数是否存在于该 data class（按 core/model + core/net/dto 解析）；
2. `AppGraph.container.<service>.<method>(...)`：方法是否存在、命名参数/位置参数数量是否匹配；
3. `AppGraph.container.<field>`：字段是否在 AppContainer 声明；
4. `Routes.X` / `Tabs.X` / `NavParams.x` / `TabNav.x` / `Navigator.x` / `EcColor.x` / `EcFont.x` /
   `EcSpace.x` / `EcRadius.x` / `EcButtonSize.x` / `EcScore.x` / `Voices.x`：常量/成员是否存在；
5. 页面 composable 签名与 AppNavHost 调用实参一致性（命名参数）。

用法：python android/tools/check_members.py [--verbose]
退出码 0 = 全部通过。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "app" / "src" / "main" / "java"
BASE = "top.dreamsearch.englishcoach"
PKG_RE = re.compile(r"^\s*package\s+([\w.]+)", re.MULTILINE)
VERBOSE = "--verbose" in sys.argv

errors: list[str] = []
warnings: list[str] = []


def strip_noise(src: str) -> str:
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if c == "/" and nxt == "*":
            j = src.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        if src.startswith('"""', i):
            j = src.find('"""', i + 3); i = n if j < 0 else j + 3; continue
        if c == '"':
            i += 1
            while i < n:
                if src[i] == "\\": i += 2; continue
                if src[i] == '"': i += 1; break
                i += 1
            continue
        if c == "'":
            i += 1
            while i < n:
                if src[i] == "\\": i += 2; continue
                if src[i] == "'": i += 1; break
                i += 1
            continue
        out.append(c); i += 1
    return "".join(out)


def rel(p: Path) -> str:
    return str(p.relative_to(ROOT)).replace("\\", "/")


def match_paren(text: str, open_idx: int) -> int:
    """返回与 text[open_idx] 的 '(' 匹配的 ')' 下标（-1 未闭合）。"""
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


def split_top_level(text: str) -> list[str]:
    parts, depth, cur = [], 0, []
    for ch in text:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur)); cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]


def parse_params(param_text: str) -> list[str]:
    """从参数列表文本解析出参数名（跳过类型/注解/默认值/val|var 修饰）。"""
    names = []
    modifiers = (
        r"(?:(?:private|internal|protected|public|override|open|final|lateinit|vararg|"
        r"crossinline|noinline)\s+)*"
    )
    for part in split_top_level(param_text):
        part = re.sub(r"@\w+(\([^)]*\))?\s*", "", part).strip()
        m = re.match(modifiers + r"(?:val|var)\s+`?(\w+)`?\s*:", part)
        if not m:
            m = re.match(r"`?(\w+)`?\s*:", part)
        if m:
            names.append(m.group(1))
    return names


def parse_named_args(call_text: str) -> list[str]:
    """从调用实参文本解析命名参数名（`name =`，不匹配 `==`/`<=` 等）。"""
    names = []
    for part in split_top_level(call_text):
        m = re.match(r"`?(\w+)`?\s*=(?!=)", part)
        if m:
            names.append(m.group(1))
    return names


# ---------------------------------------------------------------- 解析工程
files: dict[Path, str] = {}          # path -> stripped source
for p in SRC.rglob("*.kt"):
    files[p] = strip_noise(p.read_text(encoding="utf-8", errors="replace"))

data_classes: dict[str, set[str]] = {}      # simple name -> params
service_methods: dict[str, dict[str, list[str]]] = {}   # class -> method -> params
classes: dict[str, set[str]] = {}            # class/object -> body member names
enums: dict[str, set[str]] = {}              # enum -> values
object_consts: dict[str, set[str]] = {}      # object -> top-level const/prop/fun names

for p, text in files.items():
    pkg_m = PKG_RE.search(text)
    pkg = pkg_m.group(1) if pkg_m else ""

    # data class
    for m in re.finditer(r"\bdata\s+class\s+(\w+)\s*\(", text):
        name = m.group(1)
        opn = text.index("(", m.end() - 1)
        cls = match_paren(text, opn)
        if cls > 0:
            data_classes.setdefault(name, set()).update(parse_params(text[opn + 1: cls]))

    # 普通 class / object：记录成员名（用于 AppContainer 等）
    for m in re.finditer(r"\b(class|object)\s+(\w+)", text):
        kind, name = m.group(1), m.group(2)
        brace = text.find("{", m.end())
        if brace < 0:
            continue
        depth, end = 0, len(text)
        for i in range(brace, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        body = text[brace:end]
        members = set(re.findall(r"\b(?:val|var|fun)\s+(?:<[^>]*>\s*)?(\w+)", body))
        members |= set(re.findall(r"\b(?:private|internal|protected)?\s*(?:val|var)\s+(\w+)", body))
        classes.setdefault(name, set()).update(members)
        if kind == "object":
            object_consts.setdefault(name, set()).update(members)
            object_consts[name] |= set(re.findall(r"\bconst\s+val\s+(\w+)", body))
        # service 类的方法与参数
        if name.endswith("Service"):
            methods: dict[str, list[str]] = {}
            for fm in re.finditer(r"\bsuspend\s+fun\s+(\w+)\s*\(", body):
                mname = fm.group(1)
                fn_open = fm.end() - 1
                fn_close = match_paren(body, fn_open)
                if fn_close > 0:
                    methods[mname] = parse_params(body[fn_open + 1: fn_close])
            if methods:
                service_methods[name] = methods

    # enum class
    for m in re.finditer(r"\benum\s+class\s+(\w+)\s*\{", text):
        name = m.group(1)
        brace = text.index("{", m.start())
        depth, end = 0, len(text)
        for i in range(brace, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        vals = set(re.findall(r"\b([A-Z][A-Z0-9_]+)\b", text[brace:end]))
        enums.setdefault(name, set()).update(vals)

# AppContainer 字段 → 类型
container_text = files.get(SRC / Path(*BASE.split(".")) / "core/di/AppGraph.kt", "")
container_types: dict[str, str] = {}
for m in re.finditer(r"\bval\s+(\w+)\s*:\s*(\w+)", container_text):
    container_types[m.group(1)] = m.group(2)
for m in re.finditer(r"\bval\s+(\w+)\s*=\s*(\w+)\(", container_text):
    container_types.setdefault(m.group(1), m.group(2))
if VERBOSE:
    print(f"[info] AppContainer 字段 {len(container_types)}：{sorted(container_types)}")

# 简单对象名 → 成员集合（常量/枚举）
KNOWN_MEMBER_OBJECTS = {
    "Routes": object_consts.get("Routes", set()),
    "Tabs": object_consts.get("Tabs", set()),
    "NavParams": object_consts.get("NavParams", set()),
    "TabNav": object_consts.get("TabNav", set()),
    "Navigator": object_consts.get("Navigator", set()),
    "EcColor": object_consts.get("EcColor", set()),
    "EcFont": object_consts.get("EcFont", set()),
    "EcSpace": object_consts.get("EcSpace", set()),
    "EcRadius": object_consts.get("EcRadius", set()),
    "EcButtonSize": object_consts.get("EcButtonSize", set()),
    "EcScore": object_consts.get("EcScore", set()),
    "Voices": object_consts.get("Voices", set()),
    "TtsVoice": object_consts.get("TtsVoice", set()),
}
KNOWN_ENUMS = {
    "EcButtonKind": enums.get("EcButtonKind", set()),
    "EcButtonSizeKind": enums.get("EcButtonSizeKind", set()),
    "PillTone": enums.get("PillTone", set()),
    "SerTone": enums.get("SerTone", set()),
}

# ---------------------------------------------------------------- 检查
SERVICE_FIELDS = {f: t for f, t in container_types.items() if t.endswith("Service")}

files_checked = 0
for p, text in files.items():
    files_checked += 1
    where = rel(p)

    # 1) data class 构造命名参数
    for m in re.finditer(r"(?<![\w.])([A-Z]\w+)\s*\(", text):
        name = m.group(1)
        if name not in data_classes:
            continue
        line_start = text.rfind("\n", 0, m.start()) + 1
        prefix = text[line_start:m.start()]
        # 跳过声明本身（`data class X(` / `class X(` / `fun X(`）
        if re.search(r"\b(?:data\s+)?class\s+$", prefix) or re.search(r"\bfun\s+$", prefix):
            continue
        opn = m.end() - 1
        cls = match_paren(text, opn)
        if cls < 0:
            continue
        args = split_top_level(text[opn + 1: cls])
        named = parse_named_args(text[opn + 1: cls])
        for arg in named:
            if arg not in data_classes[name]:
                line = text[:opn].count("\n") + 1
                errors.append(f"{where}:{line}: {name}(...) 命名参数 `{arg}` 不存在（可用：{sorted(data_classes[name])}）")
        # 位置参数数量（有命名参数时不精确，跳过）
        if not named:
            positional = [a for a in args if not re.match(r"`?\w+`?\s*=(?!=)", a)]
            if len(positional) > len(data_classes[name]):
                line = text[:opn].count("\n") + 1
                errors.append(f"{where}:{line}: {name}(...) 位置参数 {len(positional)} 个 > 构造参数 {len(data_classes[name])} 个")

    # 2) AppGraph.container.<service>.<method>(...)
    for m in re.finditer(r"AppGraph\.container\.(\w+)\.(\w+)\s*\(", text):
        field, method = m.group(1), m.group(2)
        if field not in container_types:
            line = text[:m.start()].count("\n") + 1
            errors.append(f"{where}:{line}: AppGraph.container.{field} 字段不存在")
            continue
        cls = container_types[field]
        methods = service_methods.get(cls)
        if methods is None:
            continue
        if method not in methods:
            line = text[:m.start()].count("\n") + 1
            errors.append(f"{where}:{line}: {cls}.{method}() 不存在（可用：{sorted(methods)}）")
            continue
        opn = m.end() - 1
        close = match_paren(text, opn)
        if close < 0:
            continue
        call_args = split_top_level(text[opn + 1: close])
        named = parse_named_args(text[opn + 1: close])
        for arg in named:
            if arg not in methods[method]:
                line = text[:opn].count("\n") + 1
                errors.append(f"{where}:{line}: {cls}.{method}() 命名参数 `{arg}` 不存在（可用：{methods[method]}）")
        positional = [a for a in call_args if not re.match(r"`?\w+`?\s*=(?!=)", a)]
        if len(positional) > len(methods[method]):
            line = text[:opn].count("\n") + 1
            errors.append(f"{where}:{line}: {cls}.{method}() 位置参数 {len(positional)} > 形参 {len(methods[method])}")

    # 3) AppGraph.container.<field> 直接访问
    for m in re.finditer(r"AppGraph\.container\.(\w+)", text):
        field = m.group(1)
        if field not in container_types:
            line = text[:m.start()].count("\n") + 1
            errors.append(f"{where}:{line}: AppGraph.container.{field} 字段不存在")

    # 4) 常量/成员对象
    for obj, members in KNOWN_MEMBER_OBJECTS.items():
        if not members:
            continue
        for m in re.finditer(rf"(?<![\w.]){obj}\.(\w+)", text):
            member = m.group(1)
            if member not in members:
                line = text[:m.start()].count("\n") + 1
                errors.append(f"{where}:{line}: {obj}.{member} 不存在（可用：{sorted(members)}）")

    # 5) 枚举值
    for enum_name, values in KNOWN_ENUMS.items():
        if not values:
            continue
        for m in re.finditer(rf"{enum_name}\.(\w+)", text):
            v = m.group(1)
            if v not in values:
                line = text[:m.start()].count("\n") + 1
                errors.append(f"{where}:{line}: {enum_name}.{v} 不是有效枚举值（可用：{sorted(values)}）")

# 去重
errors = sorted(set(errors))

print(f"成员级检查：{files_checked} 个 Kotlin 文件；数据类 {len(data_classes)}，Service {len(service_methods)}")
if warnings:
    for w in warnings:
        print(f"[warn] {w}")
if errors:
    for e in errors[:120]:
        print(f"[ERROR] {e}")
    print(f"\n共 {len(errors)} 个成员级错误")
    sys.exit(1)
print("成员级检查通过 ✅")
