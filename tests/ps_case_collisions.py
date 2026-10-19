#!/usr/bin/env python3
# R155/R242 -- POWERSHELL CASE COLLISIONS, measured and held.
#
# PowerShell variable names are CASE-INSENSITIVE: `$K` and `$k` are ONE variable.
# R155 measured 65 such pairs across 21 of 28 gate scripts, 12 of the fatal shape --
# a LOOP variable (foreach / for) sharing its name, in another case, with a variable
# assigned elsewhere in the same file. A loop like that overwrites the capture, and
# a numeric assertion against the destroyed value ($null, or [double]$null = 0) then
# passes VACUOUSLY: the gate stops measuring and says nothing.
#
# This prints every variable written in more than one case, per file, and FAILS on
# any that touch a loop variable. Same name in one case is fine; the defect is two
# spellings the author read as two variables.
#
#   python tests/ps_case_collisions.py tests/*.ps1      (called by check-ps-case.sh)
import re, sys, io, collections

AUTO = {'_', 'true', 'false', 'null', 'args', 'input', 'psscriptroot', 'pscommandpath', 'error', 'matches',
        'lastexitcode', 'pid', 'host', 'home', 'pwd', 'this', 'psitem', 'myinvocation', 'erroractionpreference',
        'progresspreference', 'verbosepreference', 'executioncontext', 'foreach', 'switch', 'ofs', 'shellid'}
VAR = re.compile(r'\$(?:script:|global:|local:|private:)?([A-Za-z_][A-Za-z0-9_]*)')
LOOP = re.compile(r'\b(?:foreach|for)\s*\(\s*\$([A-Za-z_][A-Za-z0-9_]*)', re.I)

def strip_strings_and_comments(src):
    # Drop single-quoted here-strings (JS blocks), single-quoted strings and comments:
    # a JS `$` inside @' '@ is not a PowerShell variable.
    src = re.sub(r"@'.*?'@", ' ', src, flags=re.S)
    src = re.sub(r"<#.*?#>", ' ', src, flags=re.S)
    out = []
    for line in src.split('\n'):
        line = re.sub(r"'(?:[^']|'')*'", "''", line)
        i = line.find('#')
        if i >= 0 and '"' not in line[:i]: line = line[:i]
        out.append(line)
    return '\n'.join(out)

def scan(path):
    src = strip_strings_and_comments(io.open(path, encoding='utf-8', errors='replace').read())
    spell = collections.defaultdict(set)
    for m in VAR.finditer(src):
        n = m.group(1)
        if n.lower() in AUTO or n.lower().startswith('env'): continue
        spell[n.lower()].add(n)
    loops = {m.group(1).lower() for m in LOOP.finditer(src)}
    out = []
    for k, names in sorted(spell.items()):
        if len(names) > 1:
            out.append((k, sorted(names), k in loops))
    return out

fatal = 0; total = 0; files = 0
for path in sys.argv[1:]:
    hits = scan(path)
    if not hits: continue
    files += 1
    for k, names, loop in hits:
        total += 1
        if loop: fatal += 1
        print('  %s: %s%s' % (path, ' / '.join(names), '   <-- a LOOP variable' if loop else ''))
print('ps-case: %d name(s) written in more than one case, in %d file(s); %d touch a loop variable' % (total, files, fatal))
print('GATE: ' + ('PASS' if total == 0 else 'FAIL'))
sys.exit(0 if total == 0 else 1)
