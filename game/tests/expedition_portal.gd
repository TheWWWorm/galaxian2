extends "res://tests/void_portal.gd"
## Detached Dima28/second-Void29 portal checks; the session owns progression.
const Rules=preload("res://src/content/void_portal_definitions.gd")
const Thynome=preload("res://src/content/thynome_expedition_definitions.gd")
const Probe=preload("res://src/content/void_probe_definitions.gd")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<3 or args.size()>4:check(false,"Expected content, bindings, visuals and optional capture folder");quit(1);return
	library=Library.new();bindings=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest):check(false,library.error+bindings.error);quit(1);return
	verify_first_void_regression()
	if not Thynome.available(bindings) or not Probe.parameters(bindings.mido_travel.get("void_probe")):
		check(not Owner.new().configure(bindings,dima_entry(),library),"Earlier pack admitted the selected Dima portal")
		check(not Owner.new().configure(bindings,second_void_entry(),library),"Earlier pack admitted the second Void portal")
	else:
		verify_dima_portal()
		verify_second_void()
		if failures==0:await verify_selected_geometry(args[2],args[3] if args.size()==4 else OS.get_environment("GOF2_CAPTURE_DIR"))
	print("Expedition portal: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func dima_entry() -> Dictionary:
	var selected:=entry()
	var declaration: Dictionary=bindings.mido_travel.get("thynome_expedition",Thynome.VALUES)
	var mission: Dictionary=declaration.mission28
	var displacement: Array=declaration.world28.portal.cast_position_offset_xyz
	selected.campaign_cursor=int(mission.campaign_cursor);selected.mission_kind=int(mission.kind)
	selected.system_id=int(mission.system_id);selected.station_id=int(mission.station_id)
	selected.current_station_id=int(mission.station_id);selected.void_station_id=-1
	# A valid original initial point plus the cast displacement. Construction
	# supplies this already-relocated position; this owner must not draw it again.
	selected.environment_object.position=Vector3(0,0,60000)+Vector3(displacement[0],displacement[1],displacement[2])
	return selected

func second_void_entry() -> Dictionary:
	var selected:=entry()
	var declaration: Dictionary=bindings.mido_travel.get("void_probe",Probe.VALUES)
	var mission: Dictionary=declaration.mission29
	selected.campaign_cursor=int(mission.campaign_cursor);selected.mission_kind=int(mission.kind)
	selected.system_id=int(mission.system_id);selected.station_id=int(mission.station_id)
	selected.return_station_id=int(declaration.world29.entry.recorded_return_station_id)
	return selected

func story_selection(cursor: int,completed:=false) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":cursor,"mission_kind":-1 if cursor==30 else 4,
		"mission_story":cursor==29,"mission_completed":completed,"mission_failed":false,
		"current_station_id":-1,"return_station_id":91}

func verify_first_void_regression() -> void:
	var owner:=fresh()
	check(owner.portal_snapshot().campaign_cursor==25 and owner.portal_snapshot().mission_kind==156 and owner.portal_snapshot().position==Vector3(0,0,60000),"First Void portal changed its selected source identity")
	check(owner.observe_contact(observation(owner,Vector3(999,0,0))) and owner.transition_ready(1),"First Void portal lost living contact")
	check(not owner.transition_ready(0),"First Void portal admitted dead-player contact")

func verify_dima_portal() -> void:
	var selected:=dima_entry();var owner:=Owner.new()
	check(Rules.selected(bindings.mido_travel,selected) and owner.configure(bindings,selected,library),owner.error)
	if owner.portal_snapshot().is_empty():return
	var portal: Dictionary=owner.portal_snapshot()
	check(portal.campaign_cursor==28 and portal.system_id==18 and portal.station_id==91 and portal.mission_kind==4 and portal.slot==3 and portal.model_id==16994 and portal.position==selected.environment_object.position,"Dima portal redrew or lost its relocated slot3 identity")
	check(owner.observe_contact(observation(owner,Vector3(1000,0,0))) and owner.snapshot().contact.pull_distance==152 and not owner.transition_ready(1),"Dima portal crossed the strict contact distance")
	check(owner.observe_contact(observation(owner,Vector3.ZERO,false)) and owner.snapshot().contact.is_empty(),"Disabled Dima environment contact entered the portal")
	check(owner.observe_contact(observation(owner,Vector3.ZERO,true,true)) and owner.snapshot().contact.is_empty(),"Active Dima mining entered the portal")
	var wrong:=selected.duplicate(true);wrong.current_station_id=-1
	check(not owner.configure(bindings,wrong,library) and owner.portal_snapshot()==portal,"Dima portal accepted the persistent Void instead of selected station91")
	wrong=selected.duplicate(true);wrong.environment_object.position=Vector3(INF,0,0)
	check(not owner.configure(bindings,wrong,library) and owner.portal_snapshot()==portal,"Dima portal accepted a nonfinite cast anchor")
	check(owner.observe_contact(observation(owner,Vector3(999,0,0))) and owner.snapshot().contact.entry_contact and owner.transition_ready(1) and not owner.transition_ready(0),"Live Dima contact did not signal its immediate transition")
	check(owner.portal_snapshot().campaign_cursor==28 and owner.snapshot().campaign_cursor==28,"Portal contact advanced the career outside session ownership")
	var clock:=Owner.new();check(clock.configure(bindings,selected,library),clock.error)
	var random:=rng();var before: Dictionary=random.snapshot()
	if not until(clock,random,60000):return
	check(clock.portal_snapshot().elapsed_ms==60000 and clock.portal_snapshot().extent==4096 and random.snapshot()==before,"Dima portal closed at the inclusive boundary")
	if not until(clock,random,3000):return
	check(clock.portal_snapshot().visible and clock.portal_snapshot().extent==0 and random.snapshot()==before,"Dima portal relocated before the strict closure boundary")
	check(clock.advance(1,camera,random) and clock.portal_snapshot().elapsed_ms==-3000 and clock.portal_snapshot().position==Vector3(-77981,34947,-75738),"Dima portal failed recurring source relocation")
	check(not clock.transition_ready(1),"Dima relocation manufactured contact")

