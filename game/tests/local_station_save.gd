extends "res://tests/mido_application.gd"
## Actual training return, drill exchange and local journeys produce the saves.
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const PrivatePath=preload("res://tests/fixtures/convoy_station_scenario.gd")
const SavedStationSession=preload("res://src/presentation/station_session.gd")
var save_directory:=""
var saved_cursors:=[]

func after_training_application_reload(args: PackedStringArray):
	save_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if save_directory.is_empty() or not PrivatePath.private_path(save_directory+"/save.bin"):check(false,"Set a private local save directory");return
	host.enable_saves(save_directory.path_join("automatic"))
	await super.after_training_application_reload(args)

func key(code: int):
	super.key(code)
	if save_directory.is_empty() or not is_instance_valid(host) or not host.session is SavedStationSession:return
	var state: Dictionary=host.session.station_owner().snapshot();var cursor: int=state.campaign_cursor
	if cursor not in [10,11,12] or saved_cursors.has(cursor) or not host._can_save_station():return
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	var file:=SaveFile.new();var archive:=Archive.new()
	var original:=archive.capture(host.session.station_owner(),bindings,host.session.location_owner())
	var restored:=archive.restore(bindings,cat,lib,original)
	if restored==null:check(false,"Local save "+str(cursor)+": "+archive.error);return
	check(restored.snapshot()==state,"The local checkpoint changed its earned station")
	check(archive.restored_locations.snapshot()==host.session.location_owner().snapshot(),"The local checkpoint regenerated its contacts")
	check(file.load_document(host.station_save_path(),bindings,cat,lib)==original,"The local acknowledgement did not autosave: "+file.error)
	var path:=SaveFile.path_for(save_directory.path_join(str(cursor)),bindings)
	if not file.save(path,restored,bindings,cat,lib,archive.restored_locations):check(false,file.error);return
	saved_cursors.append(cursor)

func after_lounge_application(args: PackedStringArray):
	await super.after_lounge_application(args)
	check(saved_cursors==[10,11,12],"The local path did not save every acknowledged visit")
	if failures:return
	for cursor in saved_cursors:
		host.enable_saves(save_directory.path_join(str(cursor)))
		root.grab_focus();host._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		if not host.load_station(now_us):check(false,host._save_notice.text);return
		var state: Dictionary=host.session.snapshot()
		host.enable_saves(save_directory.path_join("resumed-"+str(cursor)))
		check(state.campaign_cursor==cursor and state.equipment.prototype_drill_replaced,"The local load lost its exchanged drill or mission")
		check(not state.dialogue.visible and host.session.audio.snapshot().get("history",[]).is_empty(),"The local load replayed acknowledged speech")
		if args.size()==4:await capture(args[3],"saved-local-"+str(cursor))
		check(host.request_departure(),host.session.error)
		check(host.enter_first_flight(now_us,4096,1789100000),host.status.text)
		check(host.session.snapshot().campaign_cursor==cursor,"A saved local station selected the wrong journey")
