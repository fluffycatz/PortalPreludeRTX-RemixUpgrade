"""Maintainer test helper. Never writes into the real game folder.

  make-stock --live <game dir> --out <dir> --steam-json <steam_stock.json>
        Builds a small stand-in for a fresh Steam install (the game markers + the whole bin\\ folder) from the
        working install: the upgrade's files are left out and the stock 0.2.1 files are put back from the
        *.prelude-0.2.1.bak copies. Every bin\\ file is then checked against Steam's SHA-1 list.
  compare <dirA> <dirB> [--sub bin]
        Compares two folders file by file (relative path + SHA-256). Exit 0 only if identical.
  tree-hash <dir>
        Prints one SHA-256 over the whole folder (paths + contents), to prove "nothing changed".
"""
import argparse
import hashlib
import json
import os
import shutil
import sys

BAK = ".prelude-0.2.1.bak"
PATCH_ROOT_FILES = {"d3d9.dll", "nvremixlauncher32.exe", "license.txt", "thirdpartylicenses-bridge.txt",
                    "thirdpartylicenses-dxvk.txt"}
MARKERS = ["hl2.exe", "dxvk.conf", "rtx.conf", "steam_appid.txt", "portal prelude rtx\\gameinfo.txt",
           "rtx-remix\\mods\\prelude_remix\\mod.usda"]


def digest(p, algo="sha256"):
    h = hashlib.new(algo)
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(8 << 20), b""):
            h.update(b)
    return h.hexdigest().upper()


def walk(base):
    out = {}
    for root, _, files in os.walk(base):
        for n in files:
            p = os.path.join(root, n)
            out[os.path.relpath(p, base).lower()] = p
    return out


def make_stock(live, out, steam_json):
    if os.path.exists(out):
        sys.exit(f"refusing: {out} already exists")
    for m in MARKERS:
        os.makedirs(os.path.dirname(os.path.join(out, m)) or out, exist_ok=True)
        shutil.copy2(os.path.join(live, m), os.path.join(out, m))
    lb, ob = os.path.join(live, "bin"), os.path.join(out, "bin")
    os.makedirs(ob)
    for n in os.listdir(lb):
        p = os.path.join(lb, n)
        if os.path.isdir(p) or n.lower() in PATCH_ROOT_FILES or n.lower().endswith(BAK):
            continue
        shutil.copy2(p, os.path.join(ob, n))
    shutil.copy2(os.path.join(lb, "d3d9.dll" + BAK), os.path.join(ob, "d3d9.dll"))
    shutil.copy2(os.path.join(lb, "NvRemixBridge32.dll" + BAK), os.path.join(ob, "NvRemixBridge32.dll"))
    shutil.copytree(os.path.join(lb, ".trex" + BAK), os.path.join(ob, ".trex"))
    # prove it is the stock Steam bin\ folder
    steam = {f["path"].lower(): f for f in json.load(open(steam_json, encoding="utf-8"))["files"] if not f["flags"] & 64}
    have = walk(ob)
    bad, extra = [], []
    for rel, p in have.items():
        s = steam.get("bin\\" + rel)
        if s is None:
            extra.append(rel)
        elif digest(p, "sha1") != s["sha1"].upper():
            bad.append(rel)
    missing = [k for k in steam if k.startswith("bin\\") and k[4:] not in have]
    print(f"stock stand-in: {len(have)} files in bin\\; differ from Steam: {bad}; missing: {missing}; not in Steam (logs): {extra}")
    if bad or missing:
        sys.exit(1)


def compare(a, b, sub):
    A, B = walk(os.path.join(a, sub)), walk(os.path.join(b, sub))
    only_a = sorted(set(A) - set(B))
    only_b = sorted(set(B) - set(A))
    diff = sorted(k for k in set(A) & set(B) if digest(A[k]) != digest(B[k]))
    print(f"compare {sub or '.'}: {len(A)} vs {len(B)} files; only in A {len(only_a)}, only in B {len(only_b)}, different {len(diff)}")
    for k in only_a[:20]:
        print("   only A:", k)
    for k in only_b[:20]:
        print("   only B:", k)
    for k in diff[:20]:
        print("   differ:", k)
    return 0 if not (only_a or only_b or diff) else 1


def tree_hash(d):
    h = hashlib.sha256()
    for rel, p in sorted(walk(d).items()):
        h.update(rel.encode() + b"\0" + bytes.fromhex(digest(p)))
    print(h.hexdigest().upper(), d)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make-stock"); m.add_argument("--live", required=True); m.add_argument("--out", required=True); m.add_argument("--steam-json", required=True)
    c = sub.add_parser("compare"); c.add_argument("a"); c.add_argument("b"); c.add_argument("--sub", default="")
    t = sub.add_parser("tree-hash"); t.add_argument("dir")
    a = ap.parse_args()
    if a.cmd == "make-stock":
        make_stock(a.live, a.out, a.steam_json)
    elif a.cmd == "compare":
        return compare(a.a, a.b, a.sub)
    else:
        tree_hash(a.dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
