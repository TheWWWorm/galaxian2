extends "res://tests/dima_construction.gd"
## Selected ordinary-world components only; no travel, career or save is earned.
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const FreeTraffic=preload("res://src/content/free_traffic_definitions.gd")
const Traffic=preload("res://src/simulation/traffic_population.gd")
const Field=preload("res://src/simulation/scenery_field.gd")
const FieldPopulation=preload("res://src/simulation/scenery_population.gd")
const FlightCache=preload("res://src/simulation/flight_player_cache.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Post=preload("res://src/content/post_sahi_definitions.gd")
const DimaReturn=preload("res://src/content/dima_return_definitions.gd")

func test_label() -> String:return "Expedition selected visits"

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not cat.open(library) or not library.select_language("gb"):
		check(false,library.error+bindings.error+cat.error);return
	var old_context:=context(bindings,27,10,6,11)
	if not Campaign.expedition_available(bindings.mido_travel):
		check(not Campaign.empty_story(bindings.mido_travel,old_context),"Earlier binding invented selected Thynome27 world")
		check(not Campaign.supported(bindings.mido_travel,30),"Earlier binding invented Dima30 return")
		check(not Traffic.new().configure_free(bindings,cat,old_context,4096),"Earlier binding constructed selected Thynome traffic")
		return
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	verify_visit(library,bindings,cat,bodies,effects,27,10,6,11)
	verify_visit(library,bindings,cat,bodies,effects,30,91,18,156)

func verify_visit(library: RefCounted,bindings: RefCounted,cat: RefCounted,bodies: RefCounted,effects: RefCounted,cursor: int,station: int,system: int,kind: int) -> void:
	var ctx:=context(bindings,cursor,station,system,kind)
	var mission: Dictionary=Campaign.mission(bindings.mido_travel,cursor)
	check(Campaign.supported(bindings.mido_travel,cursor) and Campaign.empty_story(bindings.mido_travel,ctx) and FreeTraffic.context_valid(bindings,ctx),"Selected visit lacks its guarded shared population admission: "+str(cursor))
	check(mission=={"kind":kind,"station_id":station,"reward":0,"bonus":0,"source_parameter":0} and Post.active_mission(bindings,cursor)==mission,"Selected visit changed its original mission tuple: "+str(cursor))
	check(cat.tables.stations[station].system_id==system and not FreeFlight.player_entry(bindings.mido_travel,station,0,cursor).is_empty(),"Selected visit changed its ordinary location or player entry: "+str(cursor))
	if cursor==27:
		var visit: Dictionary=Campaign.dialogue_presentation(bindings,cursor,mission,true)
		check(visit.get("events")==bindings.mido_travel.post_sahi.missions["27"].result_events and visit.get("mission_kind")==kind and visit.get("campaign_cursor")==27,"Thynome27 lost its original station result presentation")
		check(Campaign.dialogue_presentation(bindings,cursor,mission).is_empty(),"Thynome27 station result opened in flight")
	else:
		var visit: Dictionary=Campaign.dialogue_presentation(bindings,cursor,mission)
		check(bindings.mido_travel.dima_return.result30.briefing_events.is_empty() and visit.get("events")==bindings.mido_travel.dima_return.result30.result_events and visit.get("mission_kind")==kind and visit.get("campaign_cursor")==30,"Dima30 lost zero briefing and its original flight result")
		check(Campaign.dialogue_presentation(bindings,cursor,mission,true).is_empty() and DimaReturn.conversation(bindings,cursor,mission).get("next_cursor")==31,"Dima30 station dialogue or next result selection changed")
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":station,"system_id":system,"ship_id":0,"equipment_ids":[2,86,81,68]}
	var equipment: RefCounted=component_owner(bindings,cat,seed)
	if equipment==null:return
	var held: Dictionary=equipment.snapshot()
	var incoming:={"state":12345}
	var traffic:=Traffic.new()
	if not traffic.configure_free(bindings,cat,ctx,4096):check(false,traffic.error);return
	var sampled: Dictionary=traffic.generate(incoming)
	if sampled.is_empty():check(false,traffic.error);return
	var random:=Random.new();random.restore(incoming)
	var rules: Dictionary=bindings.early_contracts.encounter_construction
	var chosen: int=int(rules.pirate_actor_kind) if random.next_int(int(rules.enemy_faction_draw_bound))<int(rules.pirate_faction_threshold) else int(bindings.mido_travel.free_population.enemy_factions[int(sampled.system_faction)])
	check(sampled.incoming_random_state==incoming and sampled.before_actors_random_state==random.snapshot() and sampled.hostile_faction==chosen,"Selected visit changed the single enemy-faction prelude draw: "+str(cursor))
	check(sampled.mission_kind==kind and sampled.actor_count==0 and not sampled.hostile_selected and sampled.groups.values().all(func(n):return n==0) and not sampled.has("unix_seconds"),"Selected visit reseeded ambient traffic or built actor groups: "+str(cursor))
	var population:=FieldPopulation.new();var field:=Field.new();var field_random:=Random.new();field_random.seed_from(4096)
	if not population.configure(bindings):check(false,population.error);return
	var selected: Dictionary=population.for_departure(station,CONDITIONS,cursor)
	if selected.is_empty() or not field.configure(bindings,cat,station,false,false,cursor):check(false,population.error+field.error);return
	var generated: Dictionary=field.generate(selected.center,field_random.snapshot())
	if generated.is_empty():check(false,field.error);return
	var scenery:=Scenery.new()
	if not scenery.configure_free(bindings,cat,equipment,ctx,CONDITIONS,4096,true,bodies,effects):check(false,scenery.error);return
	var scene: Dictionary=scenery.snapshot();var world: Dictionary=scene.world_initialization;var actors: Dictionary=world.npc_construction
	check(scene.station_id==station and scene.system_id==system and scene.objects==generated.objects and world.input_random_state==generated.random_state,"Selected visit changed source scenery order or location: "+str(cursor))
	check(actors.actors.is_empty() and world.weapon_effects.is_empty() and actors.population.actor_count==0 and actors.population.mission_kind==kind,"Selected visit constructed ordinary actors or effects: "+str(cursor))
	var stream:=Random.new();stream.restore(generated.random_state)
	var prelude: int=int(rules.pirate_actor_kind) if stream.next_int(int(rules.enemy_faction_draw_bound))<int(rules.pirate_faction_threshold) else int(bindings.mido_travel.free_population.enemy_factions[int(actors.population.system_faction)])
	check(actors.population.incoming_random_state==generated.random_state and actors.population.hostile_faction==prelude and actors.population.before_actors_random_state==stream.snapshot() and actors.random_state==stream.snapshot() and scene.random_state==stream.snapshot(),"Selected scenery reseeded or consumed actor draws: "+str(cursor))
	check(not FreeTraffic.population(bindings,actors,int(ctx.rank),ctx.difficulty).is_empty(),"Actor-free selected visit lost shared combat population admission: "+str(cursor))
	var construction: RefCounted=scenery.world_initialization_owner().npc_construction_owner()
	var player:=Player.new()
	if not player.configure_free(bindings,cat,equipment,construction):check(false,player.error);return
	var state: Dictionary=player.snapshot();var cache: Dictionary=player.cache_snapshot()
	check(state.campaign_cursor==cursor and player.loadout().station_id==station and player.loadout().equipment_ids==held.loadout.equipment_ids and equipment.snapshot()==held,"Selected visit changed retained player or equipment: "+str(cursor))
	check(FlightCache.matches(cache,held.loadout,cursor) and cache.base_content_id==bindings.base_content_id and cache.binding_id==bindings.binding_id and cache.station_id==station and cache.system_id==system and cache.equipment_ids==held.loadout.equipment_ids,"Selected visit produced a foreign flight cache: "+str(cursor))
	var restored:=Player.new()
	check(restored.configure_free(bindings,cat,equipment,construction,cache) and restored.snapshot().vitals==state.vitals,"Selected visit could not restore its own player cache: "+str(cursor))
	var foreign: Dictionary=cache.duplicate(true);foreign.binding_id="f".repeat(64)
	check(not Player.new().configure_free(bindings,cat,equipment,construction,foreign),"Selected visit accepted a foreign cache: "+str(cursor))
	var location:=ArrivalLocation.new()
	var resolved: Dictionary=location.resolve_local_travel(bindings,cat,equipment,cache)
	check(not resolved.is_empty() and resolved.campaign_cursor==cursor and resolved.station_id==station and resolved.system_id==system and resolved.equipment_ids==held.loadout.equipment_ids and resolved.base_content_id==bindings.base_content_id and resolved.binding_id==bindings.binding_id,"Selected visit lost ordinary arrival location or identity: "+str(cursor)+" "+location.error)
	check(location.resolve_departure(bindings,cat,cache,equipment)==resolved and equipment.snapshot()==held,"Selected visit changed its resolved location or detached equipment: "+str(cursor))

func context(bindings: RefCounted,cursor: int,station: int,system: int,kind: int) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,
		"station_id":station,"system_id":system,"mission_kind":kind,"mission_story":true,"mission_completed":false,
		"mission_failed":false,"side_missions_empty":true,"companions_empty":true,"station_response":false,
		"void_encounter":false,"special_arrival":false,"rank":8,"difficulty":0.5}
