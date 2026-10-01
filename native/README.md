# Native: Luau for Meltiew Studio

`core/` is a small sandboxed Luau VM (memory limit, script timeout, `__compile`)
shared by the game client and the game server. `godot/` wraps it as the `LuauVM`
GDExtension class used by GDScript.

Sources of Luau (tag 0.739) and godot-cpp (branch 4.5) go to `third_party/`:

    git clone --depth 1 --branch 0.739 https://github.com/luau-lang/luau third_party/luau
    git clone --depth 1 --branch 4.5 https://github.com/godotengine/godot-cpp third_party/godot-cpp
    scons platform=linux arch=x86_64 target=template_release disable_exceptions=no

Binaries land in `client/addons/meltiew_luau/bin/`.

Apple, from Linux: `build_apple.py macos` (zig) makes the universal dylib, and
`build_apple.py ios` the static library, with clang and the iPhoneOS SDK from Xcode's
.xip. `apple/build_ipa.py` then links and packs the whole iPhone app (Meltiew.ipa, for
SideStore/AltStore) without Xcode; how to get the SDK is at its top.
