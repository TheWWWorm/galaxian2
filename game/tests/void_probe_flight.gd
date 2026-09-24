extends "res://tests/void_probe_construction.gd"
## A selected component flight. The earned Dima-to-Void route is tested by the
## application; every pose, contact, stage and clock here comes from evaluate.
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Pilot=preload("res://tests/fixtures/expedition_flight_pilot.gd")
var _scene: Node3D
var _phase2_branch: RefCounted

func test_label() -> String:return "Void probe selected live flight"

func after_probe_prepared(library: RefCounted,bindings: RefCounted,cat: RefCounted,_construction: RefCounted,frame: RefCounted) -> void:
	_phase2_branch=null
	var visuals:=Visuals.new()
	if not visuals.open(visual_path,library.manifest):check(false,visuals.error);return
	root.size=Vector2i(1280,720)
	_scene=Scene.new();root.add_child(_scene)
	if not _scene.build(library,bindings,visuals,cat,frame):check(false,"Probe scene: "+_scene.error);_scene.free();return
	var initial: Dictionary=frame.snapshot()
	var station: Dictionary=frame.void_environment_owner().object_state(0)
	check(initial.campaign_cursor==29 and initial.location.station_id==-1 and initial.location.return_station_id==91 and initial.actors.size()==3,"Probe flight lost selected Void29 source world/cast")
	check(station.kind=="station" and station.pose.origin==Vector3.ZERO and initial.void_environment.objects.size()==2,"Probe flight lost its original environment slot0")
	check(initial.void_station_targeting.scanner_id==81 and initial.void_station_targeting.duration_ms==4000 and not initial.void_station_targeting.mother_ship_locked,"Selected ship lost source scanner81/4s lock")
	check(initial.void_probe_stage.phase==0 and not initial.void_probe.visible and not frame.void_return_required() and initial.mining_objective.phase=="collecting","Initial probe/portal state was prematurely admitted")
	check(initial.cargo.used==0 and initial.mining_objective.mission.reward==0,"Selected component invented expedition cargo or payment")
	var result: RefCounted=await Pilot.complete_probe(frame,Callable(self,"advance_flight"),Callable(self,"capture_frame"),Callable(self,"check"),process_frame,Callable(self,"navigate_flight"),Callable(self,"retain_phase2"))
	if result==null:_scene.free();return
	var shown: Dictionary=result.snapshot()
	var source: Dictionary=bindings.mido_travel.void_probe.mission29
	check(shown.dialogue.text_id==int(source.result_events[0].text_id) and shown.dialogue.voice_event_id==int(source.result_events[0].voice_event_id),"Live result differs from the selected source line")
	check(shown.mining_objective.phase=="return_instructions" and shown.mining_objective.mission_completed and shown.void_probe_stage.stage_elapsed_ms>180000 and shown.player.vitals.hull>0,"Probe result missed its native survival condition")
	check(shown.cargo==initial.cargo and shown.progress.player_kills==initial.progress.player_kills and shown.progress.pirate_kills==initial.progress.pirate_kills and shown.progress.get("cargo_recovered",0)==initial.progress.get("cargo_recovered",0),"Probe wait fabricated cargo or combat progress")
	check(shown.actors.size()==3 and shown.actors.all(func(actor):return actor.hostile and actor.vitals.hull>0),"Probe survival invented a kill quota or silently removed the hostile cast")
	check(not result.void_return_required() and not shown.void_portal_contact.portal_entered,"Result-open admitted the selected29 portal")
	if _phase2_branch==null:check(false,"Live phase2 frame was not retained for the pre-Next contact branch")
	else:
		var pre_ack: RefCounted=await Pilot.pre_ack_portal_contact(_phase2_branch,Callable(self,"advance_flight"),Callable(self,"check"),process_frame)
		check(pre_ack!=null and not pre_ack.void_return_required() and result.snapshot()==shown,"Physical pre-Next contact advanced the selected mission or changed the independent result frame")
	var acknowledged: RefCounted=navigate_flight(result,"next")
	if acknowledged==null:check(false,"Probe result Next: "+result.error);_scene.free();return
	var retired: Dictionary=acknowledged.snapshot()
	check(retired.campaign_cursor==30 and retired.location.station_id==-1 and retired.mining_objective.phase=="portal_search" and retired.mining_objective.combat_objective_acknowledged,"Final probe Next failed to retire mission29 in its current Void world")
	check(retired.mission.kind==156 and retired.mission.station_id==91 and retired.mission.reward==0 and retired.cargo==shown.cargo,"Final probe Next changed the pending return mission or granted cargo/reward")
	check(not acknowledged.void_return_required(),"Result Next entered the distant portal without physical contact")
	var contact: RefCounted=await Pilot.enter_portal(acknowledged,Callable(self,"advance_flight"),Callable(self,"capture_frame"),Callable(self,"check"),process_frame)
	if contact!=null:
		var accepted: Dictionary=contact.snapshot()
		check(contact.void_return_required() and accepted.boundary=="void_return_transition_required" and accepted.campaign_cursor==30 and accepted.player.vitals.hull>0,"Actual post-Next contact did not require a living player return")
		check(accepted.mining_objective.phase=="portal_search" and accepted.location.station_id==-1 and accepted.cargo==shown.cargo,"Portal contact changed the current world or inventory before application adoption")
	_scene.free()

func advance_flight(frame: RefCounted,ms: int,commands: Vector2,throttle: float,fire: bool) -> RefCounted:
	return frame.evaluate(ms,commands,throttle,false,Vector2i.ZERO,Vector2.ZERO,fire)

func navigate_flight(frame: RefCounted,action: String) -> RefCounted:return frame.navigate(action)
func retain_phase2(frame: RefCounted) -> void:_phase2_branch=frame

func capture_frame(_unused_scene: Node3D,frame: RefCounted,label: String) -> void:
	var state: Dictionary=frame.snapshot()
	if not _scene.present(frame):check(false,_scene.error);return
	if label=="void29-probe-live-phase1":check(_scene.probe!=null and _scene.probe.visible and _scene.probe.model!=null and _scene.probe.model.transform==state.void_probe.pose,"Live phase1 probe did not render at its source pose")
	elif label=="void29-probe-live-phase2":check(_scene.probe!=null and not _scene.probe.visible,"Live phase2 did not retire the rendered probe")
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(captures)
	await process_frame
	RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(label+".png"))==OK,"Cannot capture "+label)
