extends "res://tests/alioth_return.gd"
## Four earned jobs and the actual convoy/Alioth path reload the pre-departure
## files. Original source-seeded contacts and disclosed combat diagnostics remain.
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
var save_directory:=""
var reloaded_cursors:=[]
var saved_cases:=0
var arriving:=false
var resumed_alioth:=false

func _initialize() -> void:
	if not OS.get_environment("GOF2_SOURCE_SAVE").is_empty():call_deferred("run_native_resume")
	else:super._initialize()

func run_native_resume() -> void:
	var args:=OS.get_cmdline_user_args();root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	save_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if args.size()!=3 or save_directory.is_empty() or not AliothCheckpoint.private_path(save_directory+"/save.bin"):check(false,"Expected content and a private resume directory");quit(1);return
	source=load("res://src/content/library.gd").new();definitions=load("res://src/content/resource_bindings.gd").new();catalogue=load("res://src/content/catalogues.gd").new();visual=Visuals.new()
	if not source.open(args[0]) or not definitions.open(args[1],source.manifest) or not catalogue.open(source) or not source.select_language("gb") or not visual.open(args[2],source.manifest):check(false,source.error+definitions.error+catalogue.error+visual.error);quit(1);return
	var path:=SaveFile.path_for(save_directory.path_join("automatic"),definitions)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if DirAccess.copy_absolute(OS.get_environment("GOF2_SOURCE_SAVE"),path)!=OK:check(false,"Could not copy the earned native checkpoint");quit(1);return
	app=Host.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.set_context(source,definitions,visual);app.set_process(false);app.enable_saves(save_directory.path_join("automatic"))
	resume_application_focus()
	if not app.load_station(now_us):check(false,app._save_notice.text);quit(1);return
	if app.session.snapshot().campaign_cursor!=16:check(false,"Expected the earned Alioth native file");quit(1);return
	resumed_alioth=true
	await verify_alioth_station(app.session.station_owner())
	print("Native Alioth save continuation: ",checks," checks; ",failures," failures")
	app.free();quit(1 if failures else 0)

func travel_application(destination: int) -> bool:
	arriving=true
	var result: bool=await super.travel_application(destination)
	arriving=false
	return result

func complete_retained_jobs(args: PackedStringArray) -> void:
	save_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if save_directory.is_empty() or not AliothCheckpoint.private_path(save_directory+"/save.bin"):check(false,"Set a private campaign application save directory");return
	app.enable_saves(save_directory.path_join("automatic"))
	if not app.save_station():check(false,app._save_notice.text);return
	if not record_current("13-initial"):return
	await super.complete_retained_jobs(args)

func release_application_flight() -> bool:
	# The normal departure just wrote its acknowledged station. Replace this
	# unstepped flight from that file, then exercise the same native departure.
	var cursor: int=app.session.snapshot().campaign_cursor
	if cursor in [13,14] and not arriving:
		var file:=SaveFile.new();var document:=file.read_document(app.station_save_path())
		if document.is_empty():check(false,file.error);return false
		if not app.load_station(now_us):check(false,app._save_notice.text);return false
		var archive:=Archive.new()
		check(archive.capture(app.session.station_owner(),definitions)==document,"Loading changed the saved contract, payment, pending story or contacts")
		if not record_current("%d-departure-%d"%[cursor,saved_cases]):return false
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return false
		reloaded_cursors.append(cursor)
	return await super.release_application_flight()

func verify_application_result(kind: int,args: PackedStringArray,previous_credits: int=0,previous_count: int=0) -> void:
	var bytes:=FileAccess.get_file_as_bytes(app.station_save_path())
	check(not app._can_save_station() and not app.save_station(false),"An unresolved result became a saved checkpoint")
	check(FileAccess.get_file_as_bytes(app.station_save_path())==bytes,"An unresolved result replaced the prior checkpoint")
	await super.verify_application_result(kind,args,previous_credits,previous_count)
	if failures:return
	if app.session is StationSession and app._can_save_station():
		if not record_current("13-paid-%d"%[previous_count+1]):return
		var file:=SaveFile.new();var current:=file.read_document(app.station_save_path())
		check(current.career.completed_side_missions==previous_count+1 and current.career.credits==app.session.snapshot().contracts.credits,"Acknowledged payment was not autosaved once")

func prepare_alioth_flight(station: RefCounted) -> Node3D:
	app.show();resume_application_focus()
	if not record_current("16-before-battle"):return null
	var before: Dictionary=station.snapshot()
	if not app.load_station(now_us):check(false,app._save_notice.text);return null
	check(app.session.station_owner().snapshot()==before,"Loading the capture checkpoint changed the pending battle or career")
	reloaded_cursors.append(16)
	return await super.prepare_alioth_flight(app.session.station_owner())

func after_alioth_flight(live: Node3D,frame: RefCounted,station: RefCounted) -> void:
	await super.after_alioth_flight(live,frame,station)
	if failures:return
	if not record_current("18-unlocked"):return
	check(reloaded_cursors.count(16)==1 and (resumed_alioth or (reloaded_cursors.count(13)==4 and reloaded_cursors.count(14)==2)),"The application did not reload each earned contract/capture departure")
	var file:=SaveFile.new();var document:=file.read_document(app.station_save_path())
	check(document.version==1 and document.station.campaign_cursor==18,"The actual unlock did not resume the compatible ordinary save format")
	print("Campaign save/load cases: ",saved_cases,"; reloaded departures: ",reloaded_cursors)

func record_current(label: String) -> bool:
	if not app.session is StationSession or not app._can_save_station():check(false,"No acknowledged campaign checkpoint: "+label);return false
	var archive:=Archive.new();var original: Dictionary=app.session.station_owner().snapshot()
	var document:=archive.capture(app.session.station_owner(),definitions)
	var restored:=archive.restore(definitions,catalogue,source,document)
	if restored==null:check(false,label+": "+archive.error);return false
	check(restored.snapshot()==original,"The campaign archive changed an earned checkpoint: "+label)
	check(archive.restored_locations.snapshot()==app.session.location_owner().snapshot(),"The campaign archive regenerated its locations: "+label)
	var file:=SaveFile.new();var path:=SaveFile.path_for(save_directory.path_join(label),definitions)
	if not file.save(path,restored,definitions,catalogue,source):check(false,file.error);return false
	saved_cases+=1
	return failures==0
