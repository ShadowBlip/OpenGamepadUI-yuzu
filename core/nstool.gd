extends Resource

enum FORMAT {
	UNKNOWN,
	XCI,
	NSP,
}

var home := OS.get_environment("HOME")
var bin_path := "/".join([home, ".local", "share", "opengamepadui", "bin"])
var nstool_path := "/".join([bin_path, "nstool"])
var nstool_url := "https://github.com/jakcron/nstool/releases/download/v1.7.0-r2/nstool-v1.7.0-ubuntu_x86_64.zip"
var keys_path: String
var installing := false
var logger := Log.get_logger("nstool", Log.LEVEL.INFO)


## Parse the given rom file
func get_info(path: String) -> Dictionary:
	var info := {}
	var format := detect_format(path)
	if format == FORMAT.UNKNOWN:
		logger.warn("Unknown ROM format for file: " + path)
		return info
	
	if format == FORMAT.NSP:
		info = get_nsp_info(path)
	if format == FORMAT.XCI:
		info = get_xci_info(path)
	
	return info


func get_nsp_info(path: String) -> Dictionary:
	# Find the cnmt metadata archive
	var file_tree_lines := file_tree(path).split("\n")
	var cnmt_nca_file: String
	for line in file_tree_lines:
		if line.contains("cnmt.nca"):
			cnmt_nca_file = line.strip_edges()
	if cnmt_nca_file == "":
		logger.warn("Unable to find cnmt.nca archive")
		return {}
	logger.debug("Found cnmt.nca file: '{0}'".format([cnmt_nca_file]))
	
	# Extract the cnmt archive
	var cnmt_nca_out_path := "/".join(["/tmp", cnmt_nca_file])
	if extract(path, "/" + cnmt_nca_file, cnmt_nca_out_path) != OK:
		logger.warn("Unable to extract cnmt.nca archive")
		return {}
	
	# List the contents of the cnmt archive
	var cnmt_tree_lines := file_tree(cnmt_nca_out_path).split("\n")
	var cnmt_file: String
	for line in cnmt_tree_lines:
		if not line.strip_edges().ends_with(".cnmt"):
			continue
		cnmt_file = line.strip_edges()
	if cnmt_file == "":
		logger.warn("Unable to find cnmt file")
		return {}
	logger.debug("Found cnmt file: '{0}'".format([cnmt_file]))

	# Extract the cnmt file
	var cnmt_out_path := "/".join(["/tmp", cnmt_file])
	if extract(cnmt_nca_out_path, "/0/" + cnmt_file, cnmt_out_path) != OK:
		logger.warn("Failed to extract cnmt file")
		return {}
	
	# Read the cnmt file to fine the Control archive
	var control_file_id := find_control_id(cnmt_out_path)
	if control_file_id == "":
		logger.warn("Unable to find control file id")
		return {}
	logger.debug("Found control file id: " + control_file_id)
	
	# Extract the control archive from the original archive
	var control_archive := control_file_id + ".nca"
	var control_nca_out_path := "/".join(["/tmp", control_archive])
	if extract(path, "/" + control_archive, control_nca_out_path) != OK:
		logger.warn("Failed to extract control archive")
		return {}
	
	# Extract the control.nacp file
	var control_out_path := control_file_id + ".control.nacp"
	if extract(control_nca_out_path, "/0/control.nacp", control_out_path) != OK:
		logger.warn("Failed to extract control.nacp file")
		return {}
	
	# Finally, read the control.nacp file
	return parse_app_info(control_out_path)


func get_xci_info(path: String) -> Dictionary:
	# Find the cnmt metadata archive
	var file_tree_lines := file_tree(path).split("\n")
	var cnmt_nca_file: String
	var secure_section_found := false
	for line in file_tree_lines:
		if line.contains("secure/"):
			secure_section_found = true
			continue
		if not secure_section_found:
			continue
		if line.contains("cnmt.nca"):
			cnmt_nca_file = line.strip_edges()
			break
	if cnmt_nca_file == "":
		logger.warn("Unable to find cnmt.nca archive")
		return {}
	logger.debug("Found cnmt.nca file: '{0}'".format([cnmt_nca_file]))
	
	# Extract the cnmt archive
	var cnmt_nca_out_path := "/".join(["/tmp", cnmt_nca_file])
	if extract(path, "/secure/" + cnmt_nca_file, cnmt_nca_out_path) != OK:
		logger.warn("Unable to extract cnmt.nca archive")
		return {}
	
	# List the contents of the cnmt archive
	var cnmt_tree_lines := file_tree(cnmt_nca_out_path).split("\n")
	var cnmt_file: String
	for line in cnmt_tree_lines:
		if not line.strip_edges().ends_with(".cnmt"):
			continue
		cnmt_file = line.strip_edges()
	if cnmt_file == "":
		logger.warn("Unable to find cnmt file")
		return {}
	logger.debug("Found cnmt file: '{0}'".format([cnmt_file]))

	# Extract the cnmt file
	var cnmt_out_path := "/".join(["/tmp", cnmt_file])
	if extract(cnmt_nca_out_path, "/0/" + cnmt_file, cnmt_out_path) != OK:
		logger.warn("Failed to extract cnmt file")
		return {}
	
	# Read the cnmt file to fine the Control archive
	var control_file_id := find_control_id(cnmt_out_path)
	if control_file_id == "":
		logger.warn("Unable to find control file id")
		return {}
	logger.debug("Found control file id: " + control_file_id)
	
	# Extract the control archive from the original archive
	var control_archive := control_file_id + ".nca"
	var control_nca_out_path := "/".join(["/tmp", control_archive])
	if extract(path, "/secure/" + control_archive, control_nca_out_path) != OK:
		logger.warn("Failed to extract control archive")
		return {}
	
	# Extract the control.nacp file
	var control_out_path := control_file_id + ".control.nacp"
	if extract(control_nca_out_path, "/0/control.nacp", control_out_path) != OK:
		logger.warn("Failed to extract control.nacp file")
		return {}
	
	# Finally, read the control.nacp file
	return parse_app_info(control_out_path)


