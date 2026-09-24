extends SceneTree
## Explicit observations test the native owner, not earned campaign progress.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Owner=preload("res://src/simulation/sahi_encounter_stage.gd")
const Rules=preload("res://src/content/sahi_stage_definitions.gd")
const Geometry=preload("res://src/presentation/sahi_portal_geometry.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
var checks:=0
var failures:=0
var library: RefCounted
var bindings: RefCounted
var player:=Transform3D(Basis.IDENTITY,Vector3(10,20,30))
var camera:=Transform3D(Basis.IDENTITY,Vector3(10510,720,1030))

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, bindings and visuals");quit(1);return
	library=Library.new();bindings=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest):check(false,library.error+bindings.error);quit(1);return
	var absent:=Owner.new()
	check(absent.snapshot().is_empty() and absent.portal_snapshot().is_empty() and not absent.transition_ready(1),"Unconfigured stage authorized an entry")
	if not Rules.selected(bindings.mido_travel,entry()):
		check(not absent.configure(bindings,entry(),library) and absent.snapshot().is_empty(),"Older pack inferred Sahi stage support")
		print("Sahi stage owner: %d checks; %d failures (missing capability guard only)"%[checks,failures]);quit(1 if failures else 0);return
	verify_admission()
	verify_sequence()
	verify_clock()
	verify_contacts()
	verify_render_contract(args[2])
	print("Sahi stage owner: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func entry() -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":24,"system_id":9,"station_id":48,"mission_kind":4,
		"mission_story":true,"mission_completed":false,"mission_failed":false,
		"current_station_id":48,"void_station_id":-1,"current_station_special":false,
		"environment_object":{"resource_id":16994,"position":Vector3(1000,2000,3000)}}

func flags() -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":24,
		"started":[false,false,false,false,false],"finished":[false,false,false,false,false]}

func fresh() -> RefCounted:
	var owner:=Owner.new();check(owner.configure(bindings,entry(),library),owner.error);return owner

func open_flags() -> Dictionary:
	var radio:=flags();radio.started[3]=true;radio.started[4]=true;return radio

func opened() -> RefCounted:
	var owner:=fresh();var radio:=open_flags()
	check(owner.advance_stage(0,radio,player,camera) and owner.advance_stage(0,radio,player,camera),owner.error)
	check(owner.advance_portal(0,camera),owner.error)
	return owner

func frame(owner: RefCounted,delta: int,radio: Dictionary) -> bool:
	return owner.advance_stage(delta,radio,player,camera) and owner.advance_portal(delta,camera)

func verify_admission() -> void:
	var owner:=fresh();var before: Dictionary=owner.snapshot();var portal: Dictionary=owner.portal_snapshot()
	for change in [{"binding_id":"foreign"},{"campaign_cursor":25},{"station_id":49},{"mission_completed":true},
		{"mission_failed":true},{"mission_story":false},{"current_station_id":6},{"current_station_id":-1},
		{"current_station_id":48.0},{"void_station_id":48},{"current_station_special":true},
		{"current_station_special":null},{"environment_object":{"resource_id":16995,"position":Vector3.ZERO}},
		{"environment_object":{"resource_id":16994,"position":Vector3(INF,0,0)}}]:
		var bad:=entry();bad.merge(change,true)
		check(not owner.configure(bindings,bad,library),"Unsupported Sahi entry was accepted: "+str(change))
		check(owner.snapshot()==before and owner.portal_snapshot()==portal,"Rejected admission changed an accepted stage")
	var retained:=entry();check(owner.configure(bindings,retained,library),owner.error)
	retained.station_id=49;retained.environment_object.position=Vector3.ZERO
	check(owner.portal_snapshot().position==Vector3(1000,2000,3000),"Stage retained caller-owned mutable entry data")

