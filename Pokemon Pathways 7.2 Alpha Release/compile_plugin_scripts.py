#!/usr/bin/env python3
"""
compile_plugin_scripts.py (FIXED VERSION)

Fixes:
- Handles broken Windows paths with extra quotes
- Robust PluginScripts.rxdata detection fallback
- Safer path normalization
"""

import sys
import os
import zlib
import shutil

# ── Configuration ──────────────────────────────────────────────────────────────
PLUGIN_NAME = "Multiplayer"
PLUGIN_DIR  = "Plugins"
RXDATA_PATH = os.path.join("Data", "PluginScripts.rxdata")
BACKUP_SUFFIX = ".bak"

SCRIPT_FILES = [
    "000_mp_diagnostic.rb",
    "001_mp_config.rb",
    "002_mp_packet.rb",
    "003_mp_data.rb",
    "004_mp_network.rb",
    "005_mp_remote_player.rb",
    "006_mp_remote_sprite.rb",
    "007_mp_overworld.rb",
    "008_mp_hooks.rb",
    "009_mp_battle.rb",
    "010_mp_trade.rb",
    "011_mp_chat.rb",
    "012_mp_version.rb",
]

# ── FIX: clean Windows path issues ─────────────────────────────────────────────
def clean_path(p: str) -> str:
    return os.path.normpath(p.strip().strip('"').strip("'"))


# ── Ruby Marshal types ─────────────────────────────────────────────────────────
class RubyI:
    def __init__(self, val, ivars):
        self.val = val
        self.ivars = ivars

class RubyRef:
    def __init__(self, idx):
        self.idx = idx

class RubyUser:
    def __init__(self, klass, data):
        self.klass = klass
        self.data = data


# ── Marshal reader ─────────────────────────────────────────────────────────────
class MarshalReader:
    def __init__(self, data):
        self.data = data
        self.pos = 2
        self.symbols = []

    def rb(self):
        b = self.data[self.pos]
        self.pos += 1
        return b

    def ri(self):
        b = self.rb()
        if b > 127: b -= 256
        if b == 0: return 0
        if b > 4: return b - 5
        if b < -4: return b + 5
        n = 0
        if b > 0:
            for i in range(b):
                n |= self.rb() << (8 * i)
        else:
            b = -b
            for i in range(b):
                n |= self.rb() << (8 * i)
            n -= (1 << (8 * b))
        return n

    def rs(self):
        l = self.ri()
        s = self.data[self.pos:self.pos + l]
        self.pos += l
        return s

    def rv(self):
        t = chr(self.rb())

        if t == '0': return None
        if t == 'T': return True
        if t == 'F': return False
        if t == 'i': return self.ri()
        if t == '"': return self.rs()
        if t == ':':
            sym = self.rs().decode('utf-8', errors='replace')
            self.symbols.append(sym)
            return sym
        if t == ';': return self.symbols[self.ri()]
        if t == '[':
            n = self.ri()
            return [self.rv() for _ in range(n)]
        if t == '{':
            n = self.ri()
            h = {}
            for _ in range(n):
                k = self.rv()
                h[k] = self.rv()
            return h
        if t == 'I':
            val = self.rv()
            n = self.ri()
            iv = {}
            for _ in range(n):
                k = self.rv()
                iv[k] = self.rv()
            return RubyI(val, iv)
        if t == '@':
            return RubyRef(self.ri())
        if t == 'u':
            return RubyUser(self.rv(), self.rs())

        raise ValueError(f"Unknown Marshal type {t}")


