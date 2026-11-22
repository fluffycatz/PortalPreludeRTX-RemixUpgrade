"""Maintainer tool: build the GitHub Release assets into dist/ (git-ignored).

  python -I tools\\build_release.py [--version 1.0.0]

Assets:
  PortalPreludeRTX-RemixUpgrade-v<version>.zip   the scripts, manifests and docs, ready to run
  SHA256SUMS.txt

NVIDIA's package is never attached: Install.bat downloads it from NVIDIA's own GitHub release and checks its SHA-256.
"""
import argparse
import hashlib
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "PortalPreludeRTX-RemixUpgrade"
BUNDLE_FILES = ["Install.bat", "Install.ps1", "Uninstall.bat", "Uninstall.ps1", "Verify.bat", "Verify.ps1",
                "README.md", "CHANGELOG.md", "LICENSE"]
BUNDLE_DIRS = ["lib", "manifest", "docs"]


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(8 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="1.0.0")
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    top = f"{NAME}-v{a.version}"
    bundle = os.path.join(a.out, f"{NAME}-v{a.version}.zip")
    files = list(BUNDLE_FILES)
    for d in BUNDLE_DIRS:
        for r, _, fs in os.walk(os.path.join(ROOT, d)):
            files += [os.path.relpath(os.path.join(r, n), ROOT) for n in fs]
    with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in sorted(files, key=str.lower):
            z.write(os.path.join(ROOT, rel), top + "/" + rel.replace("\\", "/"))
    line = f"{sha256(bundle)}  {os.path.basename(bundle)}"
    with open(os.path.join(a.out, "SHA256SUMS.txt"), "w", encoding="ascii", newline="\n") as f:
        f.write(line + "\n")
    print(f"{len(files)} files -> {os.path.getsize(bundle):,} bytes")
    print(line)


if __name__ == "__main__":
    sys.exit(main())
