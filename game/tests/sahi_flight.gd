extends "res://tests/sahi_population.gd"
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const StoryPilot=preload("res://tests/fixtures/story_flight_pilot.gd")
const SahiHistory=preload("res://tests/fixtures/sahi_location_history.gd")

func test_label() -> String:return "Sahi flight integration"
func component_equipment() -> Array:return [2,86,81,68]

func after_prepared(library: RefCounted,bindings: RefCounted,cat: RefCounted,prepared: RefCounted) -> void:
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not library.select_language("gb") or not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,library.error+bodies.error+effects.error);return
	var component: Dictionary=selected_sahi_with_locations(library,bindings,cat,prepared,bodies,effects)
	if component.is_empty():return
	var seed: Dictionary=prepared.snapshot()
	var owned: RefCounted=prepared.equipment_owner()
	var flight_source: RefCounted=component.construction
	var visuals:=Visuals.new()
	if not visuals.open(visual_path,library.manifest):check(false,visuals.error);return
	root.size=Vector2i(1280,720)
	var flight:=build_flight(library,bindings,cat,visuals,flight_source)
	if flight.is_empty():return
	var frame: RefCounted=flight.frame;var scene: Node3D=flight.scene
	var initial: Dictionary=frame.snapshot()
	check(initial.sahi_stage.phase==0 and initial.actors.size()==5 and not initial.sahi_portal.visible,"Sahi flight lost its initial stage or cast")
	check(initial.progress==seed.departure.progress and initial.equipment==owned.snapshot(),"Sahi frame changed retained progress or equipment")
	await capture_frame(scene,frame,"sahi-arrival")
	var shown:=false
	for step in 150:
		var next: RefCounted=advance_flight(frame,100,Vector2.ZERO,0.0)
		if next==null:check(false,frame.error);finish_flight(scene);return
		frame=next
		if frame.dialogue_visible():shown=true;break
	check(shown and frame.snapshot().dialogue.count==4,"Sahi did not show its four modal briefing lines")
	if not shown:return
	var modal: Dictionary=frame.snapshot()
	await capture_frame(scene,frame,"sahi-briefing")
	var frozen: Dictionary=frame.evaluate(100,Vector2.ONE,1.0,false,Vector2i.ZERO,Vector2.ZERO,true).snapshot()
	# The source still visits NPCs with zero time during a modal: their bank
	# sample ring changes, while roots, damage, projectiles and world time hold.
	for key in ["player","player_pose","camera_view","world_phase_elapsed_ms","radio","cargo","random_state","scenery"]:
		check(frozen[key]==modal[key],"Sahi modal briefing advanced "+key)
	for id in modal.encounter.combat.actors.size():
		var previous: Dictionary=modal.encounter.combat.actors[id]
		var current: Dictionary=frozen.encounter.combat.actors[id]
		check(current.body_pose.origin==previous.body_pose.origin and current.body_pose.basis.is_equal_approx(previous.body_pose.basis) and current.vitals==previous.vitals and current.systems==previous.systems,"Sahi modal briefing moved or damaged an NPC")
	check(frozen.encounter.weapons==modal.encounter.weapons,"Sahi modal briefing advanced projectiles")
	for line in 4:
		var next: RefCounted=navigate_flight(frame,"next")
		if next==null:check(false,frame.error);return
		frame=next
	check(not frame.dialogue_visible() and frame.snapshot().acknowledged,"Sahi briefing did not return control")
	for step in 260:
		var next: RefCounted=advance_flight(frame,100,Vector2.ZERO,0.0)
		if next==null:check(false,frame.error);finish_flight(scene);return
		frame=next
	var state: Dictionary=frame.snapshot()
	check(state.radio.started.slice(0,3)==[true,true,true] and not state.radio.started[3],"Sahi recovery radio started from elapsed time alone")
	check(state.sahi_stage.phase==0 and not frame.cinematic_input_blocked() and not frame.sahi_arrival_required(),"Sahi advanced its view or portal without actual collected cargo")
	check(state.campaign_cursor==24 and state.cargo_used==0 and state.progress.campaign_cursor==24,"Sahi flight granted completion or cargo")
	await capture_frame(scene,frame,"sahi-battle")
	print("Sahi live flight: ",state.world_phase_elapsed_ms,"ms; radio ",state.radio.started,"; player hull ",state.player.vitals.hull)
	frame=await recover_void_cargo(frame,scene)
	if frame!=null:
		var held: Dictionary=frame.snapshot()
		check(held.encounter.combat.recovery.accepted_quantity>=3 and held.cargo_used>=3,"Sahi did not collect its generated Void cargo")
		check(held.progress.get("cargo_recovered",0)==int(initial.progress.get("cargo_recovered",0))+held.encounter.combat.recovery.accepted_quantity,"Sahi's actual pickups did not enter retained career progress")
		var observer: RefCounted=frame._objective.fork_for_frame()
		var observed: Dictionary=observer.snapshot()
		check(observer.observe_combat(frame._encounter) and observer.snapshot()==observed,"Polling story recovery twice duplicated cargo progress")
		observer._initial_progress.cargo_recovered=2147483647
		check(not observer.observe_combat(frame._encounter) and observer.snapshot()==observed,"Overflowing story recovery partially changed its career")
		print("Sahi cargo recovery: ",held.encounter.combat.recovery,"; hull ",held.player.vitals.hull)
		await enter_sahi_portal(frame,scene)
	finish_flight(scene)

