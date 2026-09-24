extends "res://tests/ordinary_worlds.gd"
## Detached Behén and Pescal Inartu components; no earned route or Dima scene.
const Expedition=preload("res://src/content/thynome_expedition_definitions.gd")
const Exteriors=preload("res://src/content/station_exterior_resources.gd")
const GateClock=preload("res://src/simulation/gate_animation.gd")

const SOURCE_WORLDS=[
	{"system_id":2,"station_ids":[30,31,32,33],"models":[6,4,6,4],"planet_types":[1,8,13,9],
		"fields":[1,1,2,24,40,73,30,9],"arrays":[[8,11,21],[30,31,32,33],[0,8,9,17],[0,1,2]],
		"faction":2,"security":1,"sky_index":9,"gate_station_id":30,"hangar_row":2},
	{"system_id":18,"station_ids":[90,91,92,93,94],"models":[7,4,2,2,5],"planet_types":[1,4,14,17,5],
		"fields":[1,1,0,43,85,81,90,1],"arrays":[[14,10,20],[90,91,92,93,94],[1,8],[0,1,2]],
		"faction":0,"security":1,"sky_index":1,"gate_station_id":90,"hangar_row":0},
]

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Expedition ordinary worlds: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	for spec in SOURCE_WORLDS:verify_source_rows(bindings,cat,spec)
	var persistent: Dictionary=bindings.early_contracts.ordinary_generation.persistent
	var records: Array=Contacts.decode_persistent_contacts(lib.read_resource(persistent.resource,1024*1024),persistent)
	check(records.filter(func(row):return int(row.fields[1])==30).is_empty(),"Behén gained an unverified authored contact")
	var behen: Array=records.filter(func(row):return int(row.fields[1])==32)
	check(behen.size()==1 and behen[0].fields==[1,32,2,2,1,-1,15,-1,36998] and behen[0].portrait==[2,4,4,0,0],"Behén's original authored blueprint contact changed")
	var pescal: Array=records.filter(func(row):return int(row.fields[1])==90)
	check(pescal.size()==1 and pescal[0].fields==[9,90,18,0,1,-1,67,-1,39999] and pescal[0].portrait==[0,4,8,2,2],"Pescal's original authored blueprint contact changed")
	var absent: Dictionary=bindings.mido_travel.duplicate(true);absent.erase("thynome_expedition")
	var altered: Dictionary=bindings.mido_travel.duplicate(true)
	if altered.has("thynome_expedition"):altered.thynome_expedition.world28.portal.resource_id=-1
	for spec in SOURCE_WORLDS:
		for station in spec.station_ids:
			check(Worlds.location(absent,station).is_empty(),"Expedition world appeared without its source capability")
			check(Worlds.location(altered,station).is_empty(),"Expedition world accepted incoherent declarations")
	if not Expedition.available(bindings):
		for spec in SOURCE_WORLDS:
			for station in spec.station_ids:
				check(Worlds.catalogue_location(bindings,cat,station).is_empty() and FreeFlight.flight(bindings,station,27).is_empty(),"Earlier pack admitted a new ordinary world")
		return
	var cache:=Cache.new();check(cache.configure(bindings),cache.error)
	if failures:return
	for spec in SOURCE_WORLDS:
		for station in spec.station_ids:
			verify_components(bindings,cat,lib,cache,spec,int(station))
	verify_traffic(bindings,cat,SOURCE_WORLDS[0],30)
	verify_traffic(bindings,cat,SOURCE_WORLDS[1],90)
	for spec in SOURCE_WORLDS:verify_catalogue_guard(bindings,cat,spec)

func verify_source_rows(bindings: RefCounted,cat: RefCounted,spec: Dictionary):
	var source: Dictionary=cat.tables.systems[int(spec.system_id)]
	var arrays:=[]
	for row in source.arrays:arrays.append(Array(row))
	check(Array(source.fields)==spec.fields and arrays==spec.arrays and Array(source.station_ids)==spec.station_ids and int(source.sky_index)==int(spec.sky_index),"Expedition system differs from the recovered source: "+str(spec.system_id))
	for index in spec.station_ids.size():
		var id: int=int(spec.station_ids[index])
		check(Array(cat.tables.stations[id].fields)==[id,int(spec.system_id),int(spec.models[index]),int(spec.planet_types[index])],"Expedition station differs from the recovered source: "+str(id))
	var expected: Dictionary=Worlds.SYSTEMS[int(spec.system_id)]
	check(expected.station_ids==spec.station_ids and expected.system_fields==spec.fields and expected.system_arrays==spec.arrays and expected.faction==spec.faction and expected.security==spec.security and expected.sky_index==spec.sky_index and expected.gate_station_id==spec.gate_station_id,"Native expedition declaration differs from its source rows")
	check(int(source.fields[int(bindings.mido_travel.free_population.faction_field)])==int(spec.faction) and int(source.fields[int(bindings.mido_travel.free_population.security_field)])==int(spec.security),"Expedition faction/security field ownership changed")

