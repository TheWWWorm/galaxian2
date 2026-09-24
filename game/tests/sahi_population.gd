extends SceneTree
## Source-selected Sahi factory/world composition only. Live cursor24 navigation
## remains guarded until stage, portal contact and cursor25 transition are wired.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Sahi=preload("res://src/content/sahi_encounter_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Categories=preload("res://src/simulation/opening_loadout.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const Story=preload("res://src/content/story_encounter_definitions.gd")
const ArrivalLocation=preload("res://src/simulation/arrival_location.gd")
const FlightConstruction=preload("res://src/simulation/first_flight_construction.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const Career=preload("res://src/simulation/opening_handoff.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const CONDITIONS={"companions_empty":true,"location_match":false,"special_placement":false}
var checks:=0
var failures:=0
var visual_path:=""
var captures:=""

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=Array(OS.get_cmdline_user_args())
	if args.size()%3==1:captures=args.pop_back()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):
		visual_path=args[i+2]
		await verify(args[i],args[i+1])
	print("%s: %d checks; %d failures"%[test_label(),checks,failures])
	quit(1 if failures else 0)

func test_label() -> String:return "Sahi population"

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":24,"system_id":9,"station_id":48,
		"mission_kind":4,"mission_story":true,"mission_completed":false,"mission_failed":false,"rank":8,"difficulty":0.5}
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":48,"system_id":9,"ship_id":0,"equipment_ids":component_equipment()}
	if not Sahi.coherent(bindings.mido_travel):
		check(not Construction.new().configure_sahi(bindings,cat,seed,context),"Earlier content enabled Sahi construction")
		return
	for field in ["campaign_cursor","system_id","station_id","mission_kind","mission_story","mission_completed","mission_failed","binding_id"]:
		var invalid:=context.duplicate(true)
		invalid[field]={"campaign_cursor":23,"system_id":11,"station_id":55,"mission_kind":11,"mission_story":false,"mission_completed":true,"mission_failed":true,"binding_id":"foreign"}[field]
		check(not Construction.new().configure_sahi(bindings,cat,seed,invalid),"Sahi accepted a mismatched context: "+field)
	var invalid_seed:=seed.duplicate(true);invalid_seed.station_id=55
	check(not Construction.new().configure_sahi(bindings,cat,invalid_seed,context),"Sahi accepted retained equipment from another station")
	invalid_seed=seed.duplicate(true);invalid_seed.equipment_ids=[-1]
	check(not Construction.new().configure_sahi(bindings,cat,invalid_seed,context),"Sahi accepted invalid installed equipment")
	for id in [-1,0,1,2,3,4,5]:
		var route:=Route.new();var accepted:=route.configure_sahi_generated(bindings,id,context)
		check(accepted==(id>=0 and id<5),"Sahi route admission changed for actor "+str(id))
	var owner:=Construction.new()
	if not owner.configure_sahi(bindings,cat,seed,context):check(false,owner.error);return
	var before:=owner.snapshot()
	check(owner.generate({"state":-1}).is_empty() and owner.snapshot()==before,"Invalid Sahi RNG partially committed construction")
	var state:=owner.generate({"state":42})
	if state.is_empty():check(false,owner.error);return
	check(state.campaign_cursor==24 and state.station_id==48 and state.sahi_context==context and state.actors.size()==5,"Sahi construction lost selected identity or cast size")
	var authored:=[Vector3(100000,0,0),Vector3(100000,0,-30000)]
	for id in 5:
		var actor: Dictionary=state.actors[id]
		var source: Dictionary=bindings.mido_travel.sahi_encounter.population.actors[id]
		check(actor.actor_id==id and actor.actor_kind==int(source.actor_kind) and actor.subtype==int(source.subtype) and actor.hull_catalogue_id==int(source.hull_catalogue_id),"Sahi changed authored actor order")
		check(actor.body_pose.origin==actor.factory_position and actor.statistics_pose==actor.body_pose and actor.body_pose.basis==Basis.IDENTITY,"Sahi replaced the source factory position")
		var delta: Vector3=actor.factory_position-Vector3(100000,0,0)
		check(delta.x>=-20000 and delta.x<20000 and delta.y>=-20000 and delta.y<20000 and delta.z>=-20000 and delta.z<20000,"Sahi factory spawn left its source bounds")
		var route:=owner.route(id)
		if id<3:
			check(route!=null and route.snapshot()==actor.route,"Sahi lost its retained route owner")
			check(actor.population_group=="fighter" and actor.route.waypoints==authored and actor.route.index==0 and not actor.route.loop,"Void actor lost the authored two-point route")
			check(actor.cargo==actor.get("cargo",[]) and actor.discarded_cargo.is_empty(),"Void cargo handoff changed")
		else:
			check(actor.population_group=="freighter" and actor.model_assembly_required and actor.assembly==bindings.mido_travel.sahi_encounter.population.freighter_assembly,"Sahi freighter lost its source assembly")
			check(not actor.cruise_enabled and actor.hull_divisors==[3] and actor.cargo.is_empty(),"Sahi freighter lost cruise/hull/cargo overrides")
			check(route==null and actor.route.is_empty() and actor.fragments.is_empty(),"Sahi freighter acquired small-ship route or initial debris draws")
	check(owner.generate({"state":42}).is_empty() and owner.snapshot()==state,"Committed Sahi population generated twice")
	var world:=World.new()
	if not world.configure_sahi(bindings,cat,seed,context,CONDITIONS):check(false,world.error);return
	var composed:=world.generate({"state":42})
	if composed.is_empty():check(false,world.error);return
	check(composed.npc_construction==state and composed.weapon_effects.size()==5,"Sahi world changed the accepted factory ledger")
	var ordinary:=ContractWorld.impact_model(bindings,0)
	for id in 5:
		var effect: Dictionary=composed.weapon_effects[id]
		if id<3:
			check(effect.primary.item_id==5 and effect.primary.resource_id==14602 and effect.discarded_default.item_id==0 and effect.discarded_default.resource_id==ordinary,"Sahi Void weapon effects changed")
		else:check(effect=={"actor_id":id,"unarmed":true},"Sahi freighter allocated a weapon effect pool")
	var detached:=owner.snapshot();detached.actors[0].route.waypoints.clear()
	check(owner.snapshot()==state,"Sahi snapshot consumer changed retained construction")
	# Scenery composition accepts a detached valid equipment component already at
	# the selected source world. This does not authorize travel to station 48.
	var equipment: RefCounted=component_owner(bindings,cat,seed)
	if equipment==null:return
	var scene_seed: Dictionary=equipment.snapshot().loadout
	var held: Dictionary=equipment.snapshot();var scenery:=Scenery.new()
	if not scenery.configure_sahi(bindings,cat,equipment,context,CONDITIONS,123):check(false,scenery.error);return
	var field:=scenery.snapshot();var assembled: Dictionary=field.world_initialization
	check(field.departure_population.campaign_cursor==24 and field.departure_population.station_id==48,"Sahi scenery selected another source field")
	check(assembled.campaign_cursor==24 and assembled.station_id==48 and assembled.npc_construction.actors.size()==5,"Sahi scenery lost its selected world construction")
	check(equipment.snapshot()==held,"Sahi scenery changed retained equipment")
	var player:=Player.new();var npc: RefCounted=scenery.world_initialization_owner().npc_construction_owner()
	if not player.configure_sahi(bindings,cat,equipment,npc):check(false,player.error);return
	var player_state: Dictionary=player.snapshot();var player_cache: Dictionary=player.cache_snapshot()
	check(player_state.sahi_context==context and player_state.campaign_cursor==24,"Sahi player lost its selected encounter identity")
	check(player_cache.campaign_cursor==24 and player_cache.station_id==48 and player_cache.system_id==9 and player_cache.ship_id==scene_seed.ship_id,"Sahi player cache fell back to an ordinary world")
	check(equipment.snapshot()==held,"Sahi player composition changed retained equipment")
	var flight: Dictionary=Story.flight(bindings,context)
	check(not flight.is_empty() and flight.campaign_cursor==24 and flight.station_id==48 and flight.system_id==9 and flight.mission_kind==4,"Sahi story flight lost the source-selected identity")
	var location:=ArrivalLocation.new();var place: Dictionary=location.resolve_local_travel(bindings,cat,equipment,player_cache)
	check(not place.is_empty() and place.campaign_cursor==24 and place.station_id==48 and place.system_id==9,"Sahi player cache did not resolve its equipped story location")
	var progress: Dictionary=Career.calculate_progress(bindings.opening_handoff,24,0,0,0)
	if progress.is_empty():check(false,"Cannot build deterministic Sahi career progress");return
	progress.reputation=Reputation.initial(bindings);progress.debris_destroyed=0;progress.capital_ship_kills=0
	var selected:=context.duplicate(true);selected.rank=progress.rank
	var prepared:=FlightConstruction.new()
	if not prepared.prepare_sahi_selected(bindings,cat,equipment,selected,progress,{},4096,123,true,null,null,null,null,10):check(false,prepared.error);return
	var entry: Dictionary=prepared.snapshot()
	check(entry.sahi_context==selected and entry.campaign_cursor==24 and entry.station_id==48 and entry.system_id==9,"Selected Sahi construction lost encounter identity")
	check(entry.location.station_id==48 and entry.location.system_id==9 and entry.departure.sahi_context==selected,"Selected Sahi construction fell back to ordinary FreeFlight context")
	check(entry.environment_object.resource_id==int(bindings.first_flight.environment_object_resource_id) and entry.scenery.world_initialization.npc_construction.sahi_context==selected,"Selected Sahi construction lost story scenery or portal environment")
	check(prepared.equipment_owner().snapshot()==held,"Selected Sahi construction changed retained equipment")
	var encounter:=Encounter.new()
	if not encounter.configure_story(bindings,cat,library,prepared.player_owner(),prepared.scenery_owner(),prepared.equipment_owner(),progress.reputation):check(false,encounter.error);return
	check(encounter.snapshot().campaign_cursor==24 and encounter.snapshot().combat.actors.size()==5,"Selected Sahi construction did not compose its authored combat encounter")
	verify_post_sahi_cargo(bindings,cat,equipment)
	await after_prepared(library,bindings,cat,prepared)
	after_population(library,bindings,cat,equipment,scenery,player)

