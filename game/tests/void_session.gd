extends "res://tests/sahi_session.gd"
## Focused source-selected component. This does not earn a saved campaign or
## synthesize Sahi portal contact; sahi_session covers the real transition.
func test_label() -> String:return "Void session component"

func after_prepared(library: RefCounted,bindings: RefCounted,cat: RefCounted,prepared: RefCounted) -> void:
	if not Frame.OrdinaryFlight.Authored.Post.available(bindings):return
	var bodies:=Bodies.new();var effects:=Effects.new();var visuals:=Visuals.new()
	if not library.select_language("gb") or not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not visuals.open(visual_path,library.manifest):check(false,library.error+bodies.error+effects.error+visuals.error);return
	arrival_library=library;arrival_bindings=bindings;arrival_catalogues=cat;arrival_visuals=visuals;arrival_bodies=bodies;arrival_effects=effects
	var component: Dictionary=selected_sahi_with_locations(library,bindings,cat,prepared,bodies,effects)
	if component.is_empty():return
	var sahi: RefCounted=component.construction;var locations: RefCounted=component.locations
	var seed: Dictionary=sahi.snapshot()
	var equipment: RefCounted=sahi.equipment_owner();var original: Dictionary=equipment.snapshot().loadout
	if not equipment.protect_sahi_cargo(bindings) or not equipment.relocate_post_sahi(bindings,25):check(false,equipment.error);return
	var cache: Dictionary=load("res://src/simulation/flight_player_cache.gd").capture_post_sahi(bindings.mido_travel,original,equipment.snapshot().loadout,sahi.player_owner().snapshot(),25)
	var progress: Dictionary=seed.departure.progress.duplicate(true)
	progress.merge(Career.calculate_progress(bindings.opening_handoff,25,progress.player_kills,progress.pirate_kills,progress.other_score),true)
	var context: Dictionary=seed.sahi_context.duplicate(true)
	context.merge({"campaign_cursor":25,"station_id":-1,"system_id":-1,"mission_kind":156,"rank":progress.rank},true)
	var construction:=FlightConstruction.new()
	if not construction.prepare_post_sahi_selected(bindings,cat,equipment,context,progress,{},4096,123,true,bodies,effects,cache,null,locations):check(false,construction.error);return
	root.size=Vector2i(1280,720)
	var current:=Camera3D.new();root.add_child(current);current.make_current()
	var live:=Session.new();root.add_child(live)
	if not live._configure_construction(library,bindings,visuals,cat,construction,1000000,123,false):check(false,live.error);live.free();current.free();return
	check(root.get_camera_3d()==current,"Preparing a Void component stole the accepted camera")
	await verify_live_void(live,bindings,1000000)
	live.free();current.free()
