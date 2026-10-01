#!/usr/bin/env python3
"""Builds Meltiew.ipa for sideloading (SideStore, AltStore and the like) on Linux, with no
Mac and no Xcode: Godot exports the Xcode project, then this links the app itself with
clang + ld64.lld against Apple's iPhoneOS SDK and packs the bundle. The sideloading app
signs it with the user's own certificate.

One-time setup (the SDK comes from Xcode's .xip, which Apple gives to any Apple ID):
    bsdtar -xOf Xcode.xip Content | python3 pbzx.py | python3 cpio_pick.py scan  'iPhoneOS\\.platform/Developer/SDKs/' inodes.json
    bsdtar -xOf Xcode.xip Content | python3 pbzx.py | python3 cpio_pick.py extract 'iPhoneOS\\.platform/Developer/SDKs/' inodes.json
    cp -al .../iPhoneOS.sdk iPhoneOS-lld.sdk && python3 tbd_arm64.py iPhoneOS-lld.sdk
    IOS_SDK=.../iPhoneOS-lld.sdk python3 native/build_apple.py ios      # the Luau library

Then:
    IOS_SDK=.../iPhoneOS-lld.sdk python3 native/apple/build_ipa.py      # client/export/Meltiew.ipa

What Xcode would do and this can't (no actool/ibtool): icons go in as loose PNGs and the
launch screen is a plain UILaunchScreen instead of the storyboard.
"""
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client"
OUT = CLIENT / "export" / "ios"
BUILD = OUT / "build"
GODOT = os.environ.get("GODOT", str(Path.home() / ".zcode/workspace/default/tools/Godot_v4.7.2-stable_linux.x86_64"))
SDK = os.environ.get("IOS_SDK") or sys.exit("IOS_SDK: the iPhoneOS SDK copy made with tbd_arm64.py")
NAME = "Meltiew"

# What compiler-rt would give the app (there's none for Apple on Linux): @available checks.
COMPAT_C = r"""
#include <stdbool.h>
#include <stdint.h>

typedef struct { uint32_t platform; uint32_t version; } dyld_build_version_t;
extern bool _availability_version_check(uint32_t count, dyld_build_version_t versions[]);

int32_t __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t subminor) {
	dyld_build_version_t v = { platform, (major << 16) | ((minor & 0xff) << 8) | (subminor & 0xff) };
	return _availability_version_check(1, &v);
}

int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor) {
	return __isPlatformVersionAtLeast(2 /* iOS */, major, minor, subminor);
}
"""

# Loose icons (no asset catalog): file stem -> the exported icon it's made from.
ICONS = {
    "AppIcon60x60@2x.png": "Icon-120.png",
    "AppIcon60x60@3x.png": "Icon-180.png",
    "AppIcon76x76@2x~ipad.png": "Icon-152.png",
    "AppIcon83.5x83.5@2x~ipad.png": "Icon-167.png",
}


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        sys.exit(f"{cmd[0]} failed:\n{r.stdout[-3000:]}\n{r.stderr[-3000:]}")
    return r


def export_project():
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    # The preset has export_project_only: Godot writes the Xcode project and stops.
    run([GODOT, "--headless", "--path", str(CLIENT), "--export-release", "iOS", str(OUT / f"{NAME}.ipa")])
    if not (OUT / f"{NAME}.pck").exists():
        sys.exit("Godot didn't export the project")


def settings():
    pbx = (OUT / f"{NAME}.xcodeproj" / "project.pbxproj").read_text()
    get = lambda k: re.search(rf"\b{k} = \"?([^\";]+)\"?;", pbx).group(1).strip()
    return {k: get(k) for k in ["PRODUCT_BUNDLE_IDENTIFIER", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION",
                                "IPHONEOS_DEPLOYMENT_TARGET", "INFOPLIST_KEY_CFBundleDisplayName"]}


