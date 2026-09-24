extends "res://tests/local_arrival_environment.gd"
## Detached destination-world checks. No career or travel completion is granted.
const Worlds=preload("res://src/content/ordinary_world_definitions.gd")
const PostSahi=preload("res://src/content/post_sahi_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const Factory=preload("res://src/simulation/opening_npc_construction.gd")
const Traffic=preload("res://src/content/free_traffic_definitions.gd")
const Life=preload("res://src/content/free_lifecycle_definitions.gd")
const Provocation=preload("res://src/simulation/npc_provocation.gd")
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Scenery=preload("res://src/simulation/scenery_population.gd")
const LocalMap=preload("res://src/simulation/local_map.gd")
const StationView=preload("res://src/content/station_presentation_definitions.gd")
const CONTEXT={"system_id":14,"station_id":70,"campaign_cursor":18,"difficulty":0.5,"rank":0,
	"mission_kind":-1,"mission_completed":true,"mission_story":false,"companions_empty":true,
	"side_missions_empty":true,"station_response":false,"special_arrival":false,"void_encounter":false}

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Ordinary destination worlds: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):check(false,lib.error+bindings.error+cat.error);return
	verify_weymire(bindings,cat)
	if not Worlds.available(bindings):
		check(FreeFlight.flight(bindings,70).is_empty(),"Earlier pack enabled unverified Magnetar flight")
		check(PlanetLayout.new().for_lounge(bindings,cat,70,18).is_empty(),"Earlier pack enabled new planet types")
		check(not Factory.new().configure_free_factory(bindings,cat,0,[81,86],CONTEXT,1),"Earlier pack enabled destination traffic")
		return
	var vectors: Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GOF2_ARRIVAL_PLANET_VECTORS")))
	if not vectors is Array or vectors.size()!=5:check(false,"Supply independent Magnetar planet vectors");return
	verify_planet_locations(bindings,cat,lib,vectors,[70,71,72,73,74],14)
	var cache:=Cache.new();check(cache.configure(bindings),cache.error)
	for station in [95,98,70,71,72,73,74]:
		if not select(cache,bindings,cat,lib,station):return
		if station>=95:continue
		var world:=Worlds.catalogue_location(bindings,cat,station)
		check(not world.is_empty() and world.system_id==14 and world.faction==0 and world.security==3,"Destination catalogue identity changed")
		check(FreeFlight.player_entry(bindings.mido_travel,station,0).system_id==14,"Player entry retained Augmenta")
		check(FreeFlight.flight(bindings,station).system_id==14,"Flight selected the wrong system")
		var dock:=FreeFlight.docking(bindings,station)
		check(dock.system_id==14 and FreeFlight.docking_parameters(dock),"Docking lost the destination system")
		check(not FreeFlight.docking_parameters(dict_with(dock,{"system_id":19})),"A station accepted docking in the wrong system")
		var view:=StationView.select(bindings,station,18)
		check(view.station_id==station and view.hangar_row==0 and StationView.view_parameters(view),"Destination lost its original Terran hangar camera")
		var hangar: Dictionary=bindings.resolve_hangar(station,cat)
		check(not hangar.is_empty() and hangar.row==view.hangar_row,"The original hangar selector disagrees with the destination camera")
		var exterior: RefCounted=load("res://src/content/station_exterior_resources.gd").new()
		if not exterior.configure_ordinary_location(lib,bindings,cat,station):check(false,exterior.error);return
		var shapes: Dictionary=exterior.snapshot()
		check(shapes.station_id==station and shapes.system_id==14 and shapes.faction==0 and shapes.layers.size()==3,"Destination lost its full original exterior")
		for shape in shapes.collision.get("shapes",shapes.collision.boxes):check(exterior.point_volume(shape.center)>=0,"Destination docking missed an authored volume center")
		check(not exterior.configure_ordinary_location(lib,bindings,cat,120) and exterior.snapshot()==shapes,"Unsupported destination replaced prepared exterior resources")
		check(not exterior.configure_ordinary_location(null,bindings,cat,station) and exterior.snapshot()==shapes,"Missing original content replaced prepared exterior resources")
		var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
		var scenery:=Scenery.new();check(scenery.configure(bindings),scenery.error)
		var field:=scenery.for_departure(station,conditions,18)
		check(not field.is_empty() and field.station_id==station and field.count>0,"Destination lacks its generated asteroid field")
		var before:=cache.snapshot();var arrival:=ArrivalEnvironment.new()
		if not arrival.configure(bindings,cat,station,cache):check(false,arrival.error);return
		var state:=arrival.snapshot()
		check(cache.snapshot()==before and state.system_id==14,"Preparing a destination changed retained locations")
		if station==70:check(state.source=="gate" and not state.face_origin,"Dis lost its incoming gate placement")
		else:check(state.source=="cached_planet" and state.cache_station_id==station-1 and state.planet_index==station-70 and is_equal_approx(state.position.length(),80000.0),"Destination ignored FIFO eviction and its member planet")
		var context:=CONTEXT.duplicate(true);context.station_id=station
		for seed in [1,15,20]:
			verify_population(bindings,cat,context,seed)
			context.special_arrival=true;context.player_position=state.position
			verify_population(bindings,cat,context,seed)
			context.special_arrival=false;context.erase("player_position")
		verify_map(bindings,cat,lib,station)
		var original:=cache.location(station)
		check(not original.stock.is_empty() and not original.population.is_empty(),"New station omitted original stock or contacts")
		check(select(cache,bindings,cat,lib,station) and cache.location(station)==original,"Revisiting regenerated cached offers or stock")
		for offer in original.offers.values():check(not Session.acceptance_supported(bindings.early_contracts,18,offer.offer),"World construction enabled unsupported contracts")
	var foreign:=Cache.new();check(foreign.configure(bindings),foreign.error)
	for station in [95,98,71]:
		if not select(foreign,bindings,cat,lib,station):return
	var fallback:=ArrivalEnvironment.new()
	check(fallback.configure(bindings,cat,71,foreign),fallback.error)
	check(fallback.snapshot().source=="fallback_planet" and fallback.snapshot().cache_station_id==98 and fallback.snapshot().position==Vector3(0,0,100000),"Foreign FIFO planet did not use the source fallback")
	# Validate the entire source system, including the other planets and gate.
	for patch in [{"sky_index":11},{"station_ids":[70,71,72,73]}]:
		var original: Dictionary=cat.tables.systems[14].duplicate(true)
		cat.tables.systems[14].merge(patch,true)
		check(Worlds.catalogue_location(bindings,cat,70).is_empty(),"Changed system layout passed the world support guard")
		cat.tables.systems[14]=original
	var type: int=cat.tables.stations[74].planet_type;cat.tables.stations[74].planet_type=0
	check(Worlds.catalogue_location(bindings,cat,70).is_empty(),"An unverified neighboring planet passed the world support guard")
	cat.tables.stations[74].planet_type=type
	for station in [-1,15,120,126,130,132]:
		check(Worlds.location(bindings.mido_travel,station).is_empty() and FreeFlight.flight(bindings,station).is_empty(),"Unsupported ordinary world was enabled")
	for from_station in [70,71,72,73,74]:
		check(Travel.route(bindings.mido_travel,18,from_station,95).is_empty(),"Local travel crossed a jumpgate boundary")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in Worlds.SPANS:
		var invalid: Dictionary=bindings.mido_travel.duplicate(true);invalid.provenance.erase(key)
		check(not Travel.validate(invalid,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing ordinary world proof was accepted: "+key)
	var invalid: Dictionary=bindings.mido_travel.duplicate(true)
	var alternate_source: bool=int(invalid.conversations[0].events[0].text_id)==int(Travel.MAC_VALUES.conversations[0].events[0].text_id)
	var other: Dictionary=Worlds.SPANS if alternate_source else Worlds.MAC_SPANS
	invalid.provenance.ordinary_world_special_planet.offset=int(bindings.arrival_staging.provenance.actor.offset)+int(other.ordinary_world_special_planet[0])
	check(not Travel.validate(invalid,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Mixed-source ordinary world proof was accepted")

func verify_weymire(bindings: RefCounted,cat: RefCounted):
	var stations: Array=cat.tables.stations
	var systems: Array=cat.tables.systems
	var ids:=[45,46,47,48,49]
	var types:=[3,12,17,0,14]
	var models:=[3,6,7,8,1]
	var fields:=[2,1,2,39,29,63,45,7]
	var arrays:=[[10,10,10],ids,[2,11,17,19,26],[0,1,2]]
	var source_arrays:=[]
	for array in systems[9].arrays:source_arrays.append(Array(array))
	check(Array(systems[9].fields)==fields and source_arrays==arrays,"Weymire system row differs from the recovered source")
	for index in ids.size():
		var id: int=ids[index]
		check(Array(stations[id].fields)==[id,9,models[index],types[index]],"Weymire station row differs from the recovered source")
	var no_post: Dictionary=bindings.mido_travel.duplicate(true)
	no_post.erase("post_sahi")
	for id in ids:
		check(Worlds.location(no_post,id).is_empty(),"Weymire was enabled without the Post-Sahi capability")
		var world: Dictionary=Worlds.location(bindings.mido_travel,id)
		var catalogue: Dictionary=Worlds.catalogue_location(bindings,cat,id)
		if PostSahi.available(bindings):
			check(world==catalogue and world.system_id==9 and world.station_id==id and world.planet_type==types[ids.find(id)] and world.faction==2 and world.security==2 and world.gate_station_id==45 and world.sky_index==7,"Weymire location lost its supported source identity")
		else:
			check(world.is_empty() and catalogue.is_empty(),"Earlier pack enabled a Post-Sahi world")
	if not PostSahi.available(bindings):return
	var system: Dictionary=systems[9].duplicate(true)
	var changed: Dictionary=system.duplicate(true)
	var changed_fields: PackedInt32Array=changed.fields
	changed_fields[4]+=1;changed.fields=changed_fields;systems[9]=changed
	check(Worlds.catalogue_location(bindings,cat,48).is_empty(),"A changed Weymire system field passed the source guard")
	systems[9]=system
	changed=system.duplicate(true)
	var changed_arrays: Array=changed.arrays
	var changed_links: PackedInt32Array=changed_arrays[2]
	changed_links.append(25);changed_arrays[2]=changed_links;changed.arrays=changed_arrays;systems[9]=changed
	check(Worlds.catalogue_location(bindings,cat,48).is_empty(),"Changed Weymire links passed the source guard")
	systems[9]=system
	var station: Dictionary=stations[49].duplicate(true)
	changed=station.duplicate(true)
	changed_fields=changed.fields;changed_fields[2]+=1;changed.fields=changed_fields;stations[49]=changed
	check(Worlds.catalogue_location(bindings,cat,48).is_empty(),"A changed neighboring Weymire model passed the source guard")
	stations[49]=station
	verify_weymire_traffic(bindings,cat)

func verify_weymire_traffic(bindings: RefCounted,cat: RefCounted):
	# Detached ordinary component context; the session still owns actual progress.
	var context:=CONTEXT.duplicate(true)
	context.system_id=9;context.station_id=48
	var observed_hostiles:={}
	var observed_reactions:={}
	for seed in [1,2,6]:
		var owner:=Factory.new()
		if not owner.configure_free_factory(bindings,cat,0,[81,86],context,seed):check(false,owner.error);return
		var packet:=owner.generate({"state":12345})
		if packet.is_empty():check(false,owner.error);return
		var population: Dictionary=packet.population
		check(population.system_faction==2 and population.security==2 and population.hostile_faction in [3,8],"Weymire traffic lost the source local/opposing faction")
		var combat: Dictionary=Traffic.population(bindings,packet,context.rank,context.difficulty)
		var lifecycle: Dictionary=Life.population(bindings,packet)
		check(not combat.is_empty(),"Weymire traffic lacks combat support: "+str(population.groups)+" / "+str(packet.actors.map(func(actor):return [actor.population_group,actor.actor_kind])))
		check(not lifecycle.is_empty(),"Weymire traffic lacks lifecycle support")
		if combat.is_empty() or lifecycle.is_empty():return
		check(lifecycle.lifecycle.reactions.primary_faction==2 and lifecycle.lifecycle.reactions.eligible_factions==[2,3],"Weymire reaction factions ignored its admitted system")
		var live:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":context.campaign_cursor,
			"free_context":context,"provocation":{"station_id":48},"actors":[]}
		for row in packet.actors:
			if row.population_group in ["patrol","travel"]:check(row.actor_kind==2,"Weymire local patrol/travel lost faction 2")
			if row.population_group=="hostile":
				observed_hostiles[row.actor_kind]=true
				check(row.actor_kind==population.hostile_faction,"Weymire hostile lost its selected faction")
			var actor:=Actor.new()
			if not actor.configure_ambient(bindings,cat,owner,row.actor_id,context.rank,context.difficulty) or not actor.enable_local_combat():check(false,actor.error);return
			check(actor.refresh_hostility(),actor.error)
			live.actors.append(actor.snapshot())
		check(Life.live_population(bindings,live),"Weymire live combat failed its source faction validation")
		for actor in live.actors:
			if actor.actor_kind in [2,3,8] and actor.active and not observed_reactions.has(actor.actor_kind):
				verify_weymire_reaction(bindings,lifecycle,live.actors,actor,packet.random_state)
				observed_reactions[actor.actor_kind]=true
		var wrong: Dictionary=packet.duplicate(true)
		wrong.actors[0].actor_kind=0
		check(Traffic.population(bindings,wrong,context.rank,context.difficulty).is_empty(),"Foreign patrol passed Weymire packet validation")
		var wrong_live: Dictionary=live.duplicate(true)
		wrong_live.actors[0].actor_kind=0
		check(not Life.live_population(bindings,wrong_live),"Foreign patrol passed Weymire live validation")
	check(observed_hostiles.has(3) and observed_hostiles.has(8),"Weymire fixture missed an authored hostile faction branch: "+str(observed_hostiles))
	check(observed_reactions.has(2) and observed_reactions.has(3) and observed_reactions.has(8),"Weymire fixture missed a native faction reaction branch")

func verify_weymire_reaction(bindings: RefCounted,lifecycle: Dictionary,actors: Array,actor: Dictionary,random_state: Dictionary):
	var reaction:=Provocation.new()
	if not reaction._initialize_population(bindings,lifecycle,bindings.mido_travel.traffic_combat,{"axes":[0,0],"override":-1}):check(false,reaction.error);return
	reaction._set_factions(lifecycle,-1)
	var before: Dictionary=reaction.snapshot()
	var result: Dictionary=reaction.evaluate(actor,int(actor.max_hull),false,random_state,true)
	if result.is_empty():check(false,reaction.error);return
	var after: Dictionary=result.owner.snapshot()
	if actor.actor_kind==8:
		check(after==before and result.events.is_empty(),"Weymire pirate triggered neutral faction provocation")
		return
	check(after.warning_issued and after.response_issued and after.requested_damage[actor.actor_id]==actor.max_hull and result.events.size()==2,"Weymire local or opposing faction did not react to a player hit")
	check(after.station_response_flag==(actor.actor_kind==2),"Weymire station response followed a non-primary faction")
	for id in actors.size():check(after.forced_hostile[id]==(actors[id].actor_kind==actor.actor_kind),"Weymire provocation forced a different faction")

func verify_population(bindings: RefCounted,cat: RefCounted,context: Dictionary,seed: int):
	var owner:=Factory.new()
	if not owner.configure_free_factory(bindings,cat,0,[81,86],context,seed):check(false,owner.error);return
	var packet:=owner.generate({"state":12345})
	if packet.is_empty():check(false,owner.error);return
	check(packet.free_context==context and packet.population.system_id==14 and packet.station_id==context.station_id,"Destination population lost its retained inputs")
	var combat: Dictionary=Traffic.population(bindings,packet,context.rank,context.difficulty)
	var lifecycle: Dictionary=Life.population(bindings,packet)
	check(not combat.is_empty() and not lifecycle.is_empty(),"Destination traffic lacks combat or lifecycle ownership")
	if not lifecycle.is_empty():check(lifecycle.lifecycle.reactions.primary_faction==0 and lifecycle.lifecycle.reactions.eligible_factions==[0,1],"Faction 0 reaction context changed")
	for row in packet.actors:
		var actor:=Actor.new()
		if not actor.configure_ambient(bindings,cat,owner,row.actor_id,context.rank,context.difficulty):check(false,actor.error);return
		check(actor.snapshot().vitals.hull==(460 if row.population_group=="freighter" else 92),"Destination traffic changed the source difficulty/rank hull")
		check(actor.refresh_hostility() and actor.snapshot().hostile==(row.actor_kind==8),"Destination traffic changed the source standing rules")
	var baseline:=Factory.new();var ordinary:=context.duplicate(true);ordinary.system_id=19;ordinary.station_id=98
	check(baseline.configure_free_factory(bindings,cat,0,[81,86],ordinary,seed),baseline.error)
	var expected:=baseline.generate({"state":12345})
	check(not expected.is_empty() and expected.population.groups==packet.population.groups and expected.random_state==packet.random_state,"Equal source faction/security contexts consumed different traffic draws")

func verify_map(bindings: RefCounted,cat: RefCounted,lib: RefCounted,station: int):
	var owner:=LocalMap.new()
	var flight:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":18,
		"location":{"station_id":station,"system_id":14},"local_travel":{"phase":"flight"},
		"mission":{"kind":156,"station_id":56,"reward":0,"bonus":0,"source_parameter":0}}
	if not owner.configure(lib,bindings,cat,flight):check(false,owner.error);return
	check(owner.snapshot().rows.map(func(row):return row.station_id)==[70,71,72,73,74],"Magnetar map used Augmenta's stations")
	for row in owner.snapshot().rows:
		check(row.current==(row.station_id==station) and row.supported==(row.station_id!=station),"Destination map changed local travel permission")
		if row.station_id==station:continue
		check(Travel.route(bindings.mido_travel,18,station,row.station_id).get("system_id")==14,"Destination local route retained the departure system")

func select(cache: RefCounted,bindings: RefCounted,cat: RefCounted,lib: RefCounted,station: int) -> bool:
	var context:={"station_id":station,"campaign_cursor":18,"rank":0,"reputation":{"axes":[0,0],"override":-1}}
	var settings:={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
	var random:=Random.new();random.seed_from(5)
	if not cache.snapshot().get("random",{}).is_empty():check(random.restore(cache.snapshot().random),random.error)
	var success: bool=cache.select_location(bindings,cat,lib,context,settings,random.snapshot(),1700000000)
	check(success,cache.error)
	return success

func dict_with(source: Dictionary,patch: Dictionary) -> Dictionary:
	var result:=source.duplicate(true);result.merge(patch,true);return result
