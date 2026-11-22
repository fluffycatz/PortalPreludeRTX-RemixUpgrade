"""Maintainer tool: record and compare file inventories for the Prelude RTX Remix upgrade.

Subcommands (all output is JSON; nothing is ever written into the game folder):
  steam    --manifest <depotcache .manifest>  --out <json>   Steam's stock file list (size, flags, SHA-1)
  package  --zip <remix zip>                  --out <json>   every member of NVIDIA's zip (size, CRC32, SHA-1, SHA-256)
  snapshot --game <game dir>                  --out <json>   every file on disk (size, mtime, SHA-1, SHA-256)

Run with:  python -I tools\\inventory.py <subcommand> ...
"""
import argparse
import hashlib
import json
import os
import struct
import sys
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor

CHUNK = 8 << 20

# ---------------------------------------------------------------- Steam depot manifest (protobuf)
PAYLOAD_MAGIC = 0x71F617D0
METADATA_MAGIC = 0x1F4812BE
SIGNATURE_MAGIC = 0x1B81B817
END_MAGIC = 0x32C415AB

STEAM_FLAGS = {1: "UserConfig", 2: "VersionedUserConfig", 4: "Encrypted", 8: "ReadOnly", 16: "Hidden",
               32: "Executable", 64: "Directory", 128: "CustomExecutable", 256: "InstallScript", 512: "Symlink"}


def _varint(b, i):
    shift = result = 0
    while True:
        c = b[i]
        i += 1
        result |= (c & 0x7F) << shift
        if not c & 0x80:
            return result, i
        shift += 7


def _fields(b):
    i, n = 0, len(b)
    while i < n:
        key, i = _varint(b, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _varint(b, i)
        elif wt == 1:
            v = struct.unpack_from("<Q", b, i)[0]
            i += 8
        elif wt == 2:
            ln, i = _varint(b, i)
            v = b[i:i + ln]
            i += ln
        elif wt == 5:
            v = struct.unpack_from("<I", b, i)[0]
            i += 4
        else:
            raise ValueError(f"unsupported protobuf wire type {wt}")
        yield fn, v


def steam_manifest(path):
    data = open(path, "rb").read()
    i, payload, meta = 0, None, None
    while i < len(data):
        magic = struct.unpack_from("<I", data, i)[0]
        i += 4
        if magic == END_MAGIC:
            break
        ln = struct.unpack_from("<I", data, i)[0]
        i += 4
        blob = data[i:i + ln]
        i += ln
        if magic == PAYLOAD_MAGIC:
            payload = blob
        elif magic == METADATA_MAGIC:
            meta = blob
        elif magic != SIGNATURE_MAGIC:
            raise ValueError(f"unknown section magic {magic:#x}")
    md = dict(_fields(meta))
    files = []
    for fn, v in _fields(payload):
        if fn != 1:
            continue
        e = {"path": None, "size": 0, "flags": 0, "sha1": None, "sha_filename": None}
        for f2, v2 in _fields(v):
            if f2 == 1:
                e["path"] = v2.decode("utf-8").rstrip("\x00")
            elif f2 == 2:
                e["size"] = v2
            elif f2 == 3:
                e["flags"] = v2
            elif f2 == 4:
                e["sha_filename"] = v2.hex()
            elif f2 == 5:
                e["sha1"] = v2.hex()
            elif f2 == 7:
                e["linktarget"] = v2.decode("utf-8")
        e["flag_names"] = [name for bit, name in STEAM_FLAGS.items() if e["flags"] & bit]
        files.append(e)
    raw = open(path, "rb").read()
    return {
        "source": os.path.basename(path),
        "source_size": len(raw),
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "depot_id": md.get(1),
        "manifest_gid": md.get(2),
        "creation_time": md.get(3),
        "creation_time_utc": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(md.get(3, 0))),
        "filenames_encrypted": bool(md.get(4, 0)),
        "cb_disk_original": md.get(5),
        "files": sorted(files, key=lambda e: (e["path"] or "").lower()),
    }


# ---------------------------------------------------------------- hashing helpers
def hash_stream(f):
    h1, h2 = hashlib.sha1(), hashlib.sha256()
    while True:
        b = f.read(CHUNK)
        if not b:
            break
        h1.update(b)
        h2.update(b)
    return h1.hexdigest(), h2.hexdigest()


def hash_file(p):
    with open(p, "rb") as f:
        return hash_stream(f)


def package(zip_path):
    whole_sha1, whole_sha256 = hash_file(zip_path)
    members = []
    with zipfile.ZipFile(zip_path) as z:
        for zi in z.infolist():
            if zi.is_dir():
                continue
            with z.open(zi) as f:
                s1, s256 = hash_stream(f)
            members.append({"path": zi.filename, "size": zi.file_size, "crc32": f"{zi.CRC:08x}",
                            "sha1": s1, "sha256": s256})
    return {"source": os.path.basename(zip_path), "size": os.path.getsize(zip_path),
            "sha1": whole_sha1, "sha256": whole_sha256,
            "members": sorted(members, key=lambda m: m["path"].lower())}


def snapshot(game):
    paths = []
    for root, dirs, files in os.walk(game):
        dirs.sort(key=str.lower)
        for name in files:
            paths.append(os.path.join(root, name))

    def one(p):
        st = os.stat(p)
        s1, s256 = hash_file(p)
        return {"path": os.path.relpath(p, game).replace("/", "\\"), "size": st.st_size,
                "mtime_utc": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(st.st_mtime)),
                "sha1": s1, "sha256": s256}

    t0 = time.time()
    with ThreadPoolExecutor(max_workers=8) as ex:
        out = list(ex.map(one, paths))
    total = sum(e["size"] for e in out)
    return {"game_dir": game, "taken_utc": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
            "file_count": len(out), "total_bytes": total, "hash_seconds": round(time.time() - t0, 1),
            "files": sorted(out, key=lambda e: e["path"].lower())}


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("steam"); a.add_argument("--manifest", required=True); a.add_argument("--out", required=True)
    b = sub.add_parser("package"); b.add_argument("--zip", required=True); b.add_argument("--out", required=True)
    c = sub.add_parser("snapshot"); c.add_argument("--game", required=True); c.add_argument("--out", required=True)
    args = ap.parse_args()
    if args.cmd == "steam":
        res = steam_manifest(args.manifest)
        print(f"depot {res['depot_id']} manifest {res['manifest_gid']} files {len(res['files'])} "
              f"encrypted_names={res['filenames_encrypted']}")
    elif args.cmd == "package":
        res = package(args.zip)
        print(f"{res['source']} {res['size']} B sha256 {res['sha256']} members {len(res['members'])}")
    else:
        res = snapshot(os.path.abspath(args.game))
        print(f"{res['file_count']} files, {res['total_bytes']} B, {res['hash_seconds']} s")
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(res, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    sys.exit(main())