func verify_sequence() -> void:
	var owner:=fresh();var radio:=flags()
	for i in 40:
		if not frame(owner,150,radio):check(false,owner.error);return
	check(owner.snapshot().phase==0 and owner.snapshot().elapsed_ms==0 and not owner.snapshot().input_blocked,"Elapsed time invented a Sahi stage transition")
	check(not owner.portal_snapshot().visible and owner.portal_snapshot().elapsed_ms==0 and owner.portal_snapshot().animation_elapsed_ms==6000,"Hidden portal stopped model playback or advanced its appearance")
	radio=open_flags();var input:=radio.duplicate(true)
	check(owner.advance_stage(150,radio,player,camera),owner.error)
	var view: Dictionary=owner.snapshot();var portal: Dictionary=owner.portal_snapshot()
	check(view.phase==1 and not portal.visible and not view.player_update_suspended,"Event3 skipped the view or froze whole-player updates")
	check(view.input_blocked and not view.hud_visible and not view.target_overlay_visible and not view.damage_enabled and view.scripted_coast,"View gates differ from the accepted source")
	var kinds: Array=view.frame.cues.map(func(cue):return cue.kind)
	check(kinds==["primary_trigger","hud_visibility","target_overlay_visibility","player_damage","player_coast",
		"discard_flight_weapons","clear_npc_weapon_targets","player_physical_pose","camera_target","camera_eye",
		"portal_position","rebase_starfield","input_blocked"],"View operations lost their source order or conflated inventory/targets")
	var physical: Transform3D=view.frame.cues[7].pose
	check(physical.origin==player.origin and physical.basis.z.is_equal_approx(Vector3.RIGHT),"View yaw changed the physical origin or forward axis")
	check(portal.position.distance_to(Vector3(45010,20,30))<0.005,"Portal placement did not use the newly oriented physical forward")
	check(view.frame.cues[9]=={"kind":"camera_eye","position":Vector3(10510,720,1030),"previous_position":Vector3(10510,720,1030),"reset_interpolation":true},"Camera eye lost its actual player-relative position/history reset")
	check(radio==input and not owner.transition_ready(100),"Observing radio mutated input or authorized a transition")
	check(owner.advance_portal(150,camera),owner.error)
	check(owner.portal_snapshot().animation_elapsed_ms==6150 and owner.portal_snapshot().elapsed_ms==0,"Hidden view mixed its two clocks")
	check(owner.advance_stage(150,radio,player,camera),owner.error)
	var opening: Dictionary=owner.snapshot()
	kinds=opening.frame.cues.map(func(cue):return cue.kind)
	check(opening.phase==2 and opening.elapsed_ms==150 and kinds==["portal_visible","portal_reset","portal_open","sound_start","sound_position","camera_shake","player_visual_rotation"],"Opening failed to run the same-frame spin/sound cues")
	check(opening.frame.cues[1].closing==false and opening.frame.cues[2].elapsed_ms==-3000 and opening.frame.cues[2].extent==0,"Opening used the closing reset or skipped zero extent")
	check(opening.frame.cues[3].event_id==34 and opening.frame.cues[4].position==camera.origin and opening.frame.cues[4].velocity==Vector3.ZERO,"Portal sound lost its source identity/position")
	check(opening.frame.cues[5].shake_kind==3 and opening.frame.cues[5].amount==50.0,"Sahi camera shake changed")
	check(opening.frame.cues[6].delta.is_equal_approx(Vector3.ONE*0.03),"Spin did not use milliseconds/5000 on all visual axes")
	check(not kinds.has("player_physical_pose") and not owner.transition_ready(100),"Spin altered the root pose or finished the mission")
	check(owner.advance_portal(150,camera) and owner.portal_snapshot().elapsed_ms==-2850 and owner.portal_snapshot().extent==205,"World update lost the opening clock order")
	var retained_state: Dictionary=owner.snapshot();var retained_portal: Dictionary=owner.portal_snapshot()
	var fork: RefCounted=owner.fork_for_frame()
	check(frame(fork,150,radio) and owner.snapshot()==retained_state and owner.portal_snapshot()==retained_portal,"Forked stage changed its retained owner")
	var detached: Dictionary=fork.snapshot();detached.frame.cues.clear()
	var detached_portal: Dictionary=fork.portal_snapshot();detached_portal.animation.time_ms=999
	check(not fork.snapshot().frame.cues.is_empty() and fork.portal_snapshot().animation.time_ms!=999,"Returned snapshot mutated an owner")
	for delta in [-1,Frames.simulation_limit(bindings)+1,150.0]:
		check(not owner.advance_stage(delta,radio,player,camera) and not owner.advance_portal(delta,camera),"Invalid source frame was accepted")
		check(owner.snapshot()==retained_state and owner.portal_snapshot()==retained_portal,"Rejected duration changed a retained frame")
	for change in [{"binding_id":"foreign"},{"started":[false,false,false,false,false]},
		{"started":[true]},{"finished":[false,false,false,1,false]},{"finished":[true,false,false,false,false]}]:
		var bad:=radio.duplicate(true);bad.merge(change,true)
		check(not owner.advance_stage(1,bad,player,camera) and owner.snapshot()==retained_state,"Foreign, malformed or regressed radio changed stage state")
	check(not owner.advance_stage(1,radio,Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),camera),"Nonfinite physical pose was accepted")
	check(not owner.advance_portal(1,Transform3D(Basis.IDENTITY,Vector3(0,INF,0))) and owner.portal_snapshot()==retained_portal,"Invalid camera changed the portal")
	owner.clear_frame_cues();check(owner.snapshot().frame.is_empty() and owner.snapshot().phase==2,"Clearing transient cues reset the phase")
	check(frame(owner,150,radio) and owner.snapshot().frame.cues.map(func(cue):return cue.kind)==["sound_position","camera_shake","player_visual_rotation"],"Open phase repeated one-time view/open operations")

