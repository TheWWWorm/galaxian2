extends RefCounted
## Native station save files with checked staging and a previous viable record.
## Uses the same content isolation and backup approach as the Apache-2.0 GoF
## native engine; this format and state validation belong to Galaxy on Fire 2.
const Archive=preload("res://src/simulation/station_archive.gd")
const MAGIC="GOF2SAV1"
const HEADER_BYTES=40
const MAX_BYTES=8*1024*1024
var error:=""
var recovered_backup:=false

static func path_for(directory: String,bindings: RefCounted) -> String:
	if directory.is_empty() or not Archive.available(bindings):return ""
	return directory.path_join(bindings.base_content_id).path_join(bindings.binding_id).path_join("station.gof2save")

func save(path: String,station: RefCounted,bindings: RefCounted,cat: RefCounted,library: RefCounted,locations: RefCounted=null) -> bool:
	error="";recovered_backup=false
	var archive:=Archive.new();var document:=archive.capture(station,bindings,locations)
	if document.is_empty():return reject(archive.error)
	if archive.restore(bindings,cat,library,document)==null:return reject(archive.error)
	var bytes:=encode(document)
	if bytes.is_empty():return false
	if not _path_valid(path) or DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK:return reject("Cannot create the save directory")
	var previous:={}
	if FileAccess.file_exists(path):
		previous=read_document(path)
		if not previous.is_empty() and (previous.get("base_content_id")!=bindings.base_content_id or previous.get("binding_id")!=bindings.binding_id):return reject("Keep the existing save with its original content and gameplay bindings")
		if not previous.is_empty() and archive.restore(bindings,cat,library,previous)==null:previous={}
	error=""
	var staged:=path+".tmp"
	if not _write(staged,bytes):return false
	if read_document(staged)!=document:
		DirAccess.remove_absolute(staged)
		return reject("The staged save could not be verified; the previous save is unchanged")
	if not previous.is_empty():
		var backup:=path+".bak.tmp"
		if DirAccess.copy_absolute(path,backup)!=OK or read_document(backup)!=previous or DirAccess.rename_absolute(backup,path+".bak")!=OK:
			DirAccess.remove_absolute(staged);DirAccess.remove_absolute(backup)
			return reject("Could not preserve the previous save")
	if DirAccess.rename_absolute(staged,path)!=OK:
		DirAccess.remove_absolute(staged)
		return reject("Could not finish saving; the previous save is unchanged")
	error=""
	return true

func load_document(path: String,bindings: RefCounted,cat: RefCounted,library: RefCounted) -> Dictionary:
	error="";recovered_backup=false
	if not _path_valid(path):return failure("Choose a native save location")
	var first_error:=""
	for suffix in ["",".bak"]:
		var document:=read_document(path+suffix)
		if not document.is_empty():
			var archive:=Archive.new()
			if archive.restore(bindings,cat,library,document)!=null:
				error="";recovered_backup=not suffix.is_empty()
				return document
			error=archive.error
		if suffix.is_empty():first_error=error
	return failure(first_error if not first_error.is_empty() else "No viable saved station is available")

func encode(document: Dictionary) -> PackedByteArray:
	if not Archive.data_tree(document):reject("The save contains unsupported data");return PackedByteArray()
	var payload:=var_to_bytes(document)
	if payload.is_empty() or payload.size()>MAX_BYTES:reject("The save exceeds the supported file size");return PackedByteArray()
	var bytes:=MAGIC.to_ascii_buffer();bytes.append_array(_digest(payload));bytes.append_array(payload)
	return bytes

func read_document(path: String) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return failure("No readable station save is available")
	var size:=file.get_length()
	if size<=HEADER_BYTES or size>HEADER_BYTES+MAX_BYTES:file.close();return failure("The station save is truncated or oversized")
	var bytes:=file.get_buffer(size);file.close()
	if bytes.size()!=size or bytes.slice(0,8)!=MAGIC.to_ascii_buffer():return failure("This is not a supported Galaxy on Fire 2 remake save")
	var payload:=bytes.slice(HEADER_BYTES)
	if bytes.slice(8,HEADER_BYTES)!=_digest(payload):return failure("The station save is damaged")
	# The non-object decoder cannot instantiate scripts or resources from a file.
	var document: Variant=bytes_to_var(payload)
	if not document is Dictionary or not Archive.data_tree(document):return failure("The save contains unsupported data")
	return document

func _write(path: String,bytes: PackedByteArray) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return reject("Cannot write the staged station save")
	file.store_buffer(bytes);file.flush()
	var complete: bool=file.get_error()==OK and file.get_length()==bytes.size()
	file.close()
	if not complete:DirAccess.remove_absolute(path);return reject("The save write did not finish")
	return true

static func _path_valid(path: String) -> bool:
	return path.is_absolute_path() or path.begins_with("user://")

static func _digest(payload: PackedByteArray) -> PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(payload)
	return hash.finish()

func reject(message: String) -> bool:error=message;return false
func failure(message: String) -> Dictionary:error=message;return {}
