#!/usr/bin/env python3
"""Copies the app sources for the Linux typecheck, rewriting Objective-C-only
syntax (@objc, #selector) that has no meaning without the ObjC runtime."""
import os, re, sys, shutil

src, dst = sys.argv[1], sys.argv[2]
shutil.rmtree(dst, ignore_errors=True)
os.makedirs(dst)

def rewrite_selectors(text):
    out, i = [], 0
    while True:
        j = text.find("#selector(", i)
        if j < 0:
            out.append(text[i:])
            return "".join(out)
        out.append(text[i:j])
        k, depth = j + len("#selector("), 1
        while depth:
            depth += {"(": 1, ")": -1}.get(text[k], 0)
            k += 1
        out.append("StubSelector()")
        i = k

count = 0
for root, _, files in os.walk(src):
    for f in files:
        if not f.endswith(".swift"):
            continue
        text = open(os.path.join(root, f)).read()
        text = re.sub(r"@objc(\([^)]*\))?\s+", "", text)
        text = rewrite_selectors(text)
        open(os.path.join(dst, f), "w").write(text)
        count += 1
print(f"prepared {count} files")