func verify_components(bindings: RefCounted,cat: RefCounted,lib: RefCounted,cache: RefCounted,spec: Dictionary,station: int):
	var world: Dictionary=Worlds.catalogue_location(bindings,cat,station)
	check(not world.is_empty() and world==Worlds.location(bindings.mido_travel,station) and world.system_id==spec.system_id and world.planet_type==spec.planet_types[spec.station_ids.find(station)],"Expedition location rejected a source station: "+str(station))
	if world.is_empty():return
	var entry: Dictionary=FreeFlight.player_entry(bindings.mido_travel,station,0,27)
	var flight: Dictionary=FreeFlight.flight(bindings,station,27)
	var dock: Dictionary=FreeFlight.docking(bindings,station,27)
	check(not entry.is_empty() and entry.system_id==spec.system_id and flight.system_id==spec.system_id and dock.system_id==spec.system_id and FreeFlight.docking_parameters(dock),"Expedition player/flight/dock composition failed: "+str(station))
	var view: Dictionary=StationView.select(bindings,station,27)
	var hangar: Dictionary=bindings.resolve_hangar(station,cat)
	check(not view.is_empty() and StationView.view_parameters(view) and view.hangar_row==spec.hangar_row and hangar.row==spec.hangar_row and hangar.station_id==station,"Expedition source hangar/camera selection failed: "+str(station))
	var planet_owner:=PlanetLayout.new();var layout: Dictionary=planet_owner.for_lounge(bindings,cat,station,27)
	check(not layout.is_empty() and layout.system_id==spec.system_id and layout.sky_index==spec.sky_index and layout.entries.size()==spec.station_ids.size()+1 and layout.entries[layout.selected_index].station_id==station,"Expedition planet/sky selection failed: "+str(station)+" "+planet_owner.error)
	if not layout.is_empty():
		for planet in layout.entries:check(lib.manifest.files.has(planet.texture_path),"Expedition source planet texture is absent: "+str(station))
	var exterior:=Exteriors.new()
	check(exterior.configure_ordinary_location(lib,bindings,cat,station),exterior.error)
	if not exterior.snapshot().is_empty():
		var shape: Dictionary=exterior.snapshot()
		check(shape.station_id==station and shape.system_id==spec.system_id and shape.faction==spec.faction and shape.layers.size()==3 and not shape.collision.get("shapes",shape.collision.get("boxes",[])).is_empty(),"Expedition exterior or docking volumes failed: "+str(station))
	if station==int(spec.gate_station_id):
		var gate:=GateClock.new()
		check(gate.configure(bindings,cat,lib,station),gate.error)
		if not gate.snapshot().is_empty():
			var gate_state: Dictionary=gate.snapshot()
			check(gate_state.layout.gate_station_id==station and not gate_state.layout.objects.is_empty(),"Expedition gate has no original layout: "+str(station))
	if not select_expedition(cache,bindings,cat,lib,station):return
	var before: Dictionary=cache.snapshot()
	var arrival:=ArrivalEnvironment.new()
	var arrival_supported: bool=ArrivalRules.location_supported(bindings,cat,station,27)
	check(arrival.configure(bindings,cat,station,cache,27),arrival.error+" supported="+str(arrival_supported)+" selected="+str(before.get("current_station_id")))
	if not arrival.snapshot().is_empty():
		var state: Dictionary=arrival.snapshot()
		check(cache.snapshot()==before and state.system_id==spec.system_id and state.station_id==station and state.planets.system_id==spec.system_id and state.gates.gate_station_id==spec.gate_station_id,"Expedition arrival changed cache or selected the wrong world: "+str(station))
		check(state.source==("gate" if station==int(spec.gate_station_id) else ("cached_planet" if state.cache_station_id in spec.station_ids else "fallback_planet")) and state.position.is_finite(),"Expedition source arrival placement failed: "+str(station))
	var retained: Dictionary=cache.location(station)
	check(not retained.is_empty() and not retained.stock.is_empty() and not retained.population.is_empty(),"Expedition location omitted source stock or contacts: "+str(station))

