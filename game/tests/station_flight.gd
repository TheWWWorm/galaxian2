extends SceneTree
## Mac first-flight integration. Mining tests position the native player near an
## authored asteroid; station guidance captures use the actual departure pose.
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Definitions=preload("res://src/content/station_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Notices=preload("res://src/simulation/flight_notices.gd")
const NoticePanel=preload("res://src/presentation/flight_notice_panel.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Guidance=preload("res://src/simulation/player_guidance.gd")
var checks:=0
var failures:=0
var lib:=Library.new()
var bindings:=Bindings.new()
var cat:=Catalogues.new()
var construction:=Construction.new()
var ready: RefCounted
var captures:={}
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Station flight: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
func verify(args: PackedStringArray):
	var bodies:=Bodies.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(header.architecture=="x86_64","This verification is Mac only")
	if not bindings.station_flight.is_empty():
		check(Definitions.validate(bindings.station_flight,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Valid station flight declarations were refused")
		for key in Definitions.VALUES:
			var bad: Dictionary=bindings.station_flight.duplicate(true);bad[key]=null
			check(not Definitions.parameters(bad),"Changed station flight parameter accepted: "+key)
		for key in Definitions.SPANS:
			var bad: Dictionary=bindings.station_flight.duplicate(true);bad.provenance[key].offset+=1
			check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Detached station flight span accepted: "+key)
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3)),[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	if not construction.prepare(bindings,cat,station.prepare_departure(bindings,cat),4096,1789100000,true,bodies):check(false,construction.error);return
	var flight:=Frame.new()
	if not flight.configure(bindings,cat,lib,construction,"E",.5,Vector2i(960,720)):check(false,flight.error);return
	if bindings.station_flight.is_empty():
		check(not flight.snapshot().has("station_autopilot") and flight.start_station_autopilot()==null,"Legacy flight invented station control")
		return
	var entry:=flight.snapshot()
	check(flight.start_station_autopilot()==null and flight.snapshot()==entry,"Entry accepted station controls before release")
	for i in 130:
		flight=flight.evaluate(100)
		if flight==null:check(false,"Could not prepare first-flight briefing");return
	var modal:=flight.snapshot()
	check(modal.dialogue.visible and flight.start_station_autopilot()==null and flight.snapshot()==modal,"Modal instruction accepted station control")
	for i in 5:flight=flight.navigate("next")
	ready=flight
	verify_controls()
	verify_mining_history()
	verify_languages()
	if args.size()==4 and failures==0:await verify_gpu(args)
func verify_controls():
	var unchanged: Dictionary=ready.snapshot()
	var flight: RefCounted=ready.evaluate(100,Vector2(1,-1),.5)
	flight=flight.evaluate(100,Vector2(1,-1),.5)
	var manual: Dictionary=flight.snapshot()
	check(manual.angular_units.x>0 and manual.angular_units.y<0 and manual.player_model_basis!=Basis.IDENTITY,"Manual input lost its pitch/bank presentation")
	check(manual.station_autopilot.bank==manual.station_autopilot.angular_units.y and manual.station_autopilot.angular_units!=manual.angular_units,"Manual visual sample was taken after neutral/input response")
	var started: RefCounted=flight.start_station_autopilot()
	if started==null:check(false,flight.error);return
	var selected: Dictionary=started.snapshot();captures["station-start"]=started
	for key in ["player_pose","player_model_basis","camera_view","angular_units","cargo","scenery","random_state","world_elapsed_ms"]:check(selected[key]==manual[key],"Station selection changed "+key)
	check(selected.station_autopilot.active and selected.station_autopilot.throttle==1 and selected.flight_notices.current.text=="Target: Var Hastra Station","Station selection lost its source state or target notice")
	check(started.start_station_autopilot()==null and started.start_mining()==null,"Concurrent station and mining owners were accepted")
	check(started.evaluate(100,Vector2.ONE,0,true).snapshot()==selected and started.cancel_station_autopilot(true)==null,"Pause changed station guidance")
	var step: RefCounted=started.evaluate(100,Vector2(-1,1))
	if step==null:check(false,started.error);return
	check(step.snapshot()==started.evaluate(100,Vector2(1,-1)).snapshot(),"Active autopilot consumed current steering commands")
	var first: Dictionary=step.snapshot()
	check(first.player_pose.origin.distance_to(selected.player_pose.origin)>199.95 and first.player_pose.origin.distance_to(selected.player_pose.origin)<200.05,"Autopilot moved twice or used the previous half throttle")
	check(first.station_autopilot.angular_units.x==manual.angular_units.x and first.angular_units==first.station_autopilot.angular_units,"First guidance frame discarded preceding command flags")
	var second: RefCounted=step.evaluate(100,Vector2.ONE)
	if second==null:check(false,step.error);return
	var next: Dictionary=second.snapshot()
	check(next.angular_units.x<next.station_autopilot.angular_units.x and absf(next.angular_units.y)<absf(next.station_autopilot.angular_units.y),"Neutral return ignored cleared flags on the next guidance frame")
	check(next.station_autopilot.history_cursor==2 and next.station_autopilot.history.slice(2)==[0.0,0.0,0.0],"Guidance history advanced more than once per frame")
	flight=second
	for i in 18:
		var moving: RefCounted=flight.evaluate(100,Vector2.ONE)
		if moving==null:check(false,flight.error);return
		flight=moving
	captures["station-turn"]=flight
	var moving: Dictionary=flight.snapshot()
	var stopped: RefCounted=flight.cancel_station_autopilot()
	if stopped==null:check(false,flight.error);return
	var cancelled: Dictionary=stopped.snapshot();captures["station-cancel"]=stopped
	for key in ["player_pose","player_model_basis","camera_view","angular_units","cargo","scenery","random_state","world_elapsed_ms"]:check(cancelled[key]==moving[key],"Cancellation changed "+key)
	check(not cancelled.station_autopilot.active and cancelled.station_autopilot.history_cursor==0 and not cancelled.station_autopilot.history_wrapped and cancelled.station_autopilot.history==moving.station_autopilot.history,"Cancellation erased the bank samples or retained their cursor")
	var restart: RefCounted=stopped.start_station_autopilot()
	check(restart!=null and restart.snapshot().station_autopilot.bank==moving.station_autopilot.bank and restart.snapshot().player_pose==moving.player_pose,"Immediate restart lost an established bank or pose")
	check(cancelled.flight_notices.pending.back().source_id==6,"Cancellation omitted the original off notice")
	var resumed: RefCounted=stopped.evaluate(100,Vector2.ZERO,.3)
	if resumed==null:check(false,stopped.error);return
	captures["station-resume"]=resumed
	check(resumed.snapshot().station_autopilot.bank==cancelled.angular_units.y and resumed.snapshot().player_model_basis==stopped._autopilot.visual_basis(cancelled.angular_units),"Manual resume snapped to level or used the wrong response sample")
	for key in ["campaign_cursor","progress","mission","cargo","random_state","reward_credits","mining_completed"]:check(resumed.snapshot()[key]==unchanged[key],"Station guidance invented progress: "+key)
	check(ready.snapshot()==unchanged and flight.snapshot()==moving and started.snapshot()==selected,"Prospective guidance mutated an accepted frame")
	var bad: RefCounted=started.fork_for_frame();bad._shot.target="unsupported";var before: Dictionary=bad.snapshot()
	check(bad.evaluate(100)==null and bad.snapshot()==before,"Late camera failure committed guidance/history")
	var frozen: RefCounted=started.fork_for_frame();frozen._briefing._state.phase="briefing";frozen._briefing._state.line_index=0;var held: Dictionary=frozen.snapshot()
	check(frozen.evaluate(100,Vector2.ONE).snapshot()==held and frozen.cancel_station_autopilot()==null,"Modal UI failed to freeze active guidance")
	check(started.evaluate(151)==null and started.evaluate(100,Vector2(INF,0))==null and started.snapshot()==selected,"Invalid input changed the active flight")
	var branch: RefCounted=started.fork_for_frame();branch.clear();check(branch.snapshot().is_empty() and started.snapshot()==selected,"Clearing a branch changed active station flight")
	var completion: RefCounted=ready.evaluate(100,Vector2.ONE)
	check(completion._cargo.add_entries([{"item_id":construction.snapshot().scenery.bodies.objects[4].item_id,"quantity":10}]),completion._cargo.error)
	completion._briefing._state.hud_elapsed_ms=5000
	var settled: RefCounted=completion._pilot.fork_for_frame();check(settled.accept_visual_response(completion.snapshot().angular_units,.1),settled.error)
	var opened: RefCounted=completion.evaluate(100,Vector2.ONE)
	check(opened!=null and opened.snapshot().dialogue.visible and opened.snapshot().angular_units==settled.angular_units and opened._preceding_commands==Vector2.ZERO,"Cargo instruction opening consumed late pilot input")

func verify_mining_history():
	var flight: RefCounted=ready.fork_for_frame()
	var body: Dictionary=construction.snapshot().scenery.bodies.objects[4]
	# Place a test player at an oblique approach to a real authored body. The
	# established scanner has separate acquisition coverage; select that body.
	flight._pose=Transform3D(Basis.IDENTITY,body.position-Vector3(14000,0,22000));flight._targeting._selected=4
	flight._pilot.angular_units=Vector2(12,-40)
	flight=flight.evaluate(0,Vector2.ZERO,1.0)
	flight._targeting._selected=4
	var mining: RefCounted=flight.start_mining()
	if mining==null:check(false,flight.error);return
	var old: Dictionary=mining.snapshot();var retained: Dictionary=old.station_autopilot
	check(mining.start_station_autopilot()==null,"Station controls interrupted an active mining owner")
	for i in 6:
		var before: Dictionary=mining.snapshot()
		mining=mining.evaluate(100)
		if mining==null:check(false,"Mining history integration failed");return
		var after: Dictionary=mining.snapshot()
		var angle:=Guidance.signed_turn(before.player_pose.basis,after.player_pose.basis.z,float(bindings.station_autopilot.bank_sign_angle))
		check(after.station_autopilot.history[i%5]==angle and after.station_autopilot.history_cursor==(i+1)%5,"Mining did not update the shared turn sample")
		check(after.station_autopilot.bank==retained.bank and after.station_autopilot.model_basis==retained.model_basis,"Mining consumed the station bank target")
	var moved: Dictionary=mining.snapshot()
	check(moved.station_autopilot.history_wrapped and moved.player_pose!=old.player_pose,"Mining fixture did not exercise moving, wrapped turn history")
	var stop: RefCounted=mining.cancel_mining()
	if stop==null:check(false,mining.error);return
	var guide: RefCounted=stop.start_station_autopilot()
	if guide==null:check(false,stop.error);return
	check(guide.snapshot().player_pose==moved.player_pose and guide.snapshot().station_autopilot.player_pose==moved.player_pose,"Station start teleported to the last ordinary pose")
	check(guide.snapshot().station_autopilot.history==moved.station_autopilot.history and guide.snapshot().station_autopilot.history_cursor==1 and guide.snapshot().station_autopilot.bank==retained.bank,"Mining-to-station handoff lost retained bank/history")
	var zero: RefCounted=flight.start_mining();zero=zero.evaluate(0)
	check(zero.snapshot().station_autopilot.history_cursor==1,"Zero-time mining omitted a source guidance sample")
	var close: RefCounted=flight.start_mining();close._approach._state.player_pose.origin=body.position-Vector3(0,0,close._approach.snapshot().stand_off-1)
	close=close.evaluate(100)
	check(close.snapshot().station_autopilot.history_cursor==0 and close._approach.last_guidance_sample().is_empty(),"Close alignment recorded a guidance step that did not run")
func verify_languages():
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		var notice:=Notices.new();check(notice.configure(bindings,lib,construction,cat),notice.error)
		check(notice.enqueue(10) and notice.snapshot().current.text==lib.strings[535]+": "+cat.tables.stations[78].name+" "+lib.strings[135],"Wrong localized station composition: "+language)
		var target: Dictionary=notice.snapshot();check(notice.enqueue(10) and notice.snapshot()==target,"Duplicate station target restarted its fade")
		check(notice.enqueue(21) and notice.snapshot().pending[1].text==lib.strings[514],"Wrong mission restriction text: "+language)
	check(lib.select_language("gb"),lib.error)
func verify_gpu(args: PackedStringArray):
	var visuals:=Visuals.new();check(visuals.open(args[2],lib.manifest),visuals.error)
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,captures["station-start"]):check(false,scene.error);canvas.free();return
	for label in captures:
		var flight: RefCounted=captures[label];var state: Dictionary=flight.snapshot()
		check(scene.present(flight),scene.error)
		check(scene.geometry.player.transform.is_equal_approx(state.player_pose*Transform3D(state.player_model_basis,Vector3.ZERO)) and scene.camera.global_transform.is_equal_approx(state.camera_view.pose),"Live player and logical camera presentation differ: "+label)
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw
		check(canvas.get_texture().get_image().save_png(args[3].path_join(label+".png"))==OK,"Could not save station flight capture")
	canvas.free()
	canvas=SubViewport.new();canvas.size=Vector2i(960,720);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var panel:=NoticePanel.new();canvas.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		var notice:=Notices.new();check(notice.configure(bindings,lib,construction,cat) and notice.enqueue(10),notice.error)
		for i in 20:notice.advance(100)
		check(panel.configure(lib,bindings,visuals),panel.error)
		for phone in [false,true]:
			canvas.size=Vector2i(420,800) if phone else Vector2i(960,720);panel.set_mobile_layout(phone)
			check(panel.present(notice.snapshot()),panel.error)
			for i in 3:await process_frame
			check(Rect2(Vector2.ZERO,canvas.size).encloses(panel._bar.get_rect()) and panel._label.get_content_height()<=panel._label.size.y+1,"Station notice clipped in "+language+" / "+str(phone))
			if language in ["gb","de"]:check(canvas.get_texture().get_image().save_png(args[3].path_join("station-notice-"+language+("-phone" if phone else "-desktop")+".png"))==OK,"Could not save station notice layout")
	canvas.free();check(lib.select_language("gb"),lib.error)
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
