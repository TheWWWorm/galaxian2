extends SceneTree
const Importer=preload("res://src/content/dmg_import.gd")
var failures:=0
var checks:=0

class Worker extends "res://src/content/dmg_import.gd":
	var running:=false
	var state:={"state":"working","message":"Preparing textures"}
	var terminal:={}
	var calls:=[]
	func _worker_running() -> bool:
		calls.append("process")
		if not running and not terminal.is_empty():state=terminal
		return running
	func _read_status() -> Dictionary:
		calls.append("status")
		return state

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var directory:=OS.get_environment("GOF2_MENU_TEST_DIRECTORY")
	if directory.is_empty() or not preload("res://tests/fixtures/convoy_station_scenario.gd").private_path(directory+"/installation.json"):
		check(false,"Supply a private import test directory");finish();return
	DirAccess.make_dir_recursive_absolute(directory)
	var receipt:=directory.path_join("installation.json")
	var identity:="1".repeat(64)
	var record:={"schema":1,"format":"mac-dmg","source_sha256":identity,"base_content_id":identity,"binding_id":identity,"visual_id":identity}
	for kind in ["content","bindings","visuals"]:record[kind]=kind+"/"+identity
	var file:=FileAccess.open(receipt,FileAccess.WRITE);file.store_string(JSON.stringify(record));file.close()
	for mode in ["success","running","cancelled","failed"]:
		var worker:=Worker.new()
		worker._pid=123;worker._status_path=directory.path_join("status.json")
		worker._cancelled=mode=="cancelled";worker.running=mode=="running"
		worker.terminal={"state":"ready","receipt":receipt,"message":"Ready"} if mode!="failed" else {"state":"failed","message":"Unsupported image"}
		var results:=[]
		worker.finished.connect(func(ok,path,message):results.append({"ok":ok,"path":path,"message":message}))
		worker._process(0.1)
		check(worker.calls.is_empty(),"Progress polling should not contend with every rendered frame")
		worker._process(0.1)
		check(worker.calls==["process","status"],"Read final status after checking process exit")
		if mode=="running":
			check(results.is_empty() and worker.busy(),"Do not finish a running helper")
			worker.running=false;worker._process(0.2)
		check(results.size()==1 and not worker.busy(),"A stopped helper completes exactly once")
		check(results[0].ok==(mode in ["success","running"]),"Cancellation or failure must not activate content")
		if mode=="failed":check(results[0].message=="Unsupported image","Retain the helper's useful diagnostic")
		worker._process(1.0)
		check(results.size()==1,"A finished helper must not emit twice")
		worker.free()
	DirAccess.remove_absolute(receipt)
	finish()

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",message)

func finish() -> void:
	print("DMG completion: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
