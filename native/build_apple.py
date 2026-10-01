#!/usr/bin/env python3
"""Builds the meltiew_luau GDExtension for Apple platforms from Linux, with zig (its own
libc/libc++ for macOS, no SDK needed) and llvm-lipo:

    python3 build_apple.py macos          # universal dylib (arm64 + x86_64)
    IOS_SDK=/path/iPhoneOS.sdk python3 build_apple.py ios   # static library (arm64),
        # with the system's clang and Apple's iPhoneOS SDK (from Xcode)

godot-cpp's bindings must be generated first (third_party/godot-cpp/gen); scons does
that itself, or:
    cd third_party/godot-cpp && python3 -c "import binding_generator as b;
        b.generate_bindings('gdextension/extension_api.json', True, '64', 'single', '.')"
"""
import concurrent.futures
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TP = HERE / "third_party"
CPP = TP / "godot-cpp"
LUAU = TP / "luau"
OUT = HERE.parent / "client" / "addons" / "meltiew_luau" / "bin"
BUILD = HERE / "build_apple"

TARGETS = {
    "macos": [("aarch64-macos.11.0", "arm64"), ("x86_64-macos.10.13", "x86_64")],
    "ios": [("arm64-apple-ios16.0", "ios-arm64")],
}


def sources():
    out = []
    for d in [CPP / "src", CPP / "gen" / "src"]:
        out += sorted(d.rglob("*.cpp"))
    out += sorted((HERE / "core").glob("*.cpp")) + sorted((HERE / "godot").glob("*.cpp"))
    for d in ["VM/src", "Compiler/src", "Ast/src", "Bytecode/src", "Common/src"]:
        out += sorted((LUAU / d).glob("*.cpp"))
    return out


def includes():
    inc = [CPP / "include", CPP / "gen" / "include", CPP / "gdextension", LUAU / "VM" / "src"]
    inc += [LUAU / d / "include" for d in ["VM", "Compiler", "Ast", "Common", "Bytecode"]]
    return [f"-I{p}" for p in inc]


def compile_one(src, obj, target):
    obj.parent.mkdir(parents=True, exist_ok=True)
    # (An empty object is what an interrupted run leaves: build it again.)
    if obj.exists() and obj.stat().st_size > 0 and obj.stat().st_mtime > src.stat().st_mtime:
        return None
    if "ios" in target:
        cc = ["clang++", "-target", target, "-isysroot", os.environ["IOS_SDK"], "-stdlib=libc++", "-DIOS_ENABLED"]
    else:
        cc = ["zig", "c++", "-target", target, "-DMACOS_ENABLED"]
    cmd = cc + ["-std=c++17", "-O2", "-fPIC", "-fvisibility=hidden",
                "-DNDEBUG", "-DGDEXTENSION", "-DTHREADS_ENABLED", "-DUNIX_ENABLED",
                "-c", str(src), "-o", str(obj)] + includes()
    r = subprocess.run(cmd, capture_output=True, text=True)
    return None if r.returncode == 0 else f"{src}: {r.stderr[-2000:]}"


def build_arch(target, arch):
    objs = []
    jobs = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count()) as pool:
        for src in sources():
            obj = BUILD / arch / (str(src.relative_to(HERE)).replace("/", "__") + ".o")
            objs.append(obj)
            jobs.append(pool.submit(compile_one, src, obj, target))
        errors = [e for e in (j.result() for j in jobs) if e]
    if errors:
        print("\n".join(errors[:5]))
        sys.exit(1)
    if "ios" in target:
        # iOS links extensions into the app itself: a static library.
        lib = BUILD / arch / "libmeltiew_luau.a"
        lib.unlink(missing_ok=True)
        subprocess.run(["llvm-ar", "rcs", str(lib)] + [str(o) for o in objs], check=True)
        return lib
    lib = BUILD / arch / "libmeltiew_luau.dylib"
    # dead_strip drops the godot-cpp classes nothing uses; -x the local symbols.
    cmd = ["zig", "c++", "-target", target, "-shared", "-o", str(lib)] + [str(o) for o in objs] + \
          ["-Wl,-install_name,@rpath/libmeltiew_luau.macos.dylib", "-Wl,-dead_strip", "-Wl,-x",
           # room in the header for the signature Godot's export adds (both slices)
           "-Wl,-headerpad,0x4000"]
    subprocess.run(cmd, check=True)
    return lib


def main():
    platform = sys.argv[1] if len(sys.argv) > 1 else "macos"
    libs = [build_arch(t, a) for t, a in TARGETS[platform]]
    OUT.mkdir(parents=True, exist_ok=True)
    if platform == "ios":
        out = OUT / "libmeltiew_luau.ios.arm64.a"
        out.write_bytes(libs[0].read_bytes())
        print("built", out)
        return
    out = OUT / "libmeltiew_luau.macos.dylib"
    subprocess.run(["llvm-lipo", "-create", *map(str, libs), "-output", str(out)], check=True)
    print("built", out)


if __name__ == "__main__":
    main()
