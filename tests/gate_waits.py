"""R320 -- EVERY WAIT IS A WAIT ON A CONDITION, AND NOTHING TAPS OR MEASURES BEFORE ONE.

R283 swept the gates' fixed sleeps into condition waits (tests/lib/quiet.js). stackadd-gate
was written after that sweep and still tapped without waiting for the screen it tapped: it
passed alone and failed in the suite, where the machine is slower. A rule held only by
memory survives until the next file is written; this holds it by reading every gate.

Three findings, each by file and line:
  sleep    a Start-Sleep that is not inside a POLLING loop -- a loop whose body leaves on a
           condition (break / return / exit). A sleep that paces or "gives time" fails.
  input    input sent to the page (Input.dispatchTouchEvent / dispatchMouseEvent /
           dispatchKeyEvent / insertText) from code that has not waited on a condition first:
           the call must sit in a function whose body calls a Wait* before it.
  measure  a viewport or colour-scheme change (Emulation.setDeviceMetricsOverride /
           setEmulatedMedia) followed by a measurement -- a screenshot, or page code reading a
           size, position or computed style -- with no Wait* between the two.

The PowerShell is read with its strings and here-strings blanked first, so braces and words
inside page JavaScript never count as structure. A control is run first: a planted file with
one of each must give exactly three findings, so a scanner that silently matches nothing fails.

    python -I tests/gate_waits.py            exit 0 clean, 1 findings, 2 the control failed
"""
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
INPUT = re.compile(r"'Input\.(dispatchTouchEvent|dispatchMouseEvent|dispatchKeyEvent|insertText)'")
EMUL = re.compile(r"'Emulation\.(setDeviceMetricsOverride|setEmulatedMedia)'")
CONT = {'touchMove', 'touchEnd', 'touchCancel', 'mouseMoved', 'mouseReleased', 'keyUp', 'char'}
WAIT = re.compile(r"\bWait[A-Z]\w*\b|__htQuiet")
EVAL = re.compile(r"\b(Eval|EvalJ|EvalA|Shot)\b|captureScreenshot")
MEASURE = re.compile(r"getBoundingClientRect|scrollWidth|clientWidth|clientHeight|offsetWidth|offsetHeight|getComputedStyle|innerWidth|innerHeight|captureScreenshot|\bShot\b")


HERE_SPANS = []


def blank(src):
    """The source with every string and here-string replaced by spaces (newlines kept), and
    comments removed -- the same length, so offsets and line numbers still hold."""
    out = list(src)
    HERE_SPANS[:] = []
    i, n = 0, len(src)
    def wipe(a, b):
        for k in range(a, b):
            if out[k] != '\n': out[k] = ' '
    while i < n:
        c = src[i]
        if src.startswith("@'", i) or src.startswith('@"', i):
            q = src[i + 1]
            j = src.find('\n' + q + '@', i + 2)
            j = n if j < 0 else j + 3
            wipe(i, j); HERE_SPANS.append((i, j)); i = j; continue
        if c == '#':
            j = src.find('\n', i); j = n if j < 0 else j
            wipe(i, j); i = j; continue
        if c == "'":
            j = i + 1
            while j < n:
                if src[j] == "'" and j + 1 < n and src[j + 1] == "'": j += 2; continue
                if src[j] == "'": break
                j += 1
            wipe(i + 1, j); i = j + 1; continue
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == '`' else 1
            wipe(i + 1, j); i = j + 1; continue
        i += 1
    return ''.join(out)


def blocks(code):
    """Every { } block: (open, close, header) -- the header is the text before the brace on its
    statement, e.g. 'for ($i = 0; $i -lt 3; $i++)' or 'function TapAt(...)'."""
    st, out = [], []
    for i, c in enumerate(code):
        if c == '{': st.append(i)
        elif c == '}' and st:
            a = st.pop()
            h0 = code.rfind('\n', 0, a) + 1
            out.append((a, i, code[h0:a].strip()))
    return out


def line_of(src, off): return src.count('\n', 0, off) + 1