func verify_clock() -> void:
	var owner:=opened();var radio:=open_flags()
	for i in 19:
		if not frame(owner,150,radio):check(false,owner.error);return
	check(owner.portal_snapshot().elapsed_ms==-150 and owner.portal_snapshot().extent==3892,"Opening lost its source binary32 extent")
	check(frame(owner,150,radio) and owner.portal_snapshot().elapsed_ms==0 and owner.portal_snapshot().extent==3892,"Zero boundary rewrote the source's retained partial opening extent")
	check(owner.portal_snapshot().scale==0.9501953125,"Source extent-to-model scale changed")
	while owner.portal_snapshot().elapsed_ms<60000:
		if not frame(owner,150,radio):check(false,owner.error);return
	check(owner.portal_snapshot().visible and owner.portal_snapshot().extent==3892 and not owner.transition_ready(100),"Elapsed/radio time completed the encounter or closed early")
	check(frame(owner,150,radio) and owner.portal_snapshot().extent==3892,"Closing clock changed the first source extent")
	while owner.portal_snapshot().elapsed_ms<63000:
		if not frame(owner,150,radio):check(false,owner.error);return
	check(owner.portal_snapshot().visible and owner.portal_snapshot().extent==0,"Portal hid at the inclusive zero-extent boundary")
	check(frame(owner,1,radio) and not owner.portal_snapshot().visible and owner.portal_snapshot().extent==-1,"Ordinary portal missed its source hide boundary")
	var closed: Dictionary=owner.portal_snapshot()
	check(frame(owner,150,radio) and owner.portal_snapshot().elapsed_ms==closed.elapsed_ms and owner.portal_snapshot().animation_elapsed_ms==closed.animation_elapsed_ms+150,"Closed portal mixed appearance/model time")
	check(owner.portal_snapshot().position==closed.position and not owner.transition_ready(100),"Ordinary distinct-station close relocated or completed the mission")
	var finished:=radio.duplicate(true);finished.finished[3]=true;finished.finished[4]=true
	check(frame(owner,150,finished) and not owner.transition_ready(100),"Finished radio invented portal entry")

func contact(owner: RefCounted,offset: Vector3,enabled:=true,mining:=false) -> Dictionary:
	return {"player_pose":Transform3D(Basis.IDENTITY,owner.portal_snapshot().position+offset),
		"environment_contact_enabled":enabled,"mining_active":mining}

