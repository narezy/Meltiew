class_name StudioFiles
extends RefCounted
## Opening and saving files (images, .marp places) with the system dialog where
## there is one (desktop, Android), Godot's own dialog otherwise.


static func open_file(filters: Array, done: Callable) -> void:
	_dialog(false, "", filters, func(path: String):
		if path == "":
			return
		var f := FileAccess.open(path, FileAccess.READ)
		done.call(path, f.get_buffer(f.get_length()) if f else PackedByteArray()))


static func save_file(default_name: String, filters: Array, data: PackedByteArray, done: Callable = Callable()) -> void:
	_dialog(true, default_name, filters, func(path: String):
		if path == "":
			return
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
		if done.is_valid():
			done.call(path))


static func _dialog(saving: bool, default_name: String, filters: Array, done: Callable) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var mode := DisplayServer.FILE_DIALOG_MODE_SAVE_FILE if saving else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
		DisplayServer.file_dialog_show("", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), default_name, false, mode, PackedStringArray(filters),
			func(ok: bool, paths: PackedStringArray, _filter: int):
				done.call(paths[0] if ok and not paths.is_empty() else ""))
		return
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(filters)
	fd.current_file = default_name
	fd.use_native_dialog = false
	fd.size = Vector2i(900, 600)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(fd)
	fd.file_selected.connect(func(p):
		fd.queue_free()
		done.call(p))
	fd.canceled.connect(func():
		fd.queue_free()
		done.call(""))
	fd.popup_centered()