## Isolated inventory components, not granted campaign cargo. Exercise both
## branches independently of whichever wreck item the live pilot recovers.
func verify_post_sahi_cargo(bindings: RefCounted,cat: RefCounted,equipment: RefCounted) -> void:
	var absent: RefCounted=equipment.fork();var untouched: Dictionary=absent.snapshot()
	if not load("res://src/content/post_sahi_definitions.gd").available(bindings):
		check(not absent.protect_sahi_cargo(bindings) and absent.snapshot()==untouched,"A pre-Void content pack enabled the Sahi cargo transition")
		return
	check(not untouched.cargo.entries.any(func(row):return row.item_id==131),"The absent-crystal component already contains the tested item")
	check(absent.protect_sahi_cargo(bindings) and absent.snapshot()==untouched and absent.cargo_cache_valid(),"Sahi protection created missing cargo or changed its cache")
	var owner: RefCounted=equipment.fork();var hold: Dictionary=owner.snapshot().cargo
	var first: int=hold.entries.size()
	hold.entries.append_array([{"item_id":131,"quantity":1},{"item_id":132,"quantity":1},{"item_id":131,"quantity":2}])
	hold.used+=4;hold.free_space=hold.capacity-hold.used
	if not owner.retain_flight_cargo(hold):check(false,owner.error);return
	var expected: Dictionary=owner.snapshot();expected.cargo.entries[first].mission=true
	check(owner.protect_sahi_cargo(bindings) and owner.snapshot()==expected and owner.cargo_cache_valid(),"Sahi protection changed more than the first existing crystal flag, including cargo prices or quantities")
	check(not owner.snapshot().cargo.entries[first+1].has("mission") and not owner.snapshot().cargo.entries[first+2].has("mission"),"Sahi protection marked another cargo row")
	check(owner.protect_sahi_cargo(bindings) and owner.snapshot()==expected,"Repeating Sahi protection duplicated or changed retained cargo")
	var live=load("res://src/simulation/flight_cargo.gd").new()
	check(live.configure_equipment(bindings,cat,owner) and live.snapshot()==expected.cargo,"Flight cargo rejected the separately protected story item: "+live.error)
	check(equipment.snapshot()==untouched,"Detached protection tests changed the selected flight inventory")

