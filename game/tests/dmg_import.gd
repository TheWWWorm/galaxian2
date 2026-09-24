extends SceneTree
const Importer=preload("res://src/content/dmg_import.gd")
const Frontend=preload("res://src/presentation/player_frontend.gd")
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
	var app_path:=directory.path_join("Renamed.app")
	DirAccess.make_dir_recursive_absolute(app_path.path_join("Contents"))
	var info:=FileAccess.open(app_path.path_join("Contents/Info.plist"),FileAccess.WRITE);info.store_string("synthetic picker input");info.close()
	check(Importer.valid_source(app_path),"The player entry must accept an extracted Mac app directory")
	check(not Importer.valid_source(directory) and not Importer.valid_source("relative.app"),"Do not accept parent or relative directories as apps")
	var frontend:=Frontend.new();root.add_child(frontend)
	check(frontend._picker.file_mode==FileDialog.FILE_MODE_OPEN_ANY,"Use one picker for disk images and application folders")
	check(frontend._picker.file_selected.is_connected(frontend._picked) and frontend._picker.dir_selected.is_connected(frontend._picked),"Both picker selections must enter the same importer")
	frontend.free()
	var receipt:=directory.path_join("installation.json")
	var identity:="1".repeat(64)
	var record:={"schema":1,"format":"mac-dmg","source_sha256":identity,"base_content_id":identity,"binding_id":identity,"visual_id":identity}
	for kind in ["content","bindings","visuals"]:record[kind]=kind+"/"+identity
	var file:=FileAccess.open(receipt,FileAccess.WRITE);file.store_string(JSON.stringify(record));file.close()
	record.format="mac-app";file=FileAccess.open(receipt,FileAccess.WRITE);file.store_string(JSON.stringify(record));file.close()
	check(not Importer.read_receipt(receipt).is_empty(),"Accept the new app receipt without rejecting existing disk-image receipts")
	record.format="mac-dmg";file=FileAccess.open(receipt,FileAccess.WRITE);file.store_string(JSON.stringify(record));file.close()
	check(not Importer.read_receipt(receipt).is_empty(),"Existing disk-image receipts remain valid")
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
	DirAccess.remove_absolute(app_path.path_join("Contents/Info.plist"));DirAccess.remove_absolute(app_path.path_join("Contents"));DirAccess.remove_absolute(app_path)
	finish()

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",message)

func finish() -> void:
	print("DMG completion: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
