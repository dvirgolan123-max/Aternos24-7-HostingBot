#!/usr/bin/env python3
"""Type-checks Metal shader sources with clang using metal_shim.h (approximate MSL emulation)."""
import re, subprocess, sys, os, tempfile
here = os.path.dirname(os.path.abspath(__file__))
src_files = sys.argv[1:]
ok = True
for path in src_files:
    s = open(path).read()
    s = s.replace('#include <metal_stdlib>', '#include "metal_shim.h"')
    # Float literals -> float (MSL has no double).
    s = re.sub(r'(?<![\w.])(\d+\.\d*|\.\d+)(?![\w.])', r'\1f', s)
    # Vector / matrix constructors -> helper functions.
    s = re.sub(r'\b(float[234]|float3x3|float4x4)\(', lambda m: 'make_' + m.group(1) + '(', s)
    with tempfile.NamedTemporaryFile('w', suffix='.cpp', delete=False, dir=here) as f:
        f.write(s)
        tmp = f.name
    r = subprocess.run(['clang++', '-std=c++17', '-fsyntax-only', '-Wno-unknown-attributes', '-Wno-unused-value',
                        '-Wno-unused-variable', '-I', here, tmp], capture_output=True, text=True)
    os.unlink(tmp)
    out = (r.stdout + r.stderr).replace(tmp, path)
    if r.returncode != 0:
        ok = False
        print(out)
    else:
        if out.strip():
            print(out)
        print(f"MSL check passed: {path}")
sys.exit(0 if ok else 1)