def link(cfg):
    BUILD.mkdir(exist_ok=True)
    target = ["-target", f"arm64-apple-ios{cfg['IPHONEOS_DEPLOYMENT_TARGET']}", "-isysroot", SDK]
    # dummy.cpp is Godot's: it registers the GDExtension entry points of static libraries.
    run(["clang++", *target, "-std=c++17", "-O2", "-c", str(OUT / NAME / "dummy.cpp"), "-o", str(BUILD / "dummy.o")])
    (BUILD / "compat.c").write_text(COMPAT_C)
    run(["clang", *target, "-O2", "-c", str(BUILD / "compat.c"), "-o", str(BUILD / "compat.o")])
    exe = BUILD / NAME
    libs = [OUT / f"{NAME}.xcframework/ios-arm64/libgodot.a", OUT / "MoltenVK.xcframework/ios-arm64/libMoltenVK.a"]
    libs += sorted((OUT / NAME).rglob("*.ios.arm64.a"))  # GDExtensions (Luau)
    run(["clang++", *target, "-fuse-ld=lld", "-o", str(exe), str(BUILD / "dummy.o"), str(BUILD / "compat.o"),
         *map(str, libs), f"-L{SDK}/usr/lib/swift", "-lc++",
         "-Wl,-dead_strip", "-Wl,-x", "-Wl,-adhoc_codesign",
         "-Wl,-rpath,/usr/lib/swift", "-Wl,-rpath,@executable_path/Frameworks",
         # As in Godot's Xcode project: the extension's entry point may be looked up at run time.
         "-Wl,-U,_meltiew_luau_init",
         # Swift back-deployment shims for runtimes older than the deployment target: not needed.
         "-Wl,-U,__swift_FORCE_LOAD_$_swiftCompatibility56",
         "-Wl,-U,__swift_FORCE_LOAD_$_swiftCompatibilityConcurrency",
         # A private framework the objects ask for: ld64 drops it, and it only exists since
         # iOS 18. Its symbols come through SwiftUI, which re-exports it.
         "-Wl,--ignore-auto-link-option=SwiftUICore"])
    return exe


def info_plist(cfg):
    text = (OUT / NAME / f"{NAME}-Info.plist").read_text()
    subs = {"EXECUTABLE_NAME": NAME, "PRODUCT_NAME": NAME, **cfg}
    text = re.sub(r"\$\((\w+)\)", lambda m: subs.get(m.group(1), m.group(0)), text)
    info = plistlib.loads(text.encode())
    sdk = json.loads((Path(SDK) / "SDKSettings.json").read_text())
    info.pop("UILaunchStoryboardName", None)
    info["UILaunchScreen"] = {}
    info["CFBundleIcons"] = {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60"]}}
    info["CFBundleIcons~ipad"] = {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60", "AppIcon76x76", "AppIcon83.5x83.5"]}}
    info.update({
        "MinimumOSVersion": cfg["IPHONEOS_DEPLOYMENT_TARGET"],
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "UIDeviceFamily": [1, 2],
        "DTPlatformName": "iphoneos",
        "DTPlatformVersion": sdk["Version"],
        "DTSDKName": f"iphoneos{sdk['Version']}",
    })
    return info


def bundle(exe, cfg):
    app = BUILD / "Payload" / f"{NAME}.app"
    shutil.rmtree(app.parent, ignore_errors=True)
    app.mkdir(parents=True)
    shutil.copy2(exe, app / NAME)
    shutil.copy2(OUT / f"{NAME}.pck", app / f"{NAME}.pck")
    shutil.copy2(OUT / "PrivacyInfo.xcprivacy", app / "PrivacyInfo.xcprivacy")
    shutil.copytree(OUT / NAME / "en.lproj", app / "en.lproj")
    icons = OUT / NAME / "Images.xcassets" / "AppIcon.appiconset"
    for dst, src in ICONS.items():
        shutil.copy2(icons / src, app / dst)
    (app / "Info.plist").write_bytes(plistlib.dumps(info_plist(cfg), fmt=plistlib.FMT_BINARY))
    (app / "PkgInfo").write_text("APPL????")

    ipa = CLIENT / "export" / f"{NAME}.ipa"
    ipa.unlink(missing_ok=True)
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in [app.parent, *sorted(app.parent.rglob("*"))]:
            arc = str(p.relative_to(BUILD))
            if p.is_dir():
                z.mkdir(arc)  # some installers want the folders listed too
                continue
            zi = zipfile.ZipInfo.from_file(p, arc)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o755 if p.name == NAME else 0o644) << 16
            z.writestr(zi, p.read_bytes())
    return ipa


def main():
    export_project()
    cfg = settings()
    exe = link(cfg)
    ipa = bundle(exe, cfg)
    print(f"built {ipa} ({ipa.stat().st_size // (1 << 20)} MB), {cfg['MARKETING_VERSION']} ({cfg['CURRENT_PROJECT_VERSION']})")


if __name__ == "__main__":
    main()