func verify_contacts() -> void:
	var hidden:=fresh()
	check(hidden.observe_contact(contact(hidden,Vector3.ZERO)) and hidden.snapshot().contact.is_empty() and not hidden.transition_ready(1),"Hidden portal accepted entry")
	var owner:=opened()
	for observation in [contact(owner,Vector3.ZERO,false),contact(owner,Vector3.ZERO,true,true),
		contact(owner,Vector3(40000,0,0)),contact(owner,Vector3(-40000,0,0)),contact(owner,Vector3(30000,30000,0))]:
		check(owner.observe_contact(observation) and owner.snapshot().contact.is_empty() and not owner.transition_ready(1),"Portal ignored environment/mining/cube/radius admission")
	check(owner.observe_contact(contact(owner,Vector3(39999,0,0))) and owner.snapshot().contact.pull_distance==0 and not owner.snapshot().contact.entry_contact,"Outer portal contact lost a valid zero pull")
	check(owner.observe_contact(contact(owner,Vector3(1000,0,0))) and owner.snapshot().contact.pull_distance==152 and not owner.transition_ready(1),"1000-unit boundary accepted entry or changed integer pull")
	var before: Dictionary=owner.snapshot();var observation:=contact(owner,Vector3(1000,0,0));var retained:=observation.duplicate(true)
	check(owner.observe_contact(observation) and owner.snapshot().contact.pull_distance==152 and observation==retained,"Repeated contact used delta time or moved caller-owned state")
	for change in [{"mining_active":1},{"environment_contact_enabled":null},{"player_pose":Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))}]:
		var bad:=observation.duplicate(true);bad.merge(change,true)
		check(not owner.observe_contact(bad) and owner.snapshot()==before,"Malformed contact changed the retained stage")
	check(owner.observe_contact(contact(owner,Vector3(999.5,0,0))) and owner.snapshot().contact.distance==999 and owner.snapshot().portal_entered,"Opening portal did not earn strict pre-pull entry")
	check(owner.transition_ready(1) and not owner.transition_ready(0) and not owner.transition_ready(-1) and not owner.transition_ready(1.0),"Portal entry lost the positive integer hull guard")
	check(owner.snapshot().campaign_cursor==24 and not owner.snapshot().has("reward") and not owner.snapshot().has("next_cursor"),"Contact advanced or rewarded a career")
	check(owner.observe_contact(contact(owner,Vector3.ZERO,false)) and owner.snapshot().portal_entered,"Later ineligible contact erased the earned entry flag")
	var closing:=opened();var radio:=open_flags()
	while closing.portal_snapshot().elapsed_ms<=60000:
		if not frame(closing,150,radio):check(false,closing.error);return
	check(closing.observe_contact(contact(closing,Vector3.ZERO)) and closing.snapshot().contact.is_empty() and not closing.transition_ready(1),"Closing portal accepted a new contact")

func verify_render_contract(path: String) -> void:
	var visuals:=Visuals.new()
	if not visuals.open(path,library.manifest):check(false,visuals.error);return
	var geometry:=Geometry.new();root.add_child(geometry)
	if not geometry.build(library,visuals,bindings,entry()):check(false,geometry.error);geometry.free();return
	var owner:=fresh();var radio:=open_flags()
	check(not geometry.prepare_state(owner.portal_snapshot()).is_empty(),"Initial native portal snapshot failed its renderer")
	check(frame(owner,150,radio),owner.error)
	check(not geometry.prepare_state(owner.portal_snapshot()).is_empty(),"View native portal snapshot failed its renderer")
	check(frame(owner,150,radio),owner.error)
	var prepared: Dictionary=geometry.prepare_state(owner.portal_snapshot())
	check(not prepared.is_empty(),geometry.error)
	if not prepared.is_empty():geometry.commit_state(prepared)
	check(geometry.visible and owner.portal_snapshot().phase==2,"Accepted native owner failed the renderer integration contract")
	geometry.free()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
