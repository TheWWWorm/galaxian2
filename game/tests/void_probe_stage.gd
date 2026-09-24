extends SceneTree
## Detached radio/stage frames; no career or earned mission is advanced.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Portal=preload("res://src/content/void_portal_definitions.gd")
const Probe=preload("res://src/content/void_probe_definitions.gd")
const Stage=preload("res://src/simulation/void_probe_stage.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const TextResources=preload("res://src/presentation/opening_radio_resources.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")

var checks:=0
var failures:=0
var library: RefCounted
var bindings: RefCounted
var player:=Transform3D(Basis(Vector3.UP,0.4),Vector3(125,40,-350))
var camera:=Transform3D(Basis.IDENTITY,Vector3(900,120,700))
var display_ms:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected explicit content, bindings and visuals");finish();return
	library=Library.new();bindings=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest):
		check(false,library.error+bindings.error);finish();return
	var absent:=Stage.new()
	check(absent.snapshot().is_empty() and absent.probe_snapshot().is_empty() and not absent.completion_ready(1),"Unconfigured stage authorized mission29")
	if not Probe.parameters(bindings.mido_travel.get("void_probe",{})):
		check(not absent.configure(bindings,entry()) and absent.snapshot().is_empty(),"Earlier binding invented probe stage capability")
		finish();return
	check(library.select_language("gb"),library.error)
	verify_admission()
	verify_radio_phases()
	finish()

func entry() -> Dictionary:
	var selected: Dictionary=Portal.selected_identity(bindings.mido_travel,29)
	selected.merge({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"mission_story":true,"mission_completed":false,"mission_failed":false})
	return selected

func earlier_entry(cursor: int) -> Dictionary:
	var selected: Dictionary=Portal.selected_identity(bindings.mido_travel,cursor)
	selected.merge({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"mission_story":true,"mission_completed":false,"mission_failed":false})
	return selected

func fresh() -> RefCounted:
	var stage:=Stage.new()
	check(stage.configure(bindings,entry()),stage.error)
	return stage

func radio_fixture() -> RefCounted:
	var resources:=TextResources.new()
	if not resources.prepare(library,bindings,null,29):check(false,resources.error);return null
	var radio:=Radio.new()
	if not radio.configure(bindings,library,resources.line_counts,29):check(false,radio.error);return null
	return radio

func observation(stage: RefCounted,locked: bool) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":29,"stage_elapsed_ms":int(stage.snapshot().stage_elapsed_ms),
		"mother_ship_locked":locked}

func tick(stage: RefCounted,radio: RefCounted,delta: int,locked: bool,physical: Transform3D=Transform3D.IDENTITY) -> Array:
	if not stage.advance_clock(delta):check(false,stage.error);return []
	display_ms+=delta
	var changes: Array=radio.step_probe(display_ms,observation(stage,locked))
	check(radio.error.is_empty(),radio.error)
	if not stage.observe_radio(radio,player if physical==Transform3D.IDENTITY else physical,camera):check(false,stage.error)
	return changes

