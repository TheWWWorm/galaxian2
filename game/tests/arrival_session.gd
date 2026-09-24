extends SceneTree
const Station=preload("res://src/simulation/station_entry.gd")
const Session=preload("res://src/presentation/arrival_session.gd")
const World=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const RadioPanel=preload("res://src/presentation/radio_panel.gd")
var checks:=0
var failures:=0
var captures:=""

func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	captures=OS.get_environment("GOF2_CAPTURE_DIR")
	if not args.is_empty() and args[0].begins_with("--captures="):captures=args[0].trim_prefix("--captures=");args.remove_at(0)
	check(args.size()==3,"Expected one Mac content/bindings/visual triple")
	if args.size()==3:await verify(args)
	print("Arrival session: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not visuals.open(args[2],lib.manifest):check(false,lib.error+bindings.error+cat.error+visuals.error);return
	check(lib.select_language("gb"),lib.error)
	if not Session.supported(bindings):
		var unsupported:=World.new()
		check(not unsupported.configure(bindings,cat,lib,{},[],1789100000),"Legacy pack fabricated a rescue session")
		return
	var player:=Player.new();var handoff:=Handoff.new()
	check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	check(not packet.is_empty(),handoff.error)
	var viewport:=SubViewport.new();viewport.size=Vector2i(1000,700);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var session:=Session.new();viewport.add_child(session)
	if not session.configure(lib,bindings,visuals,packet,0,1789100000):check(false,session.error);viewport.free();return
	var panel:=RadioPanel.new();viewport.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(panel.configure(bindings.base_content_id,bindings.binding_id,lib.active_language,session.radio_resources.speakers,1),panel.error)
	check(session.prepare_station().is_empty(),"Running rescue prepared a station before its fade")
	var initial:=session.snapshot()
	check(initial.elapsed_ms==0 and initial.radio.started==[false,false,false] and initial.fade.alpha_byte==255,"Rescue inherited the Opening clock, radio flags or fade")
	check(initial.scenery.objects.size()==130 and initial.world_frame.progress.rank==1 and initial.world_frame.player.vitals.hull==200,"Rescue lost its field, earned rank or cached player")
	check(initial.world_frame.target_ids==["player"] and not initial.world_frame.player_update_enabled,"Rescue target list or player freeze is incorrect")
	check(not session.can_control() and not session.flight_hud_visible(),"Rescue exposed ordinary flight controls")
	var now:=0
	for i in 100:
		now+=99990
		check(session.step(now),session.error)
	check(session.snapshot().elapsed_ms==9999 and session.snapshot().radio.started==[false,false,false],"Rescue spoke before its ten-second gate")
	now=10000000;check(session.step(now),session.error)
	check(session.snapshot().radio.started==[true,false,false] and not session.snapshot().radio.visible,"First rescue transmission did not start at ten seconds")
	var frozen:=session.snapshot();var audio: Dictionary=session.audio.snapshot()
	check(not session.step(now+100000,Vector2.ONE,true) and session.snapshot()==frozen and session.audio.snapshot()==audio,"Frozen rescue player accepted flight input")
	check(session.set_pause("user",true,now) and session.set_pause("focus",true,now),session.error)
	check(session.step(now+10000000) and session.snapshot()==frozen,"Paused rescue consumed scene time")
	check(session.set_pause("user",false,now+10000000) and session.is_paused(),"One pause cleared another pause reason")
	check(session.set_pause("focus",false,now+10000000) and not session.is_paused(),session.error)
	now+=10000000
	var before: Dictionary=session.snapshot();var projection: Dictionary=session._projection._settings
	var actor_pose: Transform3D=session.geometry.actors[0].transform
	session._projection._settings={}
	check(not session.step(now+100000) and session.snapshot()==before and session.audio.snapshot().history==audio.history,"Rejected presentation consumed world time or emitted audio")
	check(session.geometry.actors[0].transform==actor_pose,"Late presentation failure retained a prospective actor pose")
	session._projection._settings=projection
	check(session.step(now+100000),session.error);now+=100000
	check(session.snapshot().elapsed_ms==10100,"Failed presentation consumed the retry's clock interval")
	var seen:={};var last_finished:=false;var final_finished_time:=-1;var fade_started:=-1
	for i in 550:
		now+=100000
		check(session.step(now),session.error)
		var state:=session.snapshot()
		check(panel.present(state.radio),panel.error)
		if state.radio.visible and not seen.has(state.radio.active_event):
			seen[state.radio.active_event]=true
			check(panel._name.text=="Gunant Breh" and state.radio.text==lib.strings[state.radio.text_id],"Rescue displayed the wrong speaker or localization")
			check(state.actor.active and state.actor.mode==1 and not state.actor.engine_draw_enabled and state.world_frame.dispatch.target_present and not state.world_frame.dispatch.target_excluded,"Live rescue failed its target and mode-five decisions")
			check(state.world_frame.player==initial.world_frame.player and state.world_frame.player_body==Transform3D.IDENTITY,"Frozen player moved or changed vitals")
			check(state.actor.body_pose.origin.z>initial.actor.body_pose.origin.z and session.geometry.actors[0].transform==state.actor.statistics_pose,"Scripted approach did not reach the rendered actor")
			await capture(viewport,"rescue-radio-%d"%state.radio.active_event)
			var count: int=session.audio.snapshot().history.size()
			check(session.present() and session.audio.snapshot().history.size()==count,"Repainting a frame replayed its voice")
		if state.radio.finished[2] and not last_finished:
			final_finished_time=int(state.elapsed_ms)
			check(state.staging.phase==0,"Controller observed same-frame radio completion")
		if state.staging.phase==1 and fade_started<0:
			fade_started=int(state.elapsed_ms)
			check(fade_started==final_finished_time+100 and state.fade.elapsed_ms==0,"Exit fade did not start on the following controller frame")
		last_finished=state.radio.finished[2]
		if session.status=="station_transition_required":break
	var end:=session.snapshot()
	check(seen.size()==3 and session.status=="station_transition_required" and end.radio.finished==[true,true,true],"Rescue did not finish its three transmissions and station fade")
	check(end.elapsed_ms==fade_started+5100 and end.fade.alpha_byte==255,"Station boundary lost its strict fade duration or black plate")
	check(end.world_frame.progress==packet.progress and end.world_frame.player_cache==packet.player_cache and end.campaign_cursor==1,"Rescue fabricated station progress, a reward or a changed save")
	var voices: Array=session.audio.snapshot().history.filter(func(op):return op.has("radio_event"))
	check(voices.size()==3 and voices.map(func(op):return op.source_id)==[501,502,503],"Rescue did not voice each source event exactly once")
	check(session.step(now+10000000) and session.snapshot()==end,"Station boundary continued simulating")
	var station_packet: Dictionary=session.prepare_station()
	check(not station_packet.is_empty() and session.snapshot()==end,session.error)
	if not bindings.station_entry.is_empty():
		var station:=Station.new()
		check(station.configure(bindings,cat,lib,station_packet),station.error)
		check(station.snapshot().dialogue.text_id==1678 and station.snapshot().loadout.ship_id==0,"Live rescue packet did not enter the source station conversation")
	await capture(viewport,"rescue-station-boundary")
	for key in ["binding_id","player","rescue_disposition","progress"]:
		var bad:=packet.duplicate(true)
		match key:
			"binding_id":bad.binding_id="foreign"
			"player":bad.player.vitals.hull=9999999
			"rescue_disposition":bad.rescue_disposition.actor_hostile=true
			"progress":bad.progress.rank=20
		var world:=World.new()
		check(not world.configure(bindings,cat,lib,bad,session.radio_resources.line_counts,1789100000) and world.snapshot().is_empty(),"Invalid rescue packet accepted "+key)
	session.free()
	check(not viewport.is_audio_listener_3d(),"Disposing rescue did not restore the viewport's listener state")
	viewport.free();await process_frame

func capture(viewport: SubViewport,name_value: String):
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	check(viewport.get_texture().get_image().save_png(captures.path_join(name_value+".png"))==OK,"Could not capture rescue scene")

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