func verify_second_void() -> void:
	var selected:=second_void_entry();var owner:=Owner.new()
	check(Rules.selected(bindings.mido_travel,selected) and owner.configure(bindings,selected,library),owner.error)
	if owner.portal_snapshot().is_empty():return
	var portal: Dictionary=owner.portal_snapshot()
	check(portal.campaign_cursor==29 and portal.system_id==-1 and portal.station_id==-1 and portal.mission_kind==4 and portal.position==selected.environment_object.position,"Second Void portal changed its original location or mission")
	for changes in [{"return_station_id":48},{"current_station_id":91},{"mission_kind":156},{"mission_story":false}]:
		var bad:=selected.duplicate(true);bad.merge(changes,true)
		check(not owner.configure(bindings,bad,library) and owner.portal_snapshot()==portal,"Second Void portal accepted a different selected source identity")
	var before:=owner.snapshot()
	check(not owner.observe_contact(observation(owner,Vector3.ZERO)) and owner.snapshot()==before,"Second Void contact accepted an absent story selection")
	for changes in [{"binding_id":"foreign"},{"return_station_id":48},{"current_station_id":91},{"mission_kind":156},{"mission_failed":true},{"campaign_cursor":31}]:
		var wrong:=story_selection(29);wrong.merge(changes,true)
		var observation_now:=observation(owner,Vector3.ZERO);observation_now.story_selection=wrong
		check(not owner.observe_contact(observation_now) and owner.snapshot()==before,"Malformed Void29 selection changed retained contact: "+str(changes))
	for completed in [false,true]:
		var locked:=observation(owner,Vector3.ZERO);locked.story_selection=story_selection(29,completed)
		check(owner.observe_contact(locked) and owner.snapshot().contact.pull_distance==156 and not owner.snapshot().contact.entry_contact and not owner.transition_ready(1),"Selected Void29 story entered before final result Next")
	var after_result: Dictionary=owner.snapshot()
	var too_early:=observation(owner,Vector3.ZERO);too_early.story_selection=story_selection(30,false)
	check(not owner.observe_contact(too_early) and owner.snapshot()==after_result,"Void29 admitted cursor30 without completed final Next")
	var finished:=observation(owner,Vector3(999,0,0));finished.story_selection=story_selection(30,true)
	check(owner.observe_contact(finished) and owner.snapshot().contact.entry_contact and owner.transition_ready(1),"Post-Next Void contact could not return to recorded Dima91")
	check(not owner.transition_ready(0) and owner.portal_snapshot().campaign_cursor==29,"Second Void transition failed alive-player or no-progression boundary")
	var clock:=Owner.new();check(clock.configure(bindings,selected,library),clock.error)
	var random:=rng()
	if not until(clock,random,63000):return
	check(clock.portal_snapshot().visible and clock.portal_snapshot().extent==0,"Second Void portal lost shared closing clock")
	check(clock.advance(1,camera,random) and clock.portal_snapshot().visible and clock.portal_snapshot().elapsed_ms==-3000 and clock.portal_snapshot().position==Vector3(-77981,34947,-75738),"Second Void portal lost shared recurrence")

func verify_selected_geometry(visual_path: String,captures: String) -> void:
	var visuals:=Visuals.new()
	if not visuals.open(visual_path,library.manifest):check(false,visuals.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var view:=Camera3D.new();viewport.add_child(view);view.current=true;view.near=10;view.far=100000
	for selected in [dima_entry(),second_void_entry()]:
		var owner:=Owner.new();var geometry:=Geometry.new();viewport.add_child(geometry)
		if not owner.configure(bindings,selected,library) or not geometry.build(library,visuals,bindings,selected):check(false,owner.error+geometry.error);geometry.free();break
		var portal: Dictionary=owner.portal_snapshot()
		var flight_camera:=Transform3D(Basis.IDENTITY,portal.position+Vector3(0,0,-20000))
		view.look_at_from_position(flight_camera.origin,portal.position)
		if not owner.advance(150,flight_camera,rng()):check(false,owner.error);geometry.free();break
		portal=owner.portal_snapshot()
		var frame: Dictionary=geometry.prepare_state(portal)
		if frame.is_empty():check(false,geometry.error);geometry.free();break
		geometry.commit_state(frame)
		check(geometry.model.instances.size()==2 and geometry.model.instances.all(func(node):return node.is_visible_in_tree()),"Expedition portal lost an original additive surface")
		var wrong:=portal.duplicate(true);wrong.campaign_cursor=25
		check(geometry.prepare_state(wrong).is_empty(),"Expedition portal renderer accepted a different selected story")
		if DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			var picture:=viewport.get_texture().get_image();var background:=picture.get_pixel(0,0);var pixels:=0
			for y in range(0,picture.get_height(),4):
				for x in range(0,picture.get_width(),4):
					var pixel:=picture.get_pixel(x,y)
					if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>.09:pixels+=1
			check(pixels>100,"Expedition portal did not render at cursor"+str(selected.campaign_cursor))
			if not captures.is_empty():
				DirAccess.make_dir_recursive_absolute(captures)
				check(picture.save_png(captures.path_join("expedition-portal-%d.png"%selected.campaign_cursor))==OK,"Expedition portal capture failed")
		geometry.free()
	viewport.free()
