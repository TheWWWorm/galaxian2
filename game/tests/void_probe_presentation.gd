extends "res://tests/dima_construction.gd"
## Selected Void29 presentation fixture; no earned mission or career is advanced.
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")
const AudioResources=preload("res://src/content/audio_resources.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Stage=preload("res://src/simulation/void_probe_stage.gd")
const Portal=preload("res://src/content/void_portal_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const TextResources=preload("res://src/presentation/opening_radio_resources.gd")

func test_label() -> String:return "Void probe selected presentation"

func after_prepared(library: RefCounted,bindings: RefCounted,cat: RefCounted,prepared: RefCounted) -> void:
	if not library.select_language("gb"):check(false,library.error);return
	var visuals:=Visuals.new()
	if not visuals.open(visual_path,library.manifest):check(false,visuals.error);return
	var previous: Dictionary=prepared.snapshot()
	var equipment: RefCounted=prepared.equipment_owner()
	var source: Dictionary=equipment.snapshot().loadout
	if not equipment.relocate_post_sahi(bindings,29):check(false,equipment.error);return
	var cache:=Cache.capture_post_sahi(bindings.mido_travel,source,equipment.snapshot().loadout,previous.departure.player,29)
	if cache.is_empty():check(false,"Dima component lost original ship pools at the portal");return
	var progress: Dictionary=previous.departure.progress.duplicate(true)
	progress.merge(Career.calculate_progress(bindings.opening_handoff,29,progress.player_kills,progress.pirate_kills,progress.other_score),true)
	var context: Dictionary=previous.sahi_context.duplicate(true)
	context.merge({"campaign_cursor":29,"station_id":-1,"system_id":-1,"rank":progress.rank},true)
	context.erase("portal_position")
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	var construction:=FlightConstruction.new()
	if not construction.prepare_post_sahi_selected(bindings,cat,equipment,context,progress,{},4096,123,true,bodies,effects,cache):check(false,construction.error);return
	var sounds:=AudioResources.new()
	if not sounds.configure(library,bindings,29):check(false,sounds.error);return
	var source_clip: Dictionary=sounds.prepare(14)
	check(not source_clip.is_empty() and not source_clip.has("unsupported") and source_clip.get("spatial",false) and not source_clip.get("looping",true),"Original probe sound14 is not a prepared spatial one-shot: "+sounds.error+str(source_clip))
	var frame:=Frame.new()
	if not frame.configure(bindings,cat,library,construction,"E",0.5):check(false,frame.error);return
	for _row in 4:
		if not frame.dialogue_visible():break
		var next: RefCounted=frame.navigate("next")
		if next==null:check(false,frame.error);return
		frame=next
	var initial: Dictionary=frame.snapshot()
	check(initial.campaign_cursor==29 and initial.has("void_probe_stage") and initial.has("void_probe") and initial.has("void_station_targeting"),"Selected29 frame lacks its native stage/model/target owners")
	if not initial.has("void_probe_stage") or not initial.has("void_probe"):return
	check(initial.void_probe_stage.phase==0 and not initial.void_probe.visible and initial.void_probe.model_id==14290,"Original probe was visible before the mother-ship lock")
	root.size=Vector2i(1280,720)
	var scene:=Scene.new();root.add_child(scene)
	if not scene.build(library,bindings,visuals,cat,frame):check(false,scene.error);scene.free();return
	check(scene.probe!=null and not scene.probe.visible and scene.probe.model!=null,"Selected Void scene did not build the hidden original probe")
	# Drive the actual native slot0 owner with a centered camera and shared aim.
	# This is detached presentation state, not a fabricated campaign transition.
	var target: RefCounted=frame._void_targeting.fork_for_frame()
	var station_pose: Transform3D=initial.void_environment.objects[0].pose
	var station_camera:=Transform3D(Basis.IDENTITY,station_pose.origin+Vector3(0,0,10000))
	var target_aim:=Vector3(640,360,0)
	var observed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":29,
		"delta_ms":100,"viewport_size":Vector2i(1280,720),"camera_pose":station_camera,"aim_point":target_aim,
		"station":{"environment_slot":0,"pose":station_pose,"active":true},"controller_enabled":true,
		"held_primary":false,"other_selected_target":false,"mining_approach_active":false,
		"alternate_operation_active":false,"selected_target_active":false}
	for _tick in 10:check(target.advance(observed),target.error)
	var scanning: Dictionary=initial.duplicate(true)
	scanning.camera_view.pose=station_camera;scanning.camera_view.eye=station_camera.origin
	scanning.player_aim.point=target_aim;scanning.player_aim.visible=true
	scanning.player_aim.viewport_size=Vector2i(1280,720)
	scanning.void_station_targeting=target.snapshot()
	check(scanning.void_station_targeting.aimed_index==0 and scanning.void_station_targeting.elapsed_ms==1000 and scanning.void_station_targeting.duration_ms==4000,"Original scanner81 did not supply live station acquisition")
	check(scene.present(frame,false,0,scanning),"Native station scan could not present: "+scene.error)
	check(scene.target_frame.visible and scene.reticle.visible and scene.scan_animation.visible and scene.scan_animation._sample.animation_frame==6 and scene.scan_animation._sample.aim_pixels==Vector2i(640,360),"Native station acquisition did not use the original center frame, reticle and scanner strip")
	await capture_station_scan(scene,"void29-station-scan")
	var scan_held: Dictionary=scene.scan_animation._sample.duplicate(true)
	var bad_station: Dictionary=scanning.duplicate(true);bad_station.void_station_targeting.binding_id="foreign"
	check(not scene.present(frame,false,0,bad_station) and scene.scan_animation._sample==scan_held and scene.scan_animation.visible,"Rejected foreign station scan replaced accepted HUD pixels")
	bad_station=scanning.duplicate(true);bad_station.void_station_targeting.duration_ms=0
	check(not scene.present(frame,false,0,bad_station) and scene.scan_animation._sample==scan_held and scene.scan_animation.visible,"Rejected station clock replaced accepted HUD pixels")
	observed.aim_point=Vector3(800,360,0);observed.delta_ms=1
	check(target.advance(observed),target.error)
	var lost_scan: Dictionary=scanning.duplicate(true);lost_scan.void_station_targeting=target.snapshot()
	lost_scan.player_aim.point=observed.aim_point
	check(lost_scan.void_station_targeting.aimed_index==-1 and scene.present(frame,false,0,lost_scan) and scene.scan_animation._sample.animation_frame==initial.mining_targeting.animation_frame and scene.scan_animation._sample.aim_pixels==initial.mining_targeting.aim_pixels,"Lost station aim did not restore the ordinary mining scan sample")
	var audio:=Audio.new();root.add_child(audio)
	if not audio.configure_full_hold(library,bindings,frame):check(false,audio.error);audio.free();scene.free();return
	check(audio._probe_sound==14 and audio._resources.prepare(14).get("spatial",false),"Selected flight did not prepare the original spatial sound14")
	var stage:=Stage.new();var entry: Dictionary=Portal.selected_identity(bindings.mido_travel,29)
	entry.merge({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"mission_story":true,"mission_completed":false,"mission_failed":false})
	if not stage.configure(bindings,entry):check(false,stage.error);audio.free();scene.free();return
	var text:=TextResources.new();var radio:=Radio.new()
	if not text.prepare(library,bindings,null,29) or not radio.configure(bindings,library,text.line_counts,29):check(false,text.error+radio.error);audio.free();scene.free();return
	if not stage.advance_clock(0):check(false,stage.error);audio.free();scene.free();return
	var observation:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":29,"stage_elapsed_ms":0,"mother_ship_locked":true}
	var changes: Array=radio.step_probe(0,observation)
	if not stage.observe_radio(radio,initial.player_pose,initial.camera_view.pose):check(false,stage.error);audio.free();scene.free();return
	var phase1: Dictionary=initial.duplicate(true)
	phase1.void_probe_stage=stage.snapshot();phase1.void_probe=stage.probe_snapshot()
	phase1.radio=radio.snapshot();phase1.radio_events=changes
	phase1.player_aim.visible=true;phase1.void_station_targeting=scanning.void_station_targeting.duplicate(true)
	check(phase1.void_probe_stage.phase==1 and not phase1.void_probe_stage.hud_visible and not phase1.void_probe_stage.target_overlay_visible and phase1.void_probe.visible,"Detached native stage missed its source phase1 flags")
	var cue: Dictionary=phase1.void_probe_stage.frame.cues.back()
	check(cue.kind=="sound_start" and cue.event_id==14 and cue.position is Vector3,"Native stage lost camera-eye sound14")
	if not scene.present(frame,false,0,phase1):check(false,scene.error);audio.free();scene.free();return
	check(scene.probe.visible and scene.probe.model.transform==phase1.void_probe.pose,"Scene did not commit the source probe pose at phase1")
	for overlay in [scene.target_frame,scene.reticle,scene.scan_animation,scene.npc_markers,scene.waypoint_marker,scene.notice_panel]:
		if overlay!=null:check(not overlay.visible,"Probe phase1 left a source-hidden HUD overlay visible")
	await capture(scene,"void29-probe-phase1",phase1.void_probe.pose)
	var corrupted: Dictionary=phase1.duplicate(true);corrupted.void_probe.binding_id="foreign"
	var shown: Transform3D=scene.probe.model.transform
	check(not scene.present(frame,false,0,corrupted) and scene.probe.visible and scene.probe.model.transform==shown,"Rejected probe frame changed the accepted scene")
	corrupted=phase1.duplicate(true);corrupted.radio.binding_id="foreign"
	check(not scene.present(frame,false,0,corrupted) and scene.probe.visible and scene.probe.model.transform==shown,"Late radio rejection failed to restore the accepted probe")
	var invalid_audio:=Audio.new();root.add_child(invalid_audio)
	if invalid_audio.configure_full_hold(library,bindings,frame):
		var bad_sound: Dictionary=phase1.duplicate(true);bad_sound.void_probe_stage.frame.cues.back().event_id=15
		var held: Dictionary=invalid_audio.snapshot()
		check(invalid_audio.prepare_full_hold(frame,bad_sound).is_empty() and invalid_audio.snapshot()==held,"Invalid probe sound cue changed audio before commitment")
	else:check(false,invalid_audio.error)
	invalid_audio.free()
	var before: Dictionary=audio.snapshot()
	var pending: Dictionary=audio.prepare_full_hold(frame,phase1)
	if pending.is_empty():check(false,audio.error);audio.free();scene.free();return
	var starts: Array=pending.operations.filter(func(row):return row.get("action")=="start_spatial" and row.get("source_id")==14)
	check(starts.size()==1 and starts[0].position==cue.position and audio.snapshot()==before,"Probe sound did not stage once at the actual camera eye")
	audio.commit_frame(pending)
	var accepted: Dictionary=audio.snapshot()
	check(accepted.active.has(14) and accepted.active[14].position==cue.position,"Committed probe sound lost its spatial source position")
	var repeat: Dictionary=audio.prepare_full_hold(frame,phase1)
	audio.commit_frame(repeat)
	check(repeat.get("repeat",false) and audio.snapshot()==accepted,"Repeated flight audio serial replayed probe sound14")
	var time:=0
	while not radio.event_state(1).playback_finished and time<60000:
		if not stage.advance_clock(100):check(false,stage.error);break
		time+=100;observation.stage_elapsed_ms=int(stage.snapshot().stage_elapsed_ms)
		radio.step_probe(time,observation)
		if not stage.observe_radio(radio,initial.player_pose,initial.camera_view.pose):check(false,stage.error);break
	check(stage.snapshot().phase==2 and not stage.probe_snapshot().visible and stage.snapshot().hud_visible and stage.snapshot().target_overlay_visible,"Native phase2 failed to retire the probe and restore HUD flags")
	if stage.snapshot().phase==2:
		var phase2: Dictionary=initial.duplicate(true)
		phase2.void_probe_stage=stage.snapshot();phase2.void_probe=stage.probe_snapshot();phase2.radio=radio.snapshot()
		phase2.player_aim.visible=true
		check(scene.present(frame,false,0,phase2) and not scene.probe.visible,"Scene did not retire the original probe at phase2")
		check(scene.target_frame.visible and scene.reticle.visible,"Probe phase2 did not restore its source target HUD")
		phase2.flight_audio.serial=int(initial.flight_audio.serial)+1
		var phase2_audio: Dictionary=audio.prepare_full_hold(frame,phase2)
		check(not phase2_audio.is_empty() and not phase2_audio.get("operations",[]).any(func(row):return row.get("source_id")==14),"Phase2 invented a probe sound restart or stop: "+audio.error)
		if not phase2_audio.is_empty():audio.commit_frame(phase2_audio)
		await capture(scene,"void29-probe-phase2",phase1.void_probe.pose)
		# The acknowledged result changes the mission cursor to30 while the
		# player/ship still occupy Void29 until the original portal accepts contact.
		var return_frame: Dictionary=phase2.duplicate(true)
		return_frame.campaign_cursor=30;return_frame.phase="portal_search"
		var objective_rules: Dictionary=OrdinaryFlight.objective(bindings,29)
		check(not objective_rules.is_empty() and not objective_rules.next_mission.is_empty(),"Void29 lost its canonical next mission")
		return_frame.mission=objective_rules.next_mission.duplicate(true)
		return_frame.mining_objective.campaign_cursor=30
		return_frame.mining_objective.mission=return_frame.mission.duplicate(true)
		return_frame.mining_objective.phase="portal_search"
		return_frame.mining_objective.combat_objective_acknowledged=true
		return_frame.mining_objective.dialogue.visible=false
		return_frame.dialogue.visible=false
		check(scene.present(frame,false,0,return_frame),"Acknowledged30 mission could not remain in its retained Void29 scene: "+scene.error)
		check(scene.geometry.player.visible and not scene.probe.visible and return_frame.player.campaign_cursor==29,"Pending return rebuilt or hid the retained Void player")
		var held_pose: Transform3D=scene.geometry.player.transform
		var invalid_return: Dictionary=return_frame.duplicate(true)
		invalid_return.mission.source_parameter=999
		check(not scene.present(frame,false,0,invalid_return) and scene.geometry.player.transform==held_pose,"Foreign cursor30 mission entered the Void29 scene")
		invalid_return=return_frame.duplicate(true);invalid_return.mining_objective.combat_objective_acknowledged=false
		check(not scene.present(frame,false,0,invalid_return) and scene.geometry.player.transform==held_pose,"Unacknowledged cursor30 objective entered the Void29 scene")
		invalid_return=return_frame.duplicate(true);invalid_return.void_probe_stage.phase=1
		check(not scene.present(frame,false,0,invalid_return) and scene.geometry.player.transform==held_pose,"Unfinished probe stage entered the acknowledged30 scene")
	audio.clear();audio.free();scene.free()

func capture(_scene: Node3D,label: String,pose: Transform3D) -> void:
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	# Inspection close-up only; the source 25,000-unit camera eye makes the
	# original model just a few pixels wide. The runtime camera is unchanged.
	var eye: Vector3=pose.origin+pose.basis.z*1050.0+pose.basis.y*100.0
	var target: Vector3=pose.origin-pose.basis.y*300.0
	var retained: Transform3D=_scene.camera.global_transform
	_scene.camera.global_transform=Transform3D(Basis.looking_at(target-eye,Vector3.UP),eye)
	DirAccess.make_dir_recursive_absolute(captures)
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(label+".png"))==OK,"Could not capture "+label)
	_scene.camera.global_transform=retained

func capture_station_scan(_scene: Node3D,label: String) -> void:
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(captures)
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(label+".png"))==OK,"Could not capture "+label)
