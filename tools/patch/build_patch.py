#!/usr/bin/env python3
"""Builds zz_patch.pck: every file changed since BASE (plus new world/ files), as a code-only
pack the player drops next to a shipped game exe (tools/build/packs.gd mounts *.pck in name
order, later ones win). See AGENT_HANDOFF.md, "Shipping a patch".

  GODOT=/path/to/Godot_v4.5-stable_linux.x86_64 BASE=3617d97 python3 tools/patch/build_patch.py

Needs Godot 4.5 exactly (a 4.6 pack is refused by a 4.5 game). Output: $OUT/zz_patch.pck
(default: build/patch/). The local dev-tools override (dev_tools_local.diff) is applied to the
patch copy only, so the repo's dev_tools.gd stays untouched."""
import os, shutil, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pck
ROOT = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True, cwd=HERE).strip()
GODOT = os.environ.get("GODOT", "godot")
BASE = os.environ.get("BASE", "3617d97")
OUT = os.environ.get("OUT", os.path.join(ROOT, "build", "patch"))
os.makedirs(OUT, exist_ok=True)
M = os.path.join(OUT, "mini")
shutil.rmtree(M, ignore_errors=True); os.makedirs(M)
os.chdir(ROOT)
files = subprocess.check_output(["git", "diff", "--name-only", BASE], text=True).split()
files += subprocess.check_output("git ls-files --others --exclude-standard world", shell=True, text=True).split()
SKIP = (".uid", ".md", ".py", ".diff")
files = sorted(set(f for f in files if os.path.exists(f) and not f.endswith(SKIP) and not f.startswith("tools/patch/")))
for f in files:
    os.makedirs(os.path.dirname(os.path.join(M, f)), exist_ok=True)
    shutil.copy(f, os.path.join(M, f))
# Local-only switch: a player build turns dev tools on when an empty dev_tools.txt sits by the exe.
if "world/dev_tools.gd" not in files:
    os.makedirs(M + "/world", exist_ok=True)
    shutil.copy("world/dev_tools.gd", M + "/world/dev_tools.gd")
    files.append("world/dev_tools.gd")
subprocess.check_call(["patch", "-s", "-p1", "-d", M, "-i", os.path.join(HERE, "dev_tools_local.diff")])
files = sorted(set(files))
open(M + "/project.godot", "w").write('config_version=5\n\n[application]\n\nconfig/name="Patch"\nconfig/features=PackedStringArray("4.5")\n')
paths = ",".join('"res://%s"' % f for f in files)
open(M + "/export_presets.cfg", "w").write(
    '[preset.0]\n\nname="Patch"\nplatform="Windows Desktop"\nrunnable=false\nadvanced_options=false\n'
    'dedicated_server=false\ncustom_features=""\nexport_filter="resources"\nexport_files=PackedStringArray(%s)\n'
    'include_filter=""\nexclude_filter=""\nexport_path=""\nencryption_include_filters=""\n'
    'encryption_exclude_filters=""\nseed=0\nencrypt_pck=false\nencrypt_directory=false\n'
    'script_export_mode=2\n\n[preset.0.options]\n' % paths)
raw = os.path.join(OUT, "zz_patch_raw.pck")
subprocess.run([GODOT, "--headless", "--path", M, "--export-pack", "Patch", raw],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
data, header, entries = pck.read(raw)
# Drop .godot/* , project.binary and .uid files: only the scripts and data themselves.
kept = pck.write(os.path.join(OUT, "zz_patch.pck"), data, header, entries,
                 lambda n: not n.startswith(".godot") and n != "project.binary" and not n.endswith(".uid"))
print(len(files), "source files ->", len(kept), "pack entries;", os.path.getsize(os.path.join(OUT, "zz_patch.pck")), "bytes")
