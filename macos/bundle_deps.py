#!/usr/bin/env python3
"""Copy every non-system dylib referenced by Mach-O files in an app bundle
into Contents/Frameworks and rewrite load commands to @loader_path-relative
paths, so the bundle no longer depends on Homebrew (or any other prefix).

Usage: bundle_deps.py /path/to/OpenKJ.app [extra lib search dirs...]
"""
import os
import shutil
import subprocess
import sys

SYSTEM_PREFIXES = ("/usr/lib/", "/System/")


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def is_macho(path):
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    with open(path, "rb") as f:
        magic = f.read(4)
    return magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")


def load_commands(path):
    """Return (install_id, [dependency paths], [rpaths])."""
    out = run("otool", "-l", path).splitlines()
    install_id, deps, rpaths = None, [], []
    i = 0
    while i < len(out):
        line = out[i].strip()
        if line.startswith("cmd "):
            cmd = line.split()[1]
            if cmd in ("LC_ID_DYLIB", "LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB", "LC_RPATH"):
                j = i + 1
                while j < len(out) and not out[j].strip().startswith(("name ", "path ")):
                    j += 1
                value = out[j].strip().split(" ", 1)[1].rsplit(" (offset", 1)[0]
                if cmd == "LC_ID_DYLIB":
                    install_id = value
                elif cmd == "LC_RPATH":
                    rpaths.append(value)
                else:
                    deps.append(value)
                i = j
        i += 1
    return install_id, deps, rpaths


def resolve(dep, origin_path, origin_rpaths):
    """Resolve a load path to a real file on disk, relative to the ORIGINAL location of the referencing binary."""
    origin_dir = os.path.dirname(origin_path)
    if dep.startswith("@loader_path/"):
        cand = os.path.join(origin_dir, dep[len("@loader_path/"):])
        return os.path.realpath(cand) if os.path.exists(cand) else None
    if dep.startswith("@rpath/"):
        for rp in origin_rpaths:
            rp = rp.replace("@loader_path", origin_dir)
            cand = os.path.join(rp, dep[len("@rpath/"):])
            if os.path.exists(cand):
                return os.path.realpath(cand)
        return None
    if dep.startswith("@executable_path/"):
        return None  # already bundled (macdeployqt)
    return os.path.realpath(dep) if os.path.exists(dep) else None


def resolve_fallback(dep, fw_dir, search_dirs):
    """For @rpath/@loader_path refs whose original rpaths are unknown (e.g. files
    copied in by macdeployqt), look for the library by name."""
    name = os.path.basename(dep)
    for d in [fw_dir] + search_dirs:
        cand = os.path.join(d, name)
        if os.path.exists(cand):
            return os.path.realpath(cand)
    return None


def main(app, search_dirs):
    app = os.path.abspath(app)
    fw_dir = os.path.join(app, "Contents", "Frameworks")
    os.makedirs(fw_dir, exist_ok=True)
    main_exe = os.path.join(app, "Contents", "MacOS", run("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleExecutable",
                                                         os.path.join(app, "Contents", "Info.plist")).strip())
    origins = {}  # bundled path -> original on-disk path (for resolving relative refs)
    queue = []
    for root, _, files in os.walk(app):
        for name in files:
            p = os.path.join(root, name)
            if is_macho(p):
                queue.append(p)
    seen = set()
    missing = []
    while queue:
        path = queue.pop()
        real = os.path.realpath(path)
        if real in seen:
            continue
        seen.add(real)
        os.chmod(path, 0o755)
        install_id, deps, rpaths = load_commands(path)
        origin = origins.get(real, real)
        _, _, origin_rpaths = load_commands(origin) if origin != real else (None, None, rpaths)
        changes = []
        if install_id and not install_id.startswith("@"):
            changes += ["-id", "@rpath/" + os.path.basename(path)]
        for dep in deps:
            if dep.startswith("@executable_path/../Frameworks/") and path != main_exe:
                # macdeployqt writes @executable_path refs, which break when the library is
                # loaded by a different executable (e.g. gst-plugin-scanner). Make them relative.
                target = os.path.join(fw_dir, dep[len("@executable_path/../Frameworks/"):])
                if not os.path.exists(target):
                    missing.append((path, dep))
                    continue
                changes += ["-change", dep, "@loader_path/" + os.path.relpath(target, os.path.dirname(path))]
                continue
            if dep.startswith(SYSTEM_PREFIXES) or dep.startswith("@executable_path/"):
                continue
            if dep.startswith("@loader_path/") and origin == real and \
                    os.path.exists(os.path.join(os.path.dirname(path), dep[len("@loader_path/"):])):
                continue  # already a valid bundle-relative path
            src = resolve(dep, origin, origin_rpaths)
            if src is None and dep.startswith(("@rpath/", "@loader_path/")):
                src = resolve_fallback(dep, fw_dir, search_dirs)
            if src is None:
                missing.append((path, dep))
                continue
            dest = os.path.join(fw_dir, os.path.basename(src))
            # Qt frameworks were deployed by macdeployqt; point at them instead of copying.
            if ".framework/" in src:
                continue
            if not os.path.exists(dest):
                shutil.copy2(src, dest)
                os.chmod(dest, 0o755)
                origins[os.path.realpath(dest)] = src
                run("install_name_tool", "-id", "@rpath/" + os.path.basename(dest), dest)
                queue.append(dest)
            rel = os.path.relpath(dest, os.path.dirname(path))
            changes += ["-change", dep, "@loader_path/" + rel]
        # Drop rpaths that point outside the bundle.
        for rp in rpaths:
            if not rp.startswith("@"):
                changes += ["-delete_rpath", rp]
        if changes:
            run("install_name_tool", *changes, path)
    if missing:
        for p, d in missing:
            print(f"UNRESOLVED: {p} -> {d}", file=sys.stderr)
        sys.exit(1)
    print(f"Processed {len(seen)} Mach-O files")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