## Reads app info from the given control.nacp file.
func parse_app_info(control_path: String) -> Dictionary:
	var info := {}
	var ret := _exec([control_path])
	var lines := ret[0].split("\n") as PackedStringArray
	for line in lines:
		if not "Name:" in line:
			continue
		line = line.replace("Name:", "")
		var name := line.strip_edges()
		info["name"] = name
		break
	
	return info

## Find the ID of the Control archive from a cnmt metadata file
func find_control_id(cnmt_path: String) -> String:
	var cnmt_output := _exec([cnmt_path])
	var lines := cnmt_output[0].split("\n") as PackedStringArray
	
	var id: String
	var found_control_section := false
	for line in lines:
		if line.contains("Type:") and line.contains("Control"):
			found_control_section = true
		if not found_control_section:
			continue
		if not line.contains("Id:"):
			continue
		var parts := line.split(":")
		id = parts[-1].strip_edges()
		break

	return id


func file_tree(path: String) -> String:
	var ret := _exec(["--fstree", path])
	return ret[0]


func extract(path: String, in_archive_path: String, output_file_path: String) -> int:
	logger.debug("Extracting '{0}' from archive {1} to: {2}".format([in_archive_path, path, output_file_path]))
	var ret := _exec(["-x", in_archive_path, output_file_path, path])
	return ret[-1]


## Execute nstool with the set keyfile. Returns an array with [output, code]
func _exec(args: PackedStringArray) -> Array:
	var cmd := nstool_path
	var arguments := PackedStringArray(["-k", keys_path])
	arguments.append_array(args)
	
	logger.debug("Executing: " + cmd + " " + " ".join(arguments))
	var output := []
	var code := OS.execute(cmd, arguments, output)
	output.append(code)
	logger.debug("Command exited with code: " + str(code))
	return output


## Use the given keys path
func set_keys_path(path: String) -> void:
	keys_path = path


## Returns whether or not nstool is installed
func is_installed() -> bool:
	return FileAccess.file_exists(nstool_path)


## Returns the detected ROM format
func detect_format(path: String) -> FORMAT:
	var ext := path.split(".")[-1].to_lower()
	if ext == "xci":
		return FORMAT.XCI
	if ext == "nsp":
		return FORMAT.NSP
	return FORMAT.UNKNOWN


## Install nstools to the user directory to allow parsing of rom files.
func install(parent: Node) -> bool:
	if installing:
		return true
	installing = true
	logger.info("Installing nstools")
	# Build the request
	var http: HTTPRequest = HTTPRequest.new()
	parent.add_child(http)
	if http.request(nstool_url) != OK:
		logger.error("Error downloading nstools: " + nstool_url)
		parent.remove_child(http)
		http.queue_free()
		installing = false
		return false
		
	# Wait for the request signal to complete
	# result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray
	var args: Array = await http.request_completed
	var result: int = args[0]
	var response_code: int = args[1]
	var body: PackedByteArray = args[3]
	parent.remove_child(http)
	http.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		logger.error("nstools couldn't be downloaded: " + nstool_url)
		installing = false
		return false

	# Save the archive
	var archive_path := "/tmp/nstools.zip"
	var file := FileAccess.open(archive_path, FileAccess.WRITE_READ)
	file.store_buffer(body)
	file.close()
	logger.info("nstools downloaded successfully")

	# Read the ZIP archive
	var reader := ZIPReader.new()
	if reader.open(archive_path) != OK:
		logger.error("Unable to read nstools zip file")
		installing = false
		return false
	
	# Ensure the bin directory exists
	if DirAccess.make_dir_recursive_absolute(bin_path) != OK:
		logger.error("Unable to create bin directory: " + bin_path)
		installing = false
		return false
	
	# Extract the zip
	for zipped_file in reader.get_files():
		if zipped_file != "nstool":
			continue
		var dest_path := nstool_path
		logger.debug("Extracting file {0} to {1}".format([zipped_file, dest_path]))
		var content := reader.read_file(zipped_file)
		var target_file := FileAccess.open(dest_path, FileAccess.WRITE_READ)
		target_file.store_buffer(content)
		target_file.close()
		OS.execute("chmod", ["+x", dest_path])
	
	installing = false
	if not FileAccess.file_exists(nstool_path):
		return false
	
	logger.debug("Successfully installed nstools")
	return true
