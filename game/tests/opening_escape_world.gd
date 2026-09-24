extends SceneTree
const Frame=preload("res://src/simulation/opening_world_frame.gd")
const Timeline=preload("res://src/simulation/opening_detail_timeline.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Deaths=preload("res://src/content/npc_destruction_resources.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const EscapeCamera=preload("res://src/simulation/opening_escape_camera.gd")
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Opening escape world checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not catalogues.open(library):check(false,library.error+bindings.error+catalogues.error);return
	var bodies:=Bodies.new();var effects:=Effects.new();var deaths:=Deaths.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not deaths.configure(library,bindings):check(false,bodies.error+effects.error+deaths.error);return
	var scenery:=Scenery.new();var frame:=Frame.new();var timeline:=Timeline.new()
	var radio:=RadioResources.new()
	if not radio.prepare(library,bindings):check(false,radio.error);return
	if not scenery.configure(bindings,catalogues,1789100000,true,bodies,effects) or not scenery.complete_world_initialization(bindings,catalogues):check(false,scenery.error);return
	if not frame.configure(bindings,catalogues,scenery,0.5,deaths) or not timeline.configure(bindings,catalogues,library,radio.line_counts,1.0,0.5):check(false,frame.error+timeline.error);return
	if bindings.opening_staging.get("escape_camera",{}).is_empty():
		check(not timeline.configure_escape(bindings,library),"Legacy timeline acquired escape support");return
	if not timeline.configure_escape(bindings,library) or not frame.configure_player_flight(bindings,catalogues,library,scenery,1.0):check(false,timeline.error+frame.error);return
	check(not timeline.configure_escape(bindings,library),"Escape reset an existing timeline")
	var state:={"world_frame":frame,"timeline":timeline,"scenery":scenery}
	for tick in 1500:
		state=step(state,100)
		if state.is_empty():return
		if state.timeline.snapshot().camera.shot.phase==4:break
	if state.timeline.snapshot().camera.shot.phase!=4:check(false,"Opening never released player flight");return
	# Controlled launch positions exercise original weapons and full original
	# hulls through live contact/death ownership. This is not pilot playtesting.
	var launches:=0
	for tick in 100:
		var alive:=false
		for actor in state.timeline.snapshot().combat.actors:
			if actor.vitals.hull<=0:continue
			alive=true
			var gun: RefCounted=state.world_frame._primaries._guns[0].projectiles
			gun._elapsed_ms=int(gun.snapshot().weapon.interval_ms)+1
			check(gun.fire(actor.pose.origin,Vector3.BACK,true).get("fired",false),gun.error)
			launches+=1
		if not alive:break
		state=step(state,100)
		if state.is_empty():return
	for actor in state.timeline.snapshot().combat.actors:check(actor.vitals.hull==0,"Original full NPC hull survived contact fixture")
	var kills: Dictionary=state.world_frame.snapshot().controller.death_accounting
	check(kills.counter_deltas.player_kills==3 and kills.events.size()==3,"Encounter did not earn exactly three player kills")
	var entered:=false;var relocated:=false;var two_passes:=false;var arrival:=false;var drift:=false;var cut:=false;var reached:=false
	var phases:={};var camera:=EscapeCamera.new();check(camera.configure(bindings),camera.error)
	var cadence: Array[int]=[16,33,150,17,149]
	var last_phase:=4
	var closest_entry_eye:=INF
	var radio_camera_distances:={}
	for tick in 5000:
		var delta_ms: int=cadence[tick%cadence.size()]
		var before: Dictionary=state.timeline.snapshot()
		if int(before.camera.shot.phase)==16:
			check(before.radio.finished[22],"Fade preceded final radio")
			for finished in before.radio.finished:check(finished,"Escape skipped an original transmission")
			check(before.escape.boundary.is_empty(),"Fade request already completed arrival")
			state=step(state,100,false)
			if state.is_empty():return
			check(state.timeline.snapshot().escape.boundary=="arrival_transition_required","Completed external fade failed to expose arrival boundary")
			reached=true;break
		var next:=step(state,delta_ms)
		if next.is_empty():return
		var after: Dictionary=next.timeline.snapshot()
		var phase:=int(after.camera.shot.phase);phases[phase]=true
		var camera_distance: float=after.camera.view.eye.distance_to(after.scene.player_pose.origin)
		if phase==5:closest_entry_eye=minf(closest_entry_eye,camera_distance)
		for event in [12,13]:
			if after.radio.started[event] and not before.radio.started[event]:
				radio_camera_distances[event]=camera_distance
				print("Escape radio %d in phase %d: eye-to-player %.1f units" % [event,phase,camera_distance])
		if phase!=last_phase:
			print("Escape phase %d at %d ms; player visible=%s, detail=%s, camera distance=%.1f" % [phase,after.elapsed_ms,str(after.escape.ship_visible),str(after.scene.ship_detail.selections.player),camera_distance])
			last_phase=phase
		if phase==5 and not entered:
			check(before.radio.finished[10] and int(before.camera.shot.phase)==4,"Escape consumed radio before its preceding frame")
			check(after.escape.frame.entry and after.scene.player_pose.origin==next.world_frame.snapshot().player_motion.pose.origin,"Entry discarded the last ordinary player travel")
			check(after.escape.input_blocked and not after.escape.hud_visible and next.world_frame.snapshot().primary_fire.is_empty(),"Escape accepted held fire or released HUD")
			entered=true
		if phase>4:
			var e: Dictionary=after.escape
			if int(before.camera.shot.phase)>4:
				var expected_position: Vector3=before.scene.player_pose.origin+before.scene.player_pose.basis.z.normalized()*(float(before.escape.cruise_speed)*float(delta_ms))
				check(next.world_frame.snapshot().player_motion.pose.origin.is_equal_approx(expected_position),"Escape movement used a later speed or visual rotation")
				if int(before.camera.shot.phase)==5 and phase==5:check(after.scene.player_pose.origin.x>before.scene.player_pose.origin.x,"Source positive-yaw escape failed to approach its positive-X fixed eye")
			var expected: Dictionary=camera.evaluate(delta_ms,e,after.scene.player_pose,before.camera.view,state.scenery.snapshot().random_state)
			check(not expected.is_empty() and expected.random_state==e.random_state and expected.camera==after.camera,"World camera consumed a different random stream")
			if phase in [5,6]:
				check(e.ship_visible and after.scene.ship_detail.selections.player.visible,"Source opening escape unexpectedly hid or culled the player")
			if phase in [8,9,10,11]:check(not e.ship_visible,"Source hyperdrive phase restored the player early")
			if phase in [12,13,14,15,16]:check(e.ship_visible,"Source arrival shot failed to restore the player")
			var first_actor: Dictionary=next.world_frame.snapshot().actor_events[0]
			if first_actor.destruction.state.phase=="retired":
				check(first_actor.destruction.random_state==e.random_state,"NPC pass did not inherit the camera's consumed stream")
			if not e.immediate_view.is_empty() and e.frame.camera_operations[0].shake_strength>0 and e.shake_strength>0:two_passes=true
			if phase==7 and not e.frame.effect_orientation.is_empty():
				check(e.effect_pose.basis.z==e.immediate_view.pose.basis.z,"Departure model used the later ordinary view")
			if phase==11 and e.frame.effect_orientation.get("view")=="preceding":
				check(e.effect_pose.basis.z==before.camera.view.pose.basis.z,"Arrival model lost preceding camera orientation");arrival=true
			if not e.frame.world_change.is_empty():
				check(after.scene.player_pose.origin==Vector3.ZERO and after.scene.player_pose.basis.z==Vector3.FORWARD,"Relocation did not replace this frame's moved pose")
				check(next.world_frame.snapshot().player_motion.pose.origin!=Vector3.ZERO,"Relocation retroactively moved earlier contacts");relocated=true
			if phase==12 and int(before.camera.shot.phase)==12:
				check(e.effect_pose.basis==before.escape.effect_pose.basis and e.model_rotation!=before.escape.model_rotation,"Drift changed effect orientation or lost visual tumble");drift=true
			if phase==15 and int(before.camera.shot.phase)==14:
				check(e.immediate_view.eye!=e.eye and after.camera.view.eye==e.eye,"Last cut overwrote the earlier immediate pan");cut=true
			if phase in [6,7,10,11,14] and not phases.has(-phase):
				rollback(state);phases[-phase]=true
		state=next
	check(entered and relocated and two_passes and arrival and drift and cut and reached,"Complete escape coverage was not reached")
	check(closest_entry_eye<2000.0 and float(radio_camera_distances.get(12,INF))<12000.0 and float(radio_camera_distances.get(13,INF))<3000.0,"Source yaw never brought the ship into the original radio-12/13 camera path")
	check(state.world_frame.snapshot().controller.death_accounting==kills,"Escape invented later kills or rewards")
	var saved:=snapshots(state)
	check(state.world_frame.evaluate(state.timeline,state.scenery,100,true).is_empty(),"Unimplemented arrival scene advanced")
	check(snapshots(state)==saved,"Arrival boundary mutated retained owners")
	print(library.manifest.profile.edition,": ",launches," controlled full-hull contacts; all 23 radio events; escape movement/camera/effect/fade boundary checked")

func step(state: Dictionary, delta: int, fade_active:=true) -> Dictionary:
	var result: Dictionary=state.world_frame.evaluate(state.timeline,state.scenery,delta,true,1.0,Vector2(0.5,-0.5),true,Vector2i(800,600),fade_active)
	if result.is_empty():check(false,state.world_frame.error)
	return result

func rollback(state: Dictionary) -> void:
	var saved:=snapshots(state)
	check(state.world_frame.evaluate(state.timeline,state.scenery,100,"invalid",1.0).is_empty(),"Late radio failure was accepted")
	check(snapshots(state)==saved,"Late failure committed escape camera, RNG, movement or effect state")

func snapshots(state: Dictionary) -> Dictionary:
	return {"world":state.world_frame.snapshot(),"timeline":state.timeline.snapshot(),"scenery":state.scenery.snapshot()}
func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
