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
