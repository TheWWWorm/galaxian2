extends Node
## Asynchronous, cancellable import-time helper. No original program is run.
signal progress(message: String)
signal finished(success: bool,receipt: String,message: String)
const Library=preload("res://src/content/library.gd")
var error:=""
var _pid:=-1
var _status_path:=""
var _cancel_path:=""
var _last_message:=""
var _cancelled:=false
var _poll_elapsed:=0.0

static func read_receipt(path: String) -> Dictionary:
	if not path.is_absolute_path() or path.get_file()!="installation.json":return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>32768:return {}
	var record: Variant=JSON.parse_string(file.get_as_text());file.close()
	if not record is Dictionary or record.get("schema")!=1 or record.get("format")!="mac-dmg" or not Library.valid_hash(record.get("source_sha256")):return {}
	for pair in [["content","base_content_id"],["bindings","binding_id"],["visuals","visual_id"]]:
		if not Library.valid_hash(record.get(pair[1])) or record.get(pair[0])!=pair[0]+"/"+record[pair[1]]:return {}
	return record

func busy() -> bool:return _pid>=0

func start(source: String,directory: String) -> bool:
	error=""
	if busy():return reject("A Mac import is already running")
	if not source.is_absolute_path() or source.get_extension().to_lower()!="dmg" or not FileAccess.file_exists(source):return reject("Choose your Galaxy on Fire 2 Full HD Mac .dmg")
	var installation:=OS.get_executable_path().get_base_dir()
	if OS.get_name()=="macOS":installation=installation.get_base_dir().path_join("Resources")
	var bundled:=installation.path_join("importer")
	var helper:=bundled.path_join("tools/import_game.py")
	if not FileAccess.file_exists(helper):helper=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("tools/import_game.py")
	if not FileAccess.file_exists(helper):return reject("The DMG import helper is missing from this engine installation")
	var jobs:=directory.path_join("import-jobs")
	if DirAccess.make_dir_recursive_absolute(jobs)!=OK:return reject("Could not create the import progress folder")
	var job:=str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())
	_status_path=jobs.path_join(job+".json");_cancel_path=jobs.path_join(job+".cancel")
	var python:=OS.get_environment("GOF2_IMPORT_PYTHON")
	var bundled_python:=bundled.path_join("python/python.exe" if OS.get_name()=="Windows" else "python/bin/python3")
	if python.is_empty() and FileAccess.file_exists(bundled_python):python=bundled_python
	if python.is_empty():python="python" if OS.get_name()=="Windows" else "python3"
	var arguments:=PackedStringArray([helper,source,"--store",directory.path_join("imports"),"--status",_status_path,"--cancel-file",_cancel_path])
	if python==bundled_python:arguments=PackedStringArray(["-E","-s","-B"])+arguments
	_pid=OS.create_process(python,arguments)
	if _pid<0:return reject("Could not start the DMG importer. Extract the complete download, including its importer folder.")
	_cancelled=false;_poll_elapsed=0.2;_last_message="Reading your Mac disk image";progress.emit(_last_message);set_process(true);return true

func cancel() -> void:
	if not busy() or _cancelled:return
	var file:=FileAccess.open(_cancel_path,FileAccess.WRITE)
	if file==null:reject("Could not request import cancellation");return
	file.store_string("cancel\n");file.close();_cancelled=true;progress.emit("Cancelling import…")

func _worker_running() -> bool:return OS.is_process_running(_pid)

func _read_status() -> Dictionary:
	var state:={};var file:=FileAccess.open(_status_path,FileAccess.READ)
	if file!=null:
		if file.get_length()<=32768:
			var decoded: Variant=JSON.parse_string(file.get_as_text())
			if decoded is Dictionary:state=decoded
		file.close()
	return state

func _process(delta: float) -> void:
	if not busy():return
	_poll_elapsed+=delta
	if _poll_elapsed<0.2:return
	_poll_elapsed=0.0
	# Observe process exit before reading its final, atomically replaced status.
	# Reading first could retain "working" when the helper finishes between the
	# read and the process check, misreporting a successful import as a failure.
	var running:=_worker_running()
	var state:=_read_status()
	var message: String=str(state.get("message",""))
	if not _cancelled and not message.is_empty() and message!=_last_message:_last_message=message;progress.emit(message)
	if running:return
	_pid=-1;set_process(false)
	var receipt: String=str(state.get("receipt",""))
	var accepted: bool=not _cancelled and state.get("state")=="ready" and not read_receipt(receipt).is_empty()
	if _cancelled:message="Import cancelled; the previous game and saves are unchanged"
	if not accepted:error=message if not message.is_empty() else "The DMG importer stopped before finishing"
	finished.emit(accepted,receipt,error)

func _exit_tree() -> void:cancel()
func reject(message: String) -> bool:error=message;return false