func after_prepared(_library: RefCounted,_bindings: RefCounted,_cat: RefCounted,_prepared: RefCounted) -> void:pass

func after_population(_library: RefCounted,_bindings: RefCounted,_cat: RefCounted,_equipment: RefCounted,_scenery: RefCounted,_player: RefCounted) -> void:pass

func component_equipment() -> Array:return [22,86,81,55]

func component_owner(bindings: RefCounted,cat: RefCounted,seed: Dictionary) -> RefCounted:
	var equipment:=Equipment.new();var scene_seed:=equipped_seed(bindings,cat,seed)
	if scene_seed.is_empty():check(false,"Cannot build a valid equipped component loadout");return null
	var capacity:=int(cat.tables.ships[int(scene_seed.ship_id)].stats.cargo_capacity)
	equipment._rules=bindings.station_equipment.duplicate(true);equipment._items={};equipment._completion_prices=[]
	for id in scene_seed.equipment_ids:equipment._items[id]=equipment._item_metadata(cat,int(id),equipment._rules)
	equipment._completion_prices=Equipment.prototype_prices(bindings,cat)
	equipment._recovery_cargo_ids=bindings.mido_travel.tractor_recovery.transfer.special_item_ids.map(func(id):return int(id))
	equipment._state={"loadout":scene_seed,"cargo":{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"ship_id":int(scene_seed.ship_id),"capacity":capacity,"entries":[],"used":0,"free_space":capacity},"cargo_cache_stale":false,"prototype_drill_replaced":true}
	if not equipment.complete_training(equipment.snapshot().cargo):check(false,equipment.error);return null
	return equipment

func equipped_seed(bindings: RefCounted,cat: RefCounted,source: Dictionary) -> Dictionary:
	var result:=source.duplicate(true);var counts:=[];var offsets:=[];var used:=[];var total:=0
	for property in Categories.SLOT_PROPERTIES:
		offsets.append(total);var count:=int(cat.tables.ships[int(result.ship_id)].stats[property]);counts.append(count);used.append(0);total+=count
	var slots:=[];slots.resize(total)
	for id in result.equipment_ids:
		if id<0 or id>=cat.tables.items.size():return {}
		var category:=int(cat.tables.items[id].arrays[2][int(bindings.weapon_parameters.item_category_value_index)])
		if category<0 or category>=counts.size() or used[category]>=counts[category]:return {}
		var slot: int=int(used[category]);used[category]+=1
		slots[offsets[category]+slot]={"item_id":id,"category":category,"slot":slot,"quantity":1}
	var ids:=[]
	for slot in slots:
		if slot!=null:ids.append(slot.item_id)
	result.slots=slots;result.equipment_ids=ids
	return result

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
