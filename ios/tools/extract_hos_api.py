# -*- coding: utf-8 -*-
"""Extract a compact API/DTO digest from the HOS (ArkTS) sources."""
import io, os, re, sys, json

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'hos', 'entry', 'src', 'main', 'ets')
ROOT = os.path.abspath(ROOT)

OUT = os.path.join(os.path.dirname(__file__), 'hos-api-digest.md')

def read(p):
    with io.open(p, 'r', encoding='utf-8-sig') as f:
        return f.read()

def strip_comments(text):
    # remove block comments and line comments (good enough for signatures)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return text

def extract_decls(path):
    src = strip_comments(read(path))
    out = []
    # interfaces
    for m in re.finditer(r'export\s+interface\s+(\w+)\s*\{', src):
        name = m.group(1)
        start = m.end() - 1
        depth = 0
        i = start
        while i < len(src):
            if src[i] == '{':
                depth += 1
            elif src[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = src[start + 1:i]
        fields = []
        for line in body.split('\n'):
            line = line.strip().rstrip(';').strip()
            if not line:
                continue
            mm = re.match(r'^(\w+)(\?)?\s*:\s*(.+)$', line)
            if mm:
                fields.append('%s%s: %s' % (mm.group(1), mm.group(2) or '', mm.group(3).strip()))
        out.append(('interface', name, fields))
    # classes with static methods
    for m in re.finditer(r'export\s+class\s+(\w+)', src):
        name = m.group(1)
        s = m.start()
        # find the class body
        brace = src.find('{', m.end())
        depth = 0
        i = brace
        while i < len(src):
            if src[i] == '{':
                depth += 1
            elif src[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = src[brace + 1:i]
        methods = re.findall(r'static\s+(?:async\s+)?(\w+)\s*\(([^)]*)\)\s*:\s*([^\n{]+)', body)
        consts = re.findall(r'static\s+readonly\s+(\w+)\s*:\s*([^=]+)=', body)
        out.append(('class', name, ['static %s(%s) -> %s' % (a, re.sub(r'\s+', ' ', b).strip(), c.strip()) for a, b, c in methods]
                    + ['const %s: %s' % (a, b.strip()) for a, b in consts]))
    # enums / const objects
    for m in re.finditer(r'export\s+enum\s+(\w+)\s*\{([^}]*)\}', src):
        vals = [v.strip() for v in m.group(2).split(',') if v.strip()]
        out.append(('enum', m.group(1), vals))
    return out

def main():
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        for fn in sorted(filenames):
            if fn.endswith('.ets') and not fn.endswith('.test.ets'):
                files.append(os.path.join(dirpath, fn))
    lines = []
    for p in files:
        rel = os.path.relpath(p, ROOT).replace('\\', '/')
        try:
            decls = extract_decls(p)
        except Exception as e:
            lines.append('## %s\nERROR %s\n' % (rel, e))
            continue
        if not decls:
            continue
        lines.append('## %s' % rel)
        for kind, name, items in decls:
            lines.append('- **%s %s**' % (kind, name))
            for it in items:
                lines.append('  - %s' % it)
        lines.append('')
    sys.stdout.write('\n'.join(lines))
    sys.stderr.write('\n[%d lines]\n' % len(lines))

if __name__ == '__main__':
    main()