func verify_admission() -> void:
	var stage:=fresh();var before: Dictionary=stage.snapshot();var probe: Dictionary=stage.probe_snapshot()
	for cursor in [25,28]:
		var other: Dictionary=earlier_entry(cursor)
		check(Portal.selected(bindings.mido_travel,other),"Expected full valid Void portal context "+str(cursor))
		check(not stage.configure(bindings,other) and stage.snapshot()==before and stage.probe_snapshot()==probe,
			"Another complete Void portal context acquired probe stage "+str(cursor))
	for changed in [{"binding_id":"foreign"},{"base_content_id":"foreign"},{"campaign_cursor":28},
		{"mission_kind":156},{"station_id":91},{"system_id":18},{"current_station_id":91},
		{"void_station_id":91},{"return_station_id":90},{"mission_story":false},
		{"mission_completed":true},{"mission_failed":true}]:
		var bad:=entry();bad.merge(changed,true)
		check(not stage.configure(bindings,bad),"Unselected probe entry was accepted: "+str(changed))
		check(stage.snapshot()==before and stage.probe_snapshot()==probe,"Rejected entry changed the accepted stage")
	check(stage.configure(bindings,entry()),stage.error)
	check(stage.snapshot().phase==0 and stage.snapshot().stage_elapsed_ms==0 and not stage.probe_snapshot().visible,"Probe was visible before its source lock")
	check(stage.probe_snapshot().model_id==14290 and stage.probe_snapshot().base_content_id==bindings.base_content_id,"Probe snapshot lost original model/content identity")
	check(not stage.observe_radio(Radio.new(),player,camera),"Stage observed radio before advancing its clock")
	var stable: Dictionary=stage.snapshot()
	for invalid in [-1,Frames.simulation_limit(bindings)+1,1.0]:
		check(not stage.advance_clock(invalid) and stage.snapshot()==stable,"Invalid native frame changed the stage clock")
	check(stage.advance_clock(0),stage.error)
	check(not stage.advance_clock(0),"Stage allowed two clock increments before one radio tick")
	check(stage.snapshot().stage_elapsed_ms==0,"Rejected second increment changed stage time")
	check(not stage.observe_radio(Radio.new(),player,camera),"Unconfigured radio passed the stage identity gate")
	check(stage.snapshot().stage_elapsed_ms==0,"Rejected radio changed stage time")
	var radio:=radio_fixture()
	if radio==null:return
	check(not stage.observe_radio(radio,Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),camera),"Invalid physical pose passed")
	check(not stage.observe_radio(radio,player,Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))),"Invalid camera pose passed")
	check(stage.observe_radio(radio,player,camera),stage.error)
	check(stage.snapshot().phase==0 and stage.snapshot().frame.cues.is_empty(),"Invalid input or absent lock triggered phase1")
	var vertical:=Transform3D(Basis(Vector3.RIGHT,-PI/2.0),Vector3(5,6,7))
	var vertical_stage:=fresh();var vertical_radio:=radio_fixture()
	if vertical_radio==null:return
	check(vertical_stage.advance_clock(0),vertical_stage.error)
	check(vertical_radio.step_probe(0,observation(vertical_stage,true))==[{"kind":"started","event":0}],"Vertical source lock did not start radio")
	check(vertical_stage.observe_radio(vertical_radio,vertical,camera),vertical_stage.error)
	var vertical_probe: Dictionary=vertical_stage.probe_snapshot()
	check(vertical_stage.snapshot().phase==1 and vertical_probe.visible and vertical_probe.pose.origin==vertical.origin and vertical_probe.pose.basis.z.distance_to(vertical.basis.z)<0.0001,"Exactly vertical player flight blocked probe or changed its forward axis")

