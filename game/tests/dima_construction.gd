extends "res://tests/sahi_population.gd"
## Selected component state only; the earned route has its separate producer.
const Thynome=preload("res://src/content/thynome_expedition_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Planets=preload("res://src/simulation/opening_planet_layout.gd")

func test_label() -> String:return "Dima selected construction"

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":28,"system_id":18,"station_id":91,
		"mission_kind":4,"mission_story":true,"mission_completed":false,"mission_failed":false,"rank":8,"difficulty":0.5}
	if not Thynome.available(bindings):
		check(Story.flight(bindings,context).is_empty(),"Earlier binding enabled Dima selected construction")
		return
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":91,"system_id":18,"ship_id":0,"equipment_ids":[2,86,81,68]}
	var equipment: RefCounted=component_owner(bindings,cat,seed)
	if equipment==null:return
	var held: Dictionary=equipment.snapshot()
	var progress: Dictionary=Career.calculate_progress(bindings.opening_handoff,28,0,0,0)
	progress.reputation=Reputation.initial(bindings);progress.debris_destroyed=0;progress.capital_ship_kills=0
	context.rank=progress.rank
	var prepared:=FlightConstruction.new()
	if not prepared.prepare_dima_selected(bindings,cat,equipment,context,progress,{},4096,123):check(false,prepared.error);return
	var state:=prepared.snapshot()
	check(state.campaign_cursor==28 and state.station_id==91 and state.system_id==18 and state.location.station_id==91,"Dima construction lost its source location")
	check(state.departure.progress==progress and state.departure.mission==Thynome.mission_values(bindings.mido_travel.thynome_expedition.mission28),"Dima construction changed component progress or mission")
	check(state.departure.player_cache.campaign_cursor==28 and state.departure.player_cache.station_id==91 and state.departure.player_cache.system_id==18,"Dima player cache fell back to another entry")
	check(equipment.snapshot()==held and prepared.equipment_owner().snapshot()==held,"Dima construction mutated supplied equipment")
	var random:=Random.new();random.seed_from(4096)
	var expected:=Vector3(-40000+random.next_int(80000),-20000+random.next_int(40000),40000+random.next_int(40000))+Vector3(100000,-50000,-40000)
	check(state.environment_object.position==expected and state.before_yaw_random_state==random.snapshot(),"Dima portal placement changed source draws or translation")
	check(state.sahi_context.portal_position==expected and not context.has("portal_position"),"Dima cast anchor is missing or mutates its caller")
	var population: Dictionary=state.scenery.world_initialization.npc_construction
	check(population.sahi_context==state.sahi_context and population.actors.size()==8,"Dima cast and environment use different selected state")
	for actor in population.actors:
		var delta: Vector3=actor.factory_position-expected
		check(delta.x>=-20000 and delta.x<20000 and delta.y>=-20000 and delta.y<20000 and delta.z>=-20000 and delta.z<20000,"Dima actor missed its relocated portal anchor")
	var planets:=Planets.new()
	check(not planets.for_departure(bindings,cat,state.departure.player_cache,"high",equipment).is_empty(),"Dima selected planet layout failed: "+planets.error)
	var wrong:=context.duplicate(true);wrong.station_id=90
	check(not FlightConstruction.new().prepare_dima_selected(bindings,cat,equipment,wrong,progress,{},4096,123),"Dima selected constructor accepted another station")
	await after_prepared(library,bindings,cat,prepared)
