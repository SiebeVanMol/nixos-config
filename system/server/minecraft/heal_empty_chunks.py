#!/usr/bin/env python3
"""Heal empty (void) chunks in a Minecraft world.

The Cobbleverse server previously generated void chunks (all-air, saved as `full`
status). Those never regenerate on their own. This tool removes them from the
region files so Minecraft regenerates them on next load (with the fixed
voxyworldgenv2 they now generate correctly).

Usage: heal_empty_chunks.py <worlddir>
"""
import os, sys, glob, struct, zlib, gzip

def parse_payload(tt, buf, off):
    if tt == 1: return struct.unpack(">b", buf[off:off+1])[0], off+1
    if tt == 2: return struct.unpack(">h", buf[off:off+2])[0], off+2
    if tt == 3: return struct.unpack(">i", buf[off:off+4])[0], off+4
    if tt == 4: return struct.unpack(">q", buf[off:off+8])[0], off+8
    if tt == 5: return struct.unpack(">f", buf[off:off+4])[0], off+4
    if tt == 6: return struct.unpack(">d", buf[off:off+8])[0], off+8
    if tt == 7:
        ln = struct.unpack(">i", buf[off:off+4])[0]; off += 4
        return buf[off:off+ln], off+ln
    if tt == 8:
        ln = struct.unpack(">H", buf[off:off+2])[0]; off += 2
        return buf[off:off+ln].decode("utf-8","replace"), off+ln
    if tt == 9:
        lt = buf[off]; off += 1
        ln = struct.unpack(">i", buf[off:off+4])[0]; off += 4
        items = []
        for _ in range(ln):
            if lt == 10:
                if buf[off] == 10:
                    d = {}
                    off += 1
                    while buf[off] != 0:
                        et, nn, off = read_named_header(buf, off)
                        v, off = parse_payload(et, buf, off)
                        d[nn] = v
                    off += 1
                    items.append(d)
                else:
                    off += 1
                    items.append({})
            else:
                v, off = parse_payload(lt, buf, off)
                items.append(v)
        return items, off
    if tt == 10:
        d = {}
        while buf[off] != 0:
            et, nn, off = read_named_header(buf, off)
            v, off = parse_payload(et, buf, off)
            d[nn] = v
        off += 1
        return d, off
    if tt == 11:
        ln = struct.unpack(">i", buf[off:off+4])[0]; off += 4
        return list(struct.unpack(f">{ln}i", buf[off:off+4*ln])), off+4*ln
    if tt == 12:
        ln = struct.unpack(">i", buf[off:off+4])[0]; off += 4
        return list(struct.unpack(f">{ln}q", buf[off:off+8*ln])), off+8*ln
    raise ValueError(f"unknown payload tag {tt}")

def read_named_header(buf, off):
    t = buf[off]; off += 1
    nl = struct.unpack(">H", buf[off:off+2])[0]; off += 2
    name = buf[off:off+nl].decode("utf-8", "replace"); off += nl
    return t, name, off

def parse_nbt(buf, off):
    if buf[off] == 0:
        return None, off + 1
    t, _, off = read_named_header(buf, off)
    return parse_payload(t, buf, off)

def read_chunk(region_path, x, z):
    with open(region_path, "rb") as f:
        hdr = f.read(4096)
        entry = struct.unpack(">I", hdr[((z & 31) * 32 + (x & 31)) * 4:][:4])[0]
        if entry == 0:
            return None
        off = (entry >> 8) * 4096
        f.seek(off)
        ln = struct.unpack(">I", f.read(4))[0]
        comp = struct.unpack(">b", f.read(1))[0]
        data = f.read(ln - 1)
        if comp == 1:
            data = gzip.decompress(data)
        elif comp == 2:
            data = zlib.decompress(data)
        return data

def chunk_is_empty(region_path, x, z):
    """Return True if the chunk at (x,z) is all-air (void)."""
    with open(region_path, "rb") as f:
        hdr = f.read(4096)
        entry = struct.unpack(">I", hdr[((z & 31) * 32 + (x & 31)) * 4:][:4])[0]
        if entry == 0:
            return False
        off = (entry >> 8) * 4096
        f.seek(off)
        ln = struct.unpack(">I", f.read(4))[0]
        # tiny chunks are almost certainly empty
        if ln < 1500:
            return True
        comp = struct.unpack(">b", f.read(1))[0]
        data = f.read(ln - 1)
        try:
            if comp == 1:
                data = gzip.decompress(data)
            elif comp == 2:
                data = zlib.decompress(data)
            nbt, _ = parse_nbt(data, 0)
            for sec in (nbt.get("sections") or []):
                if not isinstance(sec, dict):
                    continue
                bs = sec.get("block_states")
                if not isinstance(bs, dict):
                    continue
                for entry_pal in (bs.get("palette") or []):
                    if isinstance(entry_pal, dict) and entry_pal.get("Name", "minecraft:air") != "minecraft:air":
                        return False
            # also check block_entities (an empty chunk has none, but be safe)
            if isinstance(nbt.get("block_entities"), list) and nbt["block_entities"]:
                return False
            return True
        except Exception:
            # if we can't parse and it's >=1500 bytes, assume NOT empty (be conservative)
            return False

def heal_world(worlddir):
    region_dir = os.path.join(worlddir, "region")
    if not os.path.isdir(region_dir):
        print(f"No region dir at {region_dir}")
        return
    healed = 0
    total = 0
    for rp in sorted(glob.glob(os.path.join(region_dir, "*.mca"))):
        if os.path.getsize(rp) == 0:
            continue
        with open(rp, "r+b") as f:
            hdr = f.read(4096)
            if len(hdr) < 4096:
                continue
            changed = False
            for cz in range(32):
                for cx in range(32):
                    idx = (cz * 32 + cx) * 4
                    entry = struct.unpack(">I", hdr[idx:idx+4])[0]
                    if entry == 0:
                        continue
                    total += 1
                    if chunk_is_empty(rp, cx, cz):
                        # zero the location entry -> chunk becomes ungenerated, will regenerate
                        f.seek(idx)
                        f.write(b"\x00\x00\x00\x00")
                        healed += 1
                        changed = True
            if changed:
                f.flush()
                os.fsync(f.fileno())
    print(f"scanned {total} chunks, removed {healed} empty chunks")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: heal_empty_chunks.py <worlddir>")
        sys.exit(1)
    heal_world(sys.argv[1])
