extends Library

const NSTOOL := preload("res://plugins/yuzu/core/nstool.gd")

var home := OS.get_environment("HOME")
var yuzu_config_paths := [
	"/".join([home, ".config", "yuzu"]),
	"/".join([home, ".var", "app", "org.yuzu_emu.yuzu", "config", "yuzu"]),
]
var yuzu_data_paths := [
	"/".join([home, ".local", "share", "yuzu"]),
	"/".join([home, ".var", "app", "org.yuzu_emu.yuzu", "data", "yuzu"]),
]
var yuzu_config_path := find_path(yuzu_config_paths)
var yuzu_data_path := find_path(yuzu_data_paths)
var nstool: NSTOOL = NSTOOL.new()
var supported_ext := ["xci", "nsp"]


func _ready() -> void:
	if yuzu_data_path == "":
		logger.warn("No yuzu data directory was found")
		return
	logger.info("Found yuzu config directory: " + yuzu_config_path)
	logger.info("Found yuzu data directory: " + yuzu_data_path)

	# Ensure that keys exist
	var keys_path := "/".join([yuzu_data_path, "keys", "prod.keys"])
	if not FileAccess.file_exists(keys_path):
		logger.warn("No yuzu keys found in data directory")
		return
	nstool.set_keys_path(keys_path)
	logger.info("Found keys at: " + keys_path)
	
	# Ensure that nstools is installed
	if not nstool.is_installed():
		nstool.install(self)


func get_library_launch_items() -> Array:
	logger.info("Fetching library items")
	var launch_items := []
	if not nstool.is_installed():
		logger.warn("nstools is not installed")
		return launch_items
	if nstool.keys_path == "":
		logger.warn("No yuzu keys were discovered")
		return launch_items
	
	# Discover ROM paths
	var rom_paths := get_rom_paths()
	logger.debug("Discovered rom paths: " + str(rom_paths))
	
	# Discover the yuzu command to use
	var cmd_string := get_yuzu_command()
	if cmd_string == "":
		logger.error("Unable to discover yuzu installation")
		return launch_items
	var args := Array(cmd_string.split(" "))
	var command := args.pop_front() as String
	
	# Look for ROM files
	for roms_path in rom_paths:
		var files := DirAccess.get_files_at(roms_path)
		for file in files:
			var ext := file.split(".")[-1].to_lower()
			if not ext in supported_ext:
				continue
			var file_path := "/".join([roms_path, file])
			logger.debug("Discovered ROM: " + file_path)
			
			# Get info about the rom
			var info := nstool.get_info(file_path)
			if not "name" in info:
				continue
			
			# Create a library launch item for the game
			var launch_item := LibraryLaunchItem.new()
			launch_item.name = info["name"]
			launch_item.command = command
			launch_item.args = args.duplicate()
			launch_item.args.append(file_path)
			launch_item.installed = true
			launch_items.append(launch_item)
	
	return launch_items


## Tries to find the yuzu executable to use to launch games
func get_yuzu_command() -> String:
	var out := []
	if OS.execute("which", ["yuzu"], out) == OK:
		return out[0].strip_edges() + " -f -g"
	if has_flatpak_yuzu():
		#return "flatpak --user run --command=yuzu-cmd org.yuzu_emu.yuzu"
		return "flatpak --user run org.yuzu_emu.yuzu -f -g"
	return ""


## Returns true if the flatpak version of yuzu is installed
func has_flatpak_yuzu() -> bool:
	var out := []
	if OS.execute("flatpak",  ["--user", "list", "--columns=application"], out) != OK:
		return false
	var lines := out[0].split("\n") as PackedStringArray
	for line in lines:
		if line.strip_edges() == "org.yuzu_emu.yuzu":
			return true
	return false


## Returns the first path in the given paths that exists. Returns an empty string
## if not found.
func find_path(paths: PackedStringArray) -> String:
	for path in paths:
		if DirAccess.dir_exists_absolute(path):
			return path
	return ""


## Parses the yuzu config to get ROM directories
func get_rom_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	if yuzu_config_path == "":
		return paths
	var config_path := "/".join([yuzu_config_path, "qt-config.ini"])
	if not FileAccess.file_exists(config_path):
		logger.warn("Yuzu config does not exist at: " + config_path)
		return paths
		
	# Read the config
	var config := FileAccess.get_file_as_string(config_path)
	var lines := config.split("\n")
	for line in lines:
		line = line.strip_edges()
		if not line.begins_with("Path"):
			continue
		var parts := line.split("=")
		var key := parts[0]
		var value := parts[1]
		
		# Add any romsPaths
		if "romsPath" in key and not value in paths:
			paths.append(value)
		
		# Only look for gamedirs entries that are not SDMC, UserNAND, or SysNAND
		if not key.contains("gamedirs"):
			continue
		if not key.ends_with("path"):
			continue
		if value in ["SDMC", "UserNAND", "SysNAND"]:
			continue
		
		paths.append(value)
		
	return paths