func verify_radio_phases() -> void:
	display_ms=0
	var stage:=fresh();var radio:=radio_fixture()
	if radio==null:return
	for i in 10:tick(stage,radio,100,false)
	check(stage.snapshot().phase==0 and stage.snapshot().stage_elapsed_ms==1000 and not stage.completion_ready(1),"Elapsed time alone triggered probe or result")
	var physical_before:=player;var camera_before:=camera
	var start: Array=tick(stage,radio,100,true)
	var phase1: Dictionary=stage.snapshot();var launched: Dictionary=stage.probe_snapshot()
	check(start==[{"kind":"started","event":0}] and phase1.phase==1 and radio.event_state(0)=={"condition_satisfied":true,"playback_finished":false},"Phase1 waited for radio playback rather than lock condition")
	check(phase1.input_blocked and phase1.scripted_coast and not phase1.damage_enabled and not phase1.hud_visible and not phase1.target_overlay_visible and not phase1.environment_targeting_enabled and phase1.scripted_camera,"Phase1 lost source control/damage/HUD gates")
	var kinds: Array=phase1.frame.cues.map(func(cue):return cue.kind)
	check(kinds==["primary_trigger","player_coast","input_blocked","player_damage","hud_visibility",
		"target_overlay_visibility","environment_targeting","camera_scripted","camera_target","camera_initial_offsets",
		"camera_reset_offset","camera_eye","probe_spawn","camera_target","sound_start"],"Phase1 lost or repeated source one-time cues")
	check(phase1.frame.cues[0].enabled==false and phase1.frame.cues[6].enabled==false and phase1.frame.cues[8].target=="player_root" and phase1.frame.cues[13].target=="probe_model","Phase1 failed primary cancel, targeting or camera target order")
	check(phase1.frame.cues[9].first==Vector3(0,600,-650) and phase1.frame.cues[9].second==Vector3(0,600,-1338) and phase1.frame.cues[10].offset==Vector3(0,150,-800),"Phase1 lost original camera offsets")
	var eye: Vector3=player.origin+player.basis.z*25000+player.basis.x*1000+player.basis.y*1000
	check(phase1.frame.cues[11].position.distance_to(eye)<0.01 and phase1.frame.cues[14].event_id==14 and phase1.frame.cues[14].position==phase1.frame.cues[11].position,"Probe eye or sound14 changed source coordinates")
	check(launched.visible and launched.model_time_ms==0 and launched.pose.origin==player.origin and launched.pose.basis.z.distance_to(player.basis.z)<0.0001 and launched.pose.basis.y.dot(Vector3.UP)>0.8,"Probe did not spawn at the rigid physical root with source orientation")
	check(player==physical_before and camera==camera_before,"Stage changed caller-owned physical poses")
	var static_pose: Transform3D=launched.pose
	var moved_player:=Transform3D(Basis(Vector3.RIGHT,0.2),Vector3(-900,50,1200))
	var held: Dictionary=stage.snapshot();var fork: RefCounted=stage.fork_for_frame()
	check(fork.snapshot()==held and fork.probe_snapshot()==launched,"Fork lost phase1 or static probe state")
	for i in 2:tick(stage,radio,100,true,moved_player)
	check(stage.probe_snapshot().pose==static_pose and stage.probe_snapshot().model_time_ms==200 and stage.snapshot().frame.cues.is_empty(),"Probe followed a moving player or repeated launch cues")
	var detached: Dictionary=stage.probe_snapshot();detached.visible=false;detached.model_time_ms=999
	check(stage.probe_snapshot().visible and stage.probe_snapshot().model_time_ms==200,"Caller changed owned probe snapshot")
	var loops:=0
	while not radio.event_state(1).playback_finished and loops<500:
		var prior: Dictionary=radio.event_state(1)
		tick(stage,radio,100,true,moved_player)
		if prior.condition_satisfied and not radio.event_state(1).playback_finished:
			check(stage.snapshot().phase==1,"Row1 condition prematurely ended phase1")
		loops+=1
	check(loops<500 and radio.event_state(1).playback_finished,"Source row1 playback did not finish in bounded radio time")
	var phase2: Dictionary=stage.snapshot();var retired: Dictionary=stage.probe_snapshot()
	check(phase2.phase==2 and phase2.stage_elapsed_ms==0 and not retired.visible and retired.pose==static_pose,"Phase2 failed to reset only stage time or retire the static probe")
	check(not phase2.input_blocked and not phase2.scripted_coast and phase2.damage_enabled and phase2.hud_visible and phase2.target_overlay_visible and phase2.environment_targeting_enabled and not phase2.scripted_camera,"Phase2 did not restore source-defined gates")
	kinds=phase2.frame.cues.map(func(cue):return cue.kind)
	check(kinds==["probe_despawn","camera_target","camera_scripted","hud_visibility","target_overlay_visibility","environment_targeting","player_damage","player_coast","input_blocked"] and phase2.frame.cues[1].target=="player_root" and phase2.frame.cues[5].enabled,"Phase2 restored unproved primary/sound state or lost camera/target return")
	check(not stage.completion_ready(1) and not stage.completion_ready(0),"Phase2 reset immediately completed survival")
	var reset_display:=display_ms
	check(tick(stage,radio,100,true)==[{"kind":"started","event":2}] and stage.snapshot().stage_elapsed_ms==100 and display_ms>reset_display,"Post-reset row2 did not start on the next monotonic radio tick")
	check(stage.snapshot().frame.cues.is_empty(),"Phase2 one-time cues repeated")
	# Exercise the real radio owner while the stage clock reaches the exact
	# strict survival boundary. This is component time, not earned progress.
	var step:=Frames.simulation_limit(bindings)
	while stage.snapshot().stage_elapsed_ms<180000:
		var remain: int=180000-int(stage.snapshot().stage_elapsed_ms)
		tick(stage,radio,mini(step,remain),true)
	check(stage.snapshot().stage_elapsed_ms==180000 and not stage.completion_ready(1),"Inclusive three-minute boundary completed the probe")
	tick(stage,radio,1,true)
	check(stage.snapshot().stage_elapsed_ms==180001 and stage.completion_ready(1) and not stage.completion_ready(0) and not stage.completion_ready(-1) and not stage.completion_ready(1.0),"Strict living-hull result boundary changed")
	check(stage.snapshot().campaign_cursor==29 and not stage.snapshot().has("reward") and not stage.snapshot().has("next_cursor"),"Stage invented mission advancement or reward")
	check(stage.probe_snapshot().pose==static_pose and not stage.probe_snapshot().visible,"Survival clock moved or respawned the probe")
	stage.clear_frame_cues();check(stage.snapshot().frame.cues.is_empty() and stage.completion_ready(1),"Clearing transient cues changed earned component time")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+message)

func finish() -> void:
	print("Void probe stage: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
