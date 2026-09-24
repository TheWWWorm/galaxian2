extends "res://tests/dima_construction.gd"
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")

func test_label() -> String:return "Void probe selected construction"

func after_prepared(library: RefCounted,bindings: RefCounted,cat: RefCounted,prepared: RefCounted) -> void:
	if not library.select_language("gb"):check(false,library.error);return
	var previous: Dictionary=prepared.snapshot()
	var equipment: RefCounted=prepared.equipment_owner()
	var source: Dictionary=equipment.snapshot().loadout
	if not equipment.relocate_post_sahi(bindings,29):check(false,equipment.error);return
	var cache:=Cache.capture_post_sahi(bindings.mido_travel,source,equipment.snapshot().loadout,previous.departure.player,29)
	if cache.is_empty():check(false,"Dima component lost actual ship pools at the portal");return
	var progress: Dictionary=previous.departure.progress.duplicate(true)
	progress.merge(Career.calculate_progress(bindings.opening_handoff,29,progress.player_kills,progress.pirate_kills,progress.other_score),true)
	var context: Dictionary=previous.sahi_context.duplicate(true)
	context.merge({"campaign_cursor":29,"station_id":-1,"system_id":-1,"rank":progress.rank},true)
	context.erase("portal_position")
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	var construction:=FlightConstruction.new()
	if not construction.prepare_post_sahi_selected(bindings,cat,equipment,context,progress,{},4096,123,true,bodies,effects,cache):check(false,construction.error);return
	var entry:=construction.snapshot()
	check(entry.location.void_location and entry.location.station_id==-1 and entry.location.system_id==-1 and entry.location.return_station_id==91 and entry.location.return_system_id==18,"Second Void entry lost its actual special location/return")
	check(entry.void_environment.campaign_cursor==29 and entry.void_environment.return_station_id==91 and entry.void_environment.objects.size()==2,"Second Void entry lost the shared original environment")
	check(entry.scenery.world_initialization.npc_construction.actors.size()==int(bindings.mido_travel.post_sahi.void.population.count),"Second Void entry changed source cast size")
	check(entry.departure.player.vitals==previous.departure.player.vitals and entry.departure.player.gamma==previous.departure.player.gamma,"Second Void entry repaired or refilled the player")
	check(entry.departure.cargo==previous.departure.cargo and entry.departure.loadout.equipment_ids==source.equipment_ids,"Second Void entry changed cargo or equipped items")
	check(entry.player_pose.origin==entry.void_environment.player_position and entry.player_yaw_units==32768,"Second Void entry missed its incoming gate pose")
	var frame:=Frame.new()
	if not frame.configure(bindings,cat,library,construction,"E",0.5):check(false,frame.error);return
	var live:=frame.snapshot()
	check(live.campaign_cursor==29 and live.void_environment.return_station_id==91 and live.void_portal.campaign_cursor==29,"Second Void frame lost mission/portal identity")
	check(not frame.void_return_required() and live.progress==progress,"Fresh second Void frame completed or changed progress")
	await after_probe_prepared(library,bindings,cat,construction,frame)

func after_probe_prepared(_library: RefCounted,_bindings: RefCounted,_cat: RefCounted,_construction: RefCounted,_frame: RefCounted) -> void:pass
