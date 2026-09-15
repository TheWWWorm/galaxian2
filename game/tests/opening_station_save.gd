extends "res://tests/combat_training_destruction.gd"
## The producer earns each checkpoint through the existing rescue/mining path.
## A separate invocation loads only the files and continues their native actions.
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const PrivatePath=preload("res://tests/fixtures/convoy_station_scenario.gd")
var save_directory:=""
var saved_cursors:=[]

func run():
	var args:=OS.get_cmdline_user_args()
	save_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if save_directory.is_empty() or not PrivatePath.private_path(save_directory+"/save.bin"):check(false,"Set a private opening save directory")
	elif args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional captures")
	elif OS.get_environment("GOF2_OPENING_SAVE_PHASE")=="resume":await resume_checkpoints(args)
	else:
		await verify(args)
		check(saved_cursors==[2,4,6,7],"The producer did not earn each opening checkpoint")
	if is_instance_valid(host):host.free()
	print("Opening station saves: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func key(code: int):
	if is_instance_valid(host) and host._save_directory.is_empty():host.enable_saves(save_directory.path_join("automatic"))
	super.key(code)
	if OS.get_environment("GOF2_OPENING_SAVE_PHASE")=="resume":return
	if is_instance_valid(host) and host.session is Station:
		var cursor: int=host.session.snapshot().campaign_cursor
		if cursor in [2,4,6,7] and not saved_cursors.has(cursor) and host._can_save_station():
			if record_station(host.session.station_owner(),host.session.location_owner(),str(cursor)):
				saved_cursors.append(cursor)
				var cat:=Catalogues.new();check(cat.open(lib),cat.error)
				var file:=SaveFile.new();var automatic:=file.load_document(host.station_save_path(),bindings,cat,lib)
				check(automatic.get("station",{}).get("campaign_cursor")==cursor,"Acknowledging the opening station did not autosave: "+str(cursor)+" "+file.error)

func record_station(owner: RefCounted,locations: RefCounted,label: String) -> bool:
	var cat:=Catalogues.new()
	if not cat.open(lib):check(false,cat.error);return false
	var archive:=Archive.new();var before: Dictionary=owner.snapshot()
	var data:=archive.capture(owner,bindings,locations)
	var restored:=archive.restore(bindings,cat,lib,data)
	if restored==null:check(false,"Checkpoint "+label+": "+archive.error);return false
	check(restored.snapshot()==before,"The opening checkpoint changed its station: "+label)
	check(archive.restored_locations.snapshot()==locations.snapshot(),"The opening checkpoint regenerated station contacts: "+label)
	check(archive.capture(restored,bindings,archive.restored_locations)==data,"The opening checkpoint changed on recapture: "+label)
	var file:=SaveFile.new();var path:=SaveFile.path_for(save_directory.path_join(label),bindings)
	check(file.save(path,owner,bindings,cat,lib,locations),file.error)
	check(file.load_document(path,bindings,cat,lib)==data,"The opening checkpoint changed on disk: "+label+" "+file.error)
	for mutation in [[["station","acknowledged"],false],[["station","line_index"],128],[["station","progress","rank_score"],-1],[["station","mission","kind"],999],[["locations","current_station_id"],98]]:
		var invalid:=data.duplicate(true);var parent: Dictionary=invalid
		for index in mutation[0].size()-1:parent=parent[mutation[0][index]]
		parent[mutation[0].back()]=mutation[1]
		check(archive.restore(bindings,cat,lib,invalid)==null,"An invalid opening checkpoint loaded: "+label+" "+str(mutation[0]))
	check(owner.snapshot()==before,"Checkpoint validation changed the running opening")
	return true

func after_second_return(args: PackedStringArray):
	var owner: RefCounted=host.session.station_owner();var locations: RefCounted=host.session.location_owner()
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	check(owner.open_equipment(bindings,cat,lib),owner.error)
	check(Archive.new().capture(owner,bindings,locations).is_empty(),"Saving discarded an open tutorial hangar")
	check(owner.close_equipment(),owner.error)
	record_station(owner,locations,"6-unmodified")
	check(owner.open_equipment(bindings,cat,lib) and owner.equipment_action("buy",0) and owner.close_equipment(),owner.error)
	record_station(owner,locations,"6-partial")
	await super.after_second_return(args)
	var original: Dictionary=host.session.station_owner().snapshot()
	var original_session: Node=host.session
	var textures: Dictionary=visuals.textures;visuals.textures={}
	check(not host.load_station(now_us) and host.session==original_session and host.session.station_owner().snapshot()==original,"A failed early load replaced the live station")
	visuals.textures=textures
	check(host.load_station(now_us),host._save_notice.text)
	check(host.session.station_owner().snapshot()==original,"The early application load changed the equipped station")
	check(host.session.audio.snapshot().get("history",[]).is_empty(),"Loading replayed acknowledged equipment dialogue")
	check(host.request_departure(),host.session.error);host.cancel_departure()

func resume_checkpoints(args: PackedStringArray):
	var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	root.size=Vector2i(1280,720);root.grab_focus()
	host=Host.new();root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.set_context(lib,bindings,visuals);host.set_process(false)
	for label in ["2","4","6","6-unmodified","6-partial","7"]:
		host.enable_saves(save_directory.path_join(label))
		for i in 2:await process_frame
		root.grab_focus();host._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		if not host.load_station(0):check(false,label+": "+host._save_notice.text);return
		var original: Dictionary=host.session.station_owner().snapshot()
		verify_inventory_guards(cat)
		host.enable_saves(save_directory.path_join("resumed-"+label))
		check(host._can_save_station() and host._save_button.visible,"The loaded opening station cannot save")
		check(not original.dialogue.visible and host.session.audio.snapshot().get("history",[]).is_empty(),"Loading replayed acknowledged dialogue")
		check(not host.session.navigate("next",host.station_panel),"Loading allowed double acknowledgement")
		if args.size()==4:await capture(args[3],"loaded-opening-"+label)
		if original.campaign_cursor==6:
			check(host.equipment_action("open"),host.session.error)
			for id in [0,55]:
				var owned: Dictionary=host.session.snapshot().equipment
				if id not in owned.loadout.equipment_ids:
					var in_cargo: bool=owned.cargo.entries.any(func(row):return row.item_id==id)
					if not in_cargo:check(host.equipment_action("buy",id),host.session.error)
					check(host.equipment_action("mount",id),host.session.error)
			check(host.equipment_action("close"),host.session.error)
			check(host.session.snapshot().campaign_cursor==6 and host.session.snapshot().dialogue.visible,"Restored fitting skipped its acknowledgement")
			key(KEY_ENTER)
			check(host.session.snapshot().campaign_cursor==7,"Restored fitting did not unlock training")
		check(host.request_departure(),host.session.error)
		check(host.enter_first_flight(0,4096,1789100000),host.status.text)
		check(host.session.snapshot().campaign_cursor in [2,4,7],"Restored station selected another flight")
		check(not host._save_button.visible,"An in-flight save was exposed")
		host.reset()

func verify_inventory_guards(cat: RefCounted) -> void:
	var archive:=Archive.new()
	var data:=archive.capture(host.session.station_owner(),bindings,host.session.location_owner())
	if data.inventory.is_empty():return
	var invalid:=data.duplicate(true);invalid.inventory.stock[0].quantity+=1
	check(archive.restore(bindings,cat,lib,invalid)==null,"A saved tutorial duplicated its limited stock")
	invalid=data.duplicate(true);invalid.inventory.stock[0].unit_price=1
	check(archive.restore(bindings,cat,lib,invalid)==null,"A saved tutorial changed its original free price")
	invalid=data.duplicate(true);invalid.inventory.cargo.used+=1
	check(archive.restore(bindings,cat,lib,invalid)==null,"A saved tutorial changed its cargo count")
	invalid=data.duplicate(true);invalid.inventory.credit_delta=100
	check(archive.restore(bindings,cat,lib,invalid)==null,"A saved tutorial granted unearned credits")
	invalid=data.duplicate(true);invalid.inventory.training_inventory_released=true
	check(archive.restore(bindings,cat,lib,invalid)==null,"A saved tutorial skipped combat training")