# ── Marshal writer ─────────────────────────────────────────────────────────────
class MarshalWriter:
    def __init__(self):
        self.buf = bytearray(b'\x04\x08')
        self.symbols = {}

    def wb(self, b):
        self.buf.append(b & 0xff)

    def wi(self, n):
        if n == 0:
            self.buf.append(0)
            return
        if 0 < n < 123:
            self.buf.append(n + 5)
            return
        if -124 < n < 0:
            self.buf.append((n - 5) & 0xff)
            return
        if n > 0:
            enc = []
            t = n
            while t > 0:
                enc.append(t & 0xff)
                t >>= 8
            self.buf.append(len(enc))
            self.buf.extend(enc)
        else:
            nb = 1
            while not ((-1 << (8 * nb)) <= n < 0):
                nb += 1
            self.buf.append((256 - nb) & 0xff)
            for _ in range(nb):
                self.buf.append(n & 0xff)
                n >>= 8

    def ws(self, s):
        if isinstance(s, str):
            s = s.encode('utf-8')
        self.wi(len(s))
        self.buf.extend(s)

    def wv(self, v):
        if v is None:
            self.buf.append(ord('0')); return
        if v is True:
            self.buf.append(ord('T')); return
        if v is False:
            self.buf.append(ord('F')); return
        if isinstance(v, int):
            self.buf.append(ord('i')); self.wi(v); return
        if isinstance(v, bytes):
            self.buf.append(ord('"')); self.ws(v); return
        if isinstance(v, str):
            self.buf.append(ord(':'))
            self.ws(v); return
        if isinstance(v, list):
            self.buf.append(ord('['))
            self.wi(len(v))
            for i in v: self.wv(i)
            return
        if isinstance(v, dict):
            self.buf.append(ord('{'))
            self.wi(len(v))
            for k, val in v.items():
                self.wv(k); self.wv(val)
            return
        if isinstance(v, RubyI):
            self.buf.append(ord('I'))
            self.wv(v.val)
            self.wi(len(v.ivars))
            for k, val in v.ivars.items():
                self.wv(k); self.wv(val)
            return
        if isinstance(v, RubyRef):
            self.buf.append(ord('@')); self.wi(v.idx); return
        if isinstance(v, RubyUser):
            self.buf.append(ord('u'))
            self.wv(v.klass); self.ws(v.data); return

        raise ValueError(f"Unsupported type {type(v)}")


# ── Helpers ────────────────────────────────────────────────────────────────────
def find_rxdata(game_root):
    """Try standard + fallback search."""
    direct = os.path.join(game_root, RXDATA_PATH)
    if os.path.exists(direct):
        return direct

    # fallback search
    for root, _, files in os.walk(game_root):
        for f in files:
            if f.lower() == "pluginscripts.rxdata":
                return os.path.join(root, f)

    return None


def find_plugin_dir(game_root):
    candidates = [
        os.path.join(game_root, PLUGIN_DIR, PLUGIN_NAME),
        os.path.join(game_root, PLUGIN_NAME),
    ]
    for c in candidates:
        if os.path.isdir(c):
            return c
    return None


# ── Main ──────────────────────────────────────────────────────────────────────
def main(game_root):
    game_root = clean_path(game_root)

    rxdata_path = find_rxdata(game_root)
    if not rxdata_path:
        print("ERROR: PluginScripts.rxdata not found anywhere.")
        return False

    plugin_dir = find_plugin_dir(game_root)
    if not plugin_dir:
        print("ERROR: Multiplayer plugin folder not found.")
        return False

    print(f"Game root  : {game_root}")
    print(f"Plugin dir : {plugin_dir}")
    print(f"rxdata     : {rxdata_path}\n")

    with open(rxdata_path, "rb") as f:
        raw = f.read()

    r = MarshalReader(raw)
    scripts = r.rv()

    # find plugin entry
    mp_idx = None
    for i, entry in enumerate(scripts):
        if isinstance(entry, list):
            name = entry[0]
            if isinstance(name, RubyI):
                name = name.val
            if isinstance(name, bytes):
                name = name.decode("utf-8", errors="ignore")

            if name == PLUGIN_NAME:
                mp_idx = i
                break

    if mp_idx is None:
        print("ERROR: Multiplayer plugin not found in rxdata.")
        return False

    mp_entry = scripts[mp_idx]
    scripts_list = mp_entry[2]

    shutil.copy2(rxdata_path, rxdata_path + ".bak")
    print("Backup created.\n")

    updated = 0

    for i, pair in enumerate(scripts_list):
        fname = pair[0].val if isinstance(pair[0], RubyI) else pair[0]
        if isinstance(fname, bytes):
            fname = fname.decode()

        rb_path = os.path.join(plugin_dir, fname)

        if os.path.exists(rb_path):
            with open(rb_path, "r", encoding="utf-8") as f:
                code = f.read()

            scripts_list[i] = [
                pair[0],
                zlib.compress(code.encode("utf-8"))
            ]

            updated += 1
            print(f"[OK] {fname}")
        else:
            print(f"[SKIP] {fname}")

    w = MarshalWriter()
    w.wv(scripts)

    with open(rxdata_path, "wb") as f:
        f.write(bytes(w.buf))

    print(f"\nDone. Updated {updated} scripts.")
    return True


if __name__ == "__main__":
    game_root = clean_path(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
    sys.exit(0 if main(game_root) else 1)