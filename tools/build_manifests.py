"""Maintainer tool: turn the JSON inventories from inventory.py into the CSV manifests the scripts use.

  python -I tools\\build_manifests.py --steam steam_stock.json --package package.json --live live_snapshot.json
         --out manifest [--snapshot-name live-install-snapshot-<date>.csv]

Writes:
  manifest/patch-files.csv                 every file the upgrade installs (target, source, size, SHA-256)
  manifest/stock-files.csv                 every stock 0.2.1 file the upgrade moves to a backup (size, SHA-256, Steam SHA-1)
  manifest/package-remix-1.6.1-x86.csv     every member of NVIDIA's zip and where (or why not) it is installed
  manifest/steam-stock-build-<id>.csv      Steam's full stock file list for the build (size, SHA-1, flags)
  manifest/<snapshot-name>                 every file in the working install, classified
"""
import argparse
import csv
import json
import os
import sys

BAK = ".prelude-0.2.1.bak"
# Package members deliberately not installed, with the reason recorded in the manifest.
SKIP_PREFIX = {".trex_arm64/": "not installed: ARM64 Windows runtime"}
SKIP_EXACT = {"d3d8to9.dll": "not installed: D3D8 games only",
              "ThirdPartyLicenses-d3d8to9.txt": "not installed: belongs to d3d8to9.dll"}
# bridge.conf is not in NVIDIA's package; the upgrade writes the stock Prelude file (carried over).
BUILTIN = {"bin\\.trex\\bridge.conf": "builtin:bridge.conf"}


def target_for(member):
    return "bin\\" + member.replace("/", "\\")


def skip_reason(member):
    if member in SKIP_EXACT:
        return SKIP_EXACT[member]
    for p, why in SKIP_PREFIX.items():
        if member.startswith(p):
            return why
    return None


def write_csv(path, header, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    print(f"wrote {path} ({len(rows)} rows)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steam", required=True)
    ap.add_argument("--package", required=True)
    ap.add_argument("--live", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--snapshot-name", default="live-install-snapshot.csv")
    a = ap.parse_args()
    steam = json.load(open(a.steam, encoding="utf-8"))
    pkg = json.load(open(a.package, encoding="utf-8"))
    live = json.load(open(a.live, encoding="utf-8"))
    os.makedirs(a.out, exist_ok=True)

    stock = {f["path"].lower(): f for f in steam["files"] if not f["flags"] & 64}
    livem = {f["path"].lower(): f for f in live["files"]}

    # ---- patch files
    patch = []
    for m in pkg["members"]:
        if skip_reason(m["path"]):
            continue
        patch.append((target_for(m["path"]), "zip:" + m["path"], m["size"], m["sha256"].upper()))
    for tgt, src in BUILTIN.items():
        lf = livem[tgt.lower()]
        st = stock[tgt.lower()]
        assert lf["sha1"] == st["sha1"], "bridge.conf in the working install must be the stock file"
        patch.append((tgt, src, lf["size"], lf["sha256"].upper()))
    patch.sort(key=lambda r: r[0].lower())
    for tgt, src, size, sha in patch:  # the working install must hold exactly these bytes
        lf = livem.get(tgt.lower())
        assert lf and lf["sha256"].upper() == sha and lf["size"] == size, f"working install differs at {tgt}"
    write_csv(os.path.join(a.out, "patch-files.csv"), ["Target", "Source", "Size", "SHA256"], patch)
    patch_by_target = {r[0].lower(): r for r in patch}

    # ---- stock files moved to backups (everything the upgrade replaces or retires)
    stock_rows = []
    for k, s in sorted(stock.items()):
        p = s["path"]
        if not (k.startswith("bin\\.trex\\") or k in ("bin\\d3d9.dll", "bin\\nvremixbridge32.dll")):
            continue
        if k.startswith("bin\\.trex\\"):
            bak = "bin\\.trex" + BAK + p[len("bin\\.trex"):]
        else:
            bak = p + BAK
        b = livem.get(bak.lower())
        assert b and b["sha1"] == s["sha1"] and b["size"] == s["size"], f"backup missing or not stock: {bak}"
        stock_rows.append((p, s["size"], b["sha256"].upper(), s["sha1"].upper()))
    write_csv(os.path.join(a.out, "stock-files.csv"), ["Path", "Size", "SHA256", "SHA1"], stock_rows)
    stock_set = {r[0].lower(): r for r in stock_rows}

    # ---- package listing
    pk_rows = []
    for m in pkg["members"]:
        why = skip_reason(m["path"])
        pk_rows.append((m["path"], m["size"], m["crc32"].upper(), m["sha256"].upper(), m["sha1"].upper(),
                        why if why else target_for(m["path"])))
    write_csv(os.path.join(a.out, "package-remix-1.6.1-x86.csv"),
              ["Member", "Size", "CRC32", "SHA256", "SHA1", "InstalledAs"], pk_rows)

    # ---- Steam stock list
    st_rows = [(s["path"], s["size"], (s["sha1"] or "").upper(), "|".join(s["flag_names"]))
               for s in sorted(stock.values(), key=lambda s: s["path"].lower())]
    build = None
    write_csv(os.path.join(a.out, f"steam-stock-depot{steam['depot_id']}-manifest{steam['manifest_gid']}.csv"),
              ["Path", "Size", "SHA1", "Flags"], st_rows)

    # ---- the working install, classified
    rows = []
    counts = {}
    for k, f in sorted(livem.items()):
        p = f["path"]
        s = stock.get(k)
        pr = patch_by_target.get(k)
        if pr and pr[3] == f["sha256"].upper():
            cls = "patch (same bytes as stock)" if (s and s["sha1"] == f["sha1"]) else "patch"
        elif s and s["sha1"] == f["sha1"]:
            cls = "stock"
        elif k.endswith(BAK) or k.startswith("bin\\.trex" + BAK + "\\"):
            orig = (k[:-len(BAK)] if k.endswith(BAK) else "bin\\.trex\\" + k[len("bin\\.trex" + BAK + "\\"):])
            cls = "backup of stock" if orig in stock_set and stock_set[orig][3] == f["sha1"].upper() else "backup folder: other file"
        elif s:
            cls = "stock file changed by the game or user"
        else:
            cls = "created by the game or user"
        counts[cls] = counts.get(cls, 0) + 1
        rows.append((p, f["size"], f["sha256"].upper(), f["sha1"].upper(), f["mtime_utc"], cls))
    write_csv(os.path.join(a.out, a.snapshot_name), ["Path", "Size", "SHA256", "SHA1", "ModifiedUtc", "Class"], rows)
    for k in sorted(counts):
        print(f"  {counts[k]:6d}  {k}")
    missing = sorted(s["path"] for kk, s in stock.items() if kk not in livem)
    print("stock files not on disk (moved to backups):", len(missing))


if __name__ == "__main__":
    sys.exit(main())
