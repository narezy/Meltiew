@tool
extends EditorPlugin

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = DeepLinkExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class DeepLinkExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "MeltiewDeepLink"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	# The Gradle template's activity is swapped for ours (it asks Android for 90/120 Hz).
	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		var target := ProjectSettings.globalize_path("res://android/build/src/main/java/com/godot/game/GodotApp.java")
		if not FileAccess.file_exists(target):
			return
		var patched := FileAccess.get_file_as_string("res://addons/meltiew_export/android/GodotApp.java.txt")
		if patched != "" and FileAccess.get_file_as_string(target) != patched:
			var f := FileAccess.open(target, FileAccess.WRITE)
			f.store_string(patched)
			f.close()
		# Android TV: the banner on the home screen (the template's <application> gets it).
		var res := ProjectSettings.globalize_path("res://android/build/res/drawable-xhdpi")
		DirAccess.make_dir_recursive_absolute(res)
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://addons/meltiew_export/android/tv_banner.png"), res.path_join("tv_banner.png"))
		var manifest := ProjectSettings.globalize_path("res://android/build/src/main/AndroidManifest.xml")
		var xml := FileAccess.get_file_as_string(manifest)
		if xml != "" and not "android:banner" in xml:
			xml = xml.replace("<application\n", "<application\n        android:banner=\"@drawable/tv_banner\"\n")
			var m := FileAccess.open(manifest, FileAccess.WRITE)
			m.store_string(xml)
			m.close()

	# Standalone headsets: Pico starts the app in VR (not in a flat window) with these.
	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		var preset := get_export_preset()
		if preset == null or not "pico" in preset.get_custom_features():
			return ""
		return """
		<meta-data android:name="pvr.app.type" android:value="vr" />
		<meta-data android:name="pvr.sdk.version" android:value="OpenXR" />
"""

	# A TV has no touch screen and often no microphone: neither is required (stores would
	# hide the app from TVs otherwise). "show_in_android_tv" in the preset adds the TV launcher.
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return """
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
    <uses-feature android:name="android.hardware.microphone" android:required="false" />
    <uses-feature android:name="android.software.leanback" android:required="false" />
"""

	# Lets meltiew://play links (and intent:// URLs from the website) open the game.
	func _get_android_manifest_activity_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return """
			<intent-filter>
				<action android:name="android.intent.action.VIEW" />
				<category android:name="android.intent.category.DEFAULT" />
				<category android:name="android.intent.category.BROWSABLE" />
				<data android:scheme="meltiew" />
			</intent-filter>
"""