func selected_sahi_with_locations(library: RefCounted,bindings: RefCounted,cat: RefCounted,prepared: RefCounted,bodies: RefCounted,effects: RefCounted) -> Dictionary:
	var fixture:=SahiHistory.new();var locations: RefCounted=fixture.create(bindings,cat,library)
	if locations==null:check(false,fixture.error);return {}
	var seed: Dictionary=prepared.snapshot()
	var selected:=FlightConstruction.new()
	if not selected.prepare_sahi_selected(bindings,cat,prepared.equipment_owner(),seed.sahi_context,seed.departure.progress,{},4096,123,true,bodies,effects,null,null,10,locations):
		check(false,selected.error);return {}
	check(selected.selected_locations_owner().snapshot()==locations.snapshot(),"Selected Sahi world did not retain its generated location history")
	return {"construction":selected,"locations":locations}

func build_flight(library: RefCounted,bindings: RefCounted,cat: RefCounted,visuals: RefCounted,construction: RefCounted) -> Dictionary:
	var frame:=Frame.new()
	if not frame.configure(bindings,cat,library,construction,"E",0.5):check(false,frame.error);return {}
	var scene:=Scene.new();root.add_child(scene)
	if not scene.build(library,bindings,visuals,cat,frame):check(false,scene.error);scene.free();return {}
	return {"frame":frame,"scene":scene}

func advance_flight(frame: RefCounted,milliseconds: int,commands: Vector2,throttle: float,fire:=false) -> RefCounted:
	return frame.evaluate(milliseconds,commands,throttle,false,Vector2i.ZERO,Vector2.ZERO,fire)

func navigate_flight(frame: RefCounted,action: String) -> RefCounted:return frame.navigate(action)
func finish_flight(scene: Node3D) -> void:scene.free()
func portal_arrived(_frame: RefCounted) -> void:pass

func enter_sahi_portal(frame: RefCounted,scene: Node3D) -> void:
	var arrived: RefCounted=await StoryPilot.enter_sahi_portal(frame,scene,Callable(self,"advance_flight"),Callable(self,"capture_frame"),Callable(self,"check"),process_frame)
	if arrived!=null:await portal_arrived(arrived)

func recover_void_cargo(frame: RefCounted,scene: Node3D,collect:=true) -> RefCounted:
	return await StoryPilot.recover_void_cargo(frame,scene,Callable(self,"advance_flight"),Callable(self,"capture_frame"),Callable(self,"check"),process_frame,collect)

func capture_frame(scene: Node3D,frame: RefCounted,label: String) -> void:
	if not scene.present(frame):check(false,scene.error);return
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(captures)
	await process_frame
	RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(label+".png"))==OK,"Cannot capture "+label)
