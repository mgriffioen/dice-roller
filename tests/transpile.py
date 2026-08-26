import re, pathlib, sys, os
pat = re.compile(r'^(\s*)([A-Za-z_][\w.\[\]]*)\s*([+\-*/])=\s*(.*)$')
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
for f in pathlib.Path(sys.argv[1]).rglob('*.lua'):
    lines = []
    for line in f.read_text().splitlines():
        m = pat.match(line)
        if m and not line.lstrip().startswith('--'):
            i, lhs, op, rest = m.groups()
            c = ''
            if ' --' in rest:
                rest, c = rest.split(' --', 1); c = ' --' + c
            line = f'{i}{lhs} = {lhs} {op} ({rest.strip()}){c}'
        line = re.sub(r'^\s*import\s+".*"\s*$', '', line)
        lines.append(line)
    (out / f.name).write_text('\n'.join(lines))
print("transpiled to", out)
