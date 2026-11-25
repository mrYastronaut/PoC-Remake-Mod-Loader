class_name ModScripts
extends RefCounted
## Loads the scripts of active mods (mod.json "scripts"). Scripts are code: they run with the
## full power of the game, so they only load when the player allowed it in the Mods screen
## (mods/settings.json {"allow_scripts": true}, off by default).

const SETTINGS_FILE := "settings.json"
const MAX_SCRIPT_BYTES := 256 * 1024

## path -> {"mtime": int, "script": GDScript}
static var _cache := {}


static func _settings_path(storage_dir: String) -> String:
	return ModRegistry.mods_dir(storage_dir).path_join(SETTINGS_FILE)


static func allowed(storage_dir: String) -> bool:
	if storage_dir == "" or not FileAccess.file_exists(_settings_path(storage_dir)):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(_settings_path(storage_dir))) != OK or not json.data is Dictionary:
		return false
	return json.data.get("allow_scripts", false) == true


static func set_allowed(storage_dir: String, value: bool) -> bool:
	DirAccess.make_dir_recursive_absolute(ModRegistry.mods_dir(storage_dir))
	var file := FileAccess.open(_settings_path(storage_dir), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"allow_scripts": value}, "  "))
	file.close()
	return true


## [{"mod": id, "path": absolute path}] of the scripts of the active mods, in load order.
## Empty when scripts are not allowed.
static func active_scripts(storage_dir: String) -> Array:
	var out: Array = []
	if storage_dir == "" or not allowed(storage_dir):
		return out
	for mod: Dictionary in ModRegistry.active(storage_dir):
		for rel in mod["manifest"].get("scripts", []):
			out.append({"mod": str(mod["id"]), "path": str(mod["dir"]).path_join(str(rel))})
	return out


## Compiles a script file (cached by modification time) and creates an instance. null if it does
## not compile, is too big, or does not extend ModScript.
static func instantiate(path: String) -> ModScript:
	if not FileAccess.file_exists(path):
		push_warning("mods: script not found: " + path)
		return null
	var mtime := FileAccess.get_modified_time(path)
	var script: GDScript = null
	if _cache.has(path) and _cache[path]["mtime"] == mtime:
		script = _cache[path]["script"]
	else:
		var text := FileAccess.get_file_as_string(path)
		if text.length() > MAX_SCRIPT_BYTES:
			push_warning("mods: script too big: " + path)
			return null
		script = GDScript.new()
		script.source_code = text
		if script.reload() != OK:
			push_warning("mods: script does not compile: " + path)
			return null
		_cache[path] = {"mtime": mtime, "script": script}
	var instance: Variant = script.new()
	if not instance is ModScript:
		push_warning("mods: script does not extend ModScript: " + path)
		return null
	return instance
