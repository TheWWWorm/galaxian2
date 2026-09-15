extends "res://tests/alioth_return.gd"
## Actual Alioth battle/return and final acknowledgement create the first save.
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Archive=preload("res://src/simulation/station_archive.gd")

func prepare_alioth_flight(station: RefCounted) -> Node3D:
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not AliothCheckpoint.private_path(directory+"/save.bin"):
		check(false,"Set a private save-test directory");return null
	var live: Node3D=await super.prepare_alioth_flight(station)
	if live==null:return null
	app.enable_saves(directory.path_join(str(Time.get_ticks_usec())))
	check(not FileAccess.file_exists(app.station_save_path()),"The unlock diagnostic already has a saved station")
	return live

func after_alioth_flight(live: Node3D,frame: RefCounted,station: RefCounted) -> void:
	await super.after_alioth_flight(live,frame,station)
	if failures:return
	var file:=SaveFile.new();var expected:=Archive.new().capture(app.session.station_owner(),definitions)
	check(not expected.is_empty(),"The acknowledged unlock has no supported save")
	check(file.load_document(app.station_save_path(),definitions,catalogue,source)==expected,"The final original acknowledgement did not save the earned unlock: "+file.error)
	check(app._save_button.visible and not app._save_button.disabled and app._load_button.visible,"The earned unlock omitted Save or Load")
	var before: Dictionary=app.session.station_owner().snapshot()
	resume_application_focus()
	check(app.load_station(now_us) and app.session.station_owner().snapshot()==before,"Reloading the first autosave changed the earned opening: "+app._save_notice.text)