def scan(path, src):
    code = blank(src)
    bl = blocks(code)
    found = []
    # ---- sleep ----
    for m in re.finditer(r'\bStart-Sleep\b', code):
        enc = [b for b in bl if b[0] < m.start() < b[1]]
        # a block whose own header (the text on its line before the brace) ends in a loop's head
        loops = [b for b in enc if re.search(r'\b(for|foreach|while)\s*\([^{}]*\)\s*$|\bdo\s*$', b[2], re.I)]
        # it leaves on a condition: a break / return / exit in its body, or a condition in its
        # head beyond the counter (`$i -lt 40 -and $paused.Count -eq 0`)
        ok = any(re.search(r'\b(break|return|exit)\b', code[b[0]:b[1]]) or re.search(r'-(and|or)\b', b[2]) for b in loops)
        if not ok:
            found.append(('sleep', line_of(src, m.start()), 'a Start-Sleep outside a loop that leaves on a condition'))
    # ---- input ----
    # Walking back from each input, in its own scope (its function, or the script's top level):
    # a Wait* is what must come first. The gesture's own earlier events (a touchMove walks back
    # past its touchStart) and page reads (Eval*) are passed over; anything else -- another
    # gesture, a viewport change, the start of the scope -- comes too soon.
    funcs = [b for b in bl if re.search(r'\bfunction\b', b[2], re.I)]
    toks = []
    # a helper whose body is a wait (`function Settle { WaitQuiet 'after a step' }`) is a wait
    waits = set()
    for b in funcs:
        nm = re.search(r'\bfunction\s+(\w+)', b[2], re.I)
        body = code[b[0]:b[1]]
        if nm and WAIT.search(body) and not re.search(r'Invoke-CDP\s+\S*\s*@\{\s*type', src[b[0]:b[1]]) and 'Input.' not in src[b[0]:b[1]]:
            waits.add(nm.group(1))
    for m in WAIT.finditer(code): toks.append((m.start(), 'wait', None))
    if waits:
        for m in re.finditer(r'\b(' + '|'.join(map(re.escape, sorted(waits))) + r')\b', code):
            if not re.search(r'function\s+$', code[max(0, m.start() - 12):m.start()]):
                toks.append((m.start(), 'wait', None))
    for m in re.finditer(r'\b(Eval|EvalJ|EvalA)\b', code): toks.append((m.start(), 'eval', None))
    for m in EMUL.finditer(src):
        if not any(a <= m.start() < b for a, b in HERE_SPANS): toks.append((m.start(), 'emul', None))
    for m in INPUT.finditer(src):
        if any(a <= m.start() < b for a, b in HERE_SPANS): continue
        tm = re.match(r"[^\n]*?type\s*=\s*'(\w+)'", src[m.end():])
        t = tm.group(1) if tm else m.group(1)
        toks.append((m.start(), 'input', 'cont' if t in CONT else 'start'))
    toks.sort()
    def scope(off):
        enc = [b for b in funcs if b[0] < off < b[1]]
        return min(enc, key=lambda b: b[1] - b[0]) if enc else None
    for i, (off, kind, gk) in enumerate(toks):
        if kind != 'input': continue
        sc = scope(off)
        state, ok = gk, False
        for poff, pk, pgk in reversed(toks[:i]):
            if scope(poff) != sc: continue
            if pk == 'wait': ok = True; break
            if pk == 'eval': continue
            if pk == 'input' and state == 'cont': state = pgk; continue
            break
        if not ok:
            found.append(('input', line_of(src, off), 'input sent with no Wait* before it' + (' in ' + sc[2] if sc else ' (top level)')))
    # ---- measure after an emulation change ----
    heres = {}
    for hm in re.finditer(r"\$(\w+)\s*=\s*@'\r?\n(.*?)\r?\n'@", src, re.S):
        heres[hm.group(1).lower()] = hm.group(2)
    lines = src.split('\n')
    wait_line = re.compile(WAIT.pattern + (r'|\b(' + '|'.join(map(re.escape, sorted(waits))) + r')\b' if waits else ''))
    for idx, ln in enumerate(lines):
        if not EMUL.search(ln):
            continue
        # the rest of this line after the call, then the lines after it
        tail = [ln[EMUL.search(ln).end():]] + lines[idx + 1:]
        for k, t in enumerate(tail):
            if wait_line.search(t):
                break
            if EMUL.search(t) and k > 0:
                continue
            if EVAL.search(t):
                text = t
                for v in re.findall(r'\$(\w+)', t):
                    text += heres.get(v.lower(), '')
                j = idx + 1 + k
                # an EvalJ given a here-string on the following lines
                if re.search(r"@'\s*$", t):
                    end = next((q for q in range(j + 1, len(lines)) if lines[q].startswith("'@")), len(lines))
                    text += '\n'.join(lines[j:end])
                if MEASURE.search(text):
                    found.append(('measure', idx + 1, 'a measurement (line %d) after an emulation change with no Wait* between' % (j if k else idx + 1)))
                    break
    return found


CONTROL = """function Bad1 { Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart' } }
function Good1 { WaitQuiet 'x'; Invoke-CDP 'Input.dispatchTouchEvent' @{ type = 'touchStart' } }
Start-Sleep -Milliseconds 400
for ($i = 0; $i -lt 9; $i++) { Start-Sleep -Milliseconds 100; if ($ok) { break } }
$js = @'
{ Start-Sleep 'Input.dispatchTouchEvent' }
'@
Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 360 } | Out-Null
$w = Eval "document.documentElement.scrollWidth"
Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = 390 } | Out-Null
WaitQuiet 'resize'
$w = Eval "document.documentElement.scrollWidth"
"""


def main():
    ctl = sorted(k for k, _, _ in scan('control', CONTROL))
    if ctl != ['input', 'measure', 'sleep']:
        print('gate-waits: CONTROL FAILED -- a planted file with one finding of each kind gave %r' % ctl)
        print('GATE: FAIL'); return 2
    files = sorted(glob.glob(os.path.join(HERE, '*-gate.ps1')))
    total = 0
    for f in files:
        src = open(f, encoding='utf-8-sig').read().replace('\r\n', '\n')
        for kind, ln, why in scan(f, src):
            total += 1
            print('  %s:%d  %s -- %s' % (os.path.basename(f), ln, kind, why))
    if total:
        print('gate-waits: FAIL -- %d finding(s) in %d gate files (control: 3 of 3 found)' % (total, len(files)))
        print('GATE: FAIL'); return 1
    print('gate-waits: OK -- %d gate files: every sleep polls a condition, every input and every measurement after a viewport change follows a wait (control: 3 of 3 found)' % len(files))
    print('GATE: PASS'); return 0


if __name__ == '__main__':
    sys.exit(main())