func select_expedition(cache: RefCounted,bindings: RefCounted,cat: RefCounted,lib: RefCounted,station: int) -> bool:
	var context:={"station_id":station,"campaign_cursor":27,"rank":0,"reputation":{"axes":[0,0],"override":-1}}
	var settings:={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
	var random:=Random.new();random.seed_from(5)
	var current: Dictionary=cache.snapshot()
	if not current.get("random",{}).is_empty():check(random.restore(current.random),random.error)
	var selected: bool=cache.select_location(bindings,cat,lib,context,settings,random.snapshot(),1700000000)
	check(selected,str(station)+": "+cache.error)
	return selected

func verify_traffic(bindings: RefCounted,cat: RefCounted,spec: Dictionary,station: int):
	var context:=CONTEXT.duplicate(true)
	context.system_id=int(spec.system_id);context.station_id=station;context.campaign_cursor=27
	for seed in [1,2,6]:
		var factory:=Factory.new()
		if not factory.configure_free_factory(bindings,cat,0,[81,86],context,seed):check(false,factory.error);return
		var packet: Dictionary=factory.generate({"state":12345})
		if packet.is_empty():check(false,factory.error);return
		var population: Dictionary=packet.population
		var local_faction: int=int(spec.faction)
		var enemy: int=int(bindings.mido_travel.free_population.enemy_factions[local_faction])
		check(population.system_faction==local_faction and population.security==spec.security and population.hostile_faction in [enemy,int(bindings.mido_travel.free_population.pirate_faction)],"Expedition traffic lost source faction/security: "+str(station))
		var combat: Dictionary=Traffic.population(bindings,packet,context.rank,context.difficulty)
		var lifecycle: Dictionary=Life.population(bindings,packet)
		check(not combat.is_empty() and not lifecycle.is_empty(),"Expedition traffic lacks combat/lifecycle ownership: "+str(station))
		if lifecycle.is_empty():return
		check(lifecycle.lifecycle.reactions.primary_faction==local_faction and lifecycle.lifecycle.reactions.eligible_factions==[local_faction,enemy],"Expedition reaction context ignored its source faction: "+str(station))
		var live:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":27,"free_context":context,"provocation":{"station_id":station},"actors":[]}
		for row in packet.actors:
			if row.population_group in ["patrol","travel"]:check(row.actor_kind==local_faction,"Expedition local traffic changed faction: "+str(station))
			if row.population_group=="hostile":check(row.actor_kind==population.hostile_faction,"Expedition hostile traffic changed faction: "+str(station))
			var actor:=Actor.new()
			if not actor.configure_ambient(bindings,cat,factory,row.actor_id,context.rank,context.difficulty) or not actor.enable_local_combat():check(false,actor.error);return
			check(actor.refresh_hostility(),actor.error)
			live.actors.append(actor.snapshot())
		check(Life.live_population(bindings,live),"Expedition live faction traffic failed source validation: "+str(station))

func verify_catalogue_guard(bindings: RefCounted,cat: RefCounted,spec: Dictionary):
	var station: int=int(spec.station_ids[0])
	var original: Dictionary=cat.tables.systems[int(spec.system_id)].duplicate(true)
	var changed: Dictionary=original.duplicate(true)
	var fields: PackedInt32Array=changed.fields;fields[4]+=1;changed.fields=fields
	cat.tables.systems[int(spec.system_id)]=changed
	check(Worlds.catalogue_location(bindings,cat,station).is_empty(),"Changed expedition system row passed the source guard")
	cat.tables.systems[int(spec.system_id)]=original
	var neighbor: int=int(spec.station_ids[-1])
	var prior: Dictionary=cat.tables.stations[neighbor].duplicate(true)
	changed=prior.duplicate(true)
	fields=changed.fields;fields[2]+=1;changed.fields=fields
	cat.tables.stations[neighbor]=changed
	check(Worlds.catalogue_location(bindings,cat,station).is_empty(),"Changed expedition neighboring station passed the source guard")
	cat.tables.stations[neighbor]=prior
