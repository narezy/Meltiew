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
