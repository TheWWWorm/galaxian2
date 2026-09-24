extends "res://tests/ordinary_generation.gd"
## Isolated generated-location and source-math checks; no earned travel claim.
const ArrivalEnvironment=preload("res://src/simulation/local_arrival_environment.gd")
const ArrivalRules=preload("res://src/content/local_arrival_environment_definitions.gd")
const PlanetLayout=preload("res://src/simulation/opening_planet_layout.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const SahiHistory=preload("res://tests/fixtures/sahi_location_history.gd")

func _initialize():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Local arrival environment: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var cache:=Cache.new();check(cache.configure(bindings),cache.error)
	var environment:=ArrivalEnvironment.new()
	if not ArrivalRules.available(bindings):
		check(not environment.configure(bindings,cat,95,cache) and environment.snapshot().is_empty(),"Earlier bindings invented incoming placement")
		return
	check(bindings.early_contracts.ordinary_generation.offers.faction_required_system_array==bindings.early_contracts.base_navigation.links_array,"Faction offers confused station IDs with jump links")
	verify_planets(bindings,cat,lib)
	var initial:=Basis(Vector3.UP,0.71)
	for station in [95,96,97,98,99]:
		if not select(cache,bindings,cat,lib,station):return
		var before:=cache.snapshot()
		if not environment.configure(bindings,cat,station,cache):check(false,environment.error);return
		var state:=environment.snapshot();var pose: Transform3D=environment.player_pose(initial)
		check(cache.snapshot()==before,"Deriving arrival mutated location history or stock")
		check(state.location_order==before.locations.map(func(entry):return entry.station_id),"Arrival discarded FIFO insertion order")
		if station==95:
			check(state.source=="gate" and state.position==Vector3(141568.375,0,64843.078125),"Gome C arrival missed generated object2")
			check(pose.basis==initial and not state.face_origin,"Gate arrival replaced the ordinary initial heading")
		else:
			check(state.source=="cached_planet" and state.cache_station_id==before.locations[1].station_id,"Arrival selected a recent visit instead of insertion index1")
			var expected: Vector3=state.planets.entries[state.planet_index].origin*4.0
			check(state.position==expected and is_equal_approx(state.position.length(),80000.0),"Planet-relative arrival changed its four-times distance")
			check(pose.basis.z.dot(-state.position.normalized())>0.99999 and absf(pose.basis.determinant()-1.0)<0.00001,"Arrival did not face the origin with positive local Z forward")
		var detached:=environment.snapshot();detached.planets.entries.clear()
		check(environment.snapshot()==state,"A caller changed prepared arrival geometry")
	var one:=Cache.new();check(one.configure(bindings),one.error)
	if not select(one,bindings,cat,lib,96):return
	check(environment.configure(bindings,cat,96,one),environment.error)
	check(environment.snapshot().source=="gate" and not environment.snapshot().face_origin,"A missing second cached station did not use the incoming gate")
	var foreign:=Cache.new();check(foreign.configure(bindings),foreign.error)
	for station in [79,75,96]:
		if not select(foreign,bindings,cat,lib,station):return
	check(environment.configure(bindings,cat,96,foreign),environment.error)
	check(environment.snapshot().source=="fallback_planet" and environment.snapshot().position==Vector3(0,0,100000),"A nonmember cached station lost the source fallback distance")
	var before:=environment.snapshot()
	check(not environment.configure(bindings,cat,95,foreign) and environment.snapshot()==before,"Arrival accepted a cache selecting a different station")
	check(not environment.configure(bindings,cat,56,foreign) and environment.snapshot()==before,"Unsupported pending story location changed prepared arrival")
	check(environment.player_pose(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO))==null and environment.snapshot()==before,"Invalid initial heading changed prepared arrival")
	if load("res://src/content/post_sahi_definitions.gd").available(bindings):verify_sahi_history(bindings,cat,lib)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in ArrivalRules.SPANS:
		var invalid: Dictionary=bindings.mido_travel.duplicate(true);invalid.provenance.erase(key)
		check(not Travel.validate(invalid,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing arrival proof was accepted: "+key)

func verify_sahi_history(bindings: RefCounted,cat: RefCounted,lib: RefCounted) -> void:
	var fixture:=SahiHistory.new();var history: RefCounted=fixture.create(bindings,cat,lib)
	if history==null:check(false,fixture.error);return
	var before: Dictionary=history.snapshot()
	check(before.locations.map(func(row):return int(row.station_id))==[55,45,48] and before.current_station_id==48,"Selected Sahi cache lost its generated FIFO history")
	var environment:=ArrivalEnvironment.new()
	if not environment.configure(bindings,cat,48,history,26):check(false,environment.error);return
	var arrival: Dictionary=environment.snapshot()
	check(arrival.source=="cached_planet" and arrival.cache_station_id==45 and arrival.planet_index==1 and arrival.location_order==[55,45,48],"Sahi return did not select insertion index1 from retained history")
	check(arrival.position==arrival.planets.entries[1].origin*4.0 and history.snapshot()==before,"Sahi return changed the source planet position or retained locations")
	var revisit:={"station_id":45,"campaign_cursor":24,"rank":0,"reputation":{"axes":[0,0],"override":-1}}
	if not history.select_location(bindings,cat,lib,revisit,SahiHistory.SETTINGS,before.random,1700000045):check(false,history.error);return
	check(history.snapshot().locations==before.locations and history.snapshot().history==before.history and history.snapshot().random==before.random,"A cached revisit reordered visits or regenerated stock and contacts")
	check(not environment.configure(bindings,cat,48,history,26) and environment.snapshot()==arrival,"Sahi arrival accepted a cache currently selecting a different station")
	revisit.station_id=48
	if not history.select_location(bindings,cat,lib,revisit,SahiHistory.SETTINGS,before.random,1700000048):check(false,history.error);return
	check(history.snapshot()==before and environment.configure(bindings,cat,48,history,26) and environment.snapshot()==arrival,"Returning to a cached Sahi destination changed insertion order or its arrival")
	var missing:=Cache.new();check(missing.configure(bindings),missing.error)
	check(not environment.configure(bindings,cat,48,missing,26) and environment.snapshot()==arrival,"Sahi arrival accepted a cache without matching destination history")

func select(cache: RefCounted,bindings: RefCounted,cat: RefCounted,lib: RefCounted,station: int) -> bool:
	var context:={"station_id":station,"campaign_cursor":13 if station<95 else 18,"rank":0,"reputation":{"axes":[0,0],"override":-1}}
	var settings:={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,"energy_availability_percent":0,"missile_availability_percent":0}
	if station>=95:settings.ship_price_percent=0
	var random:=Random.new();random.seed_from(5)
	if not cache.snapshot().get("random",{}).is_empty():check(random.restore(cache.snapshot().random),random.error)
	var success: bool=cache.select_location(bindings,cat,lib,context,settings,random.snapshot(),1700000000)
	check(success,cache.error)
	return success

func verify_planets(bindings: RefCounted,cat: RefCounted,lib: RefCounted):
	var vectors: Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GOF2_ARRIVAL_PLANET_VECTORS")))
	if not vectors is Array or vectors.size()!=5:check(false,"Supply the five independent source-math planet vectors");return
	verify_planet_locations(bindings,cat,lib,vectors,[95,96,97,98,99],19)

func verify_planet_locations(bindings: RefCounted,cat: RefCounted,lib: RefCounted,vectors: Array,station_ids: Array,system_id: int):
	for vector in vectors:
		var planets:=PlanetLayout.new();var state:=planets.for_lounge(bindings,cat,int(vector.station),18)
		if state.is_empty():check(false,planets.error);return
		check(state.entries.map(func(entry):return entry.angular_slot)==vector.slots.map(func(value):return int(value)),"Planet angular draw order differs at%d"%vector.station)
		check(state.entries[state.selected_index].scale==float(vector.size_units)/65536.0 and state.random_state.state==int(vector.random_state),"Planet size replacement or subsequent RNG differs at%d"%vector.station)
		check(state.entries.size()==station_ids.size()+1 and state.system_id==system_id and state.campaign_cursor==18,"Ordinary planet membership or identity was lost")
		var exterior: Dictionary=load("res://src/content/station_exterior_definitions.gd").for_location(bindings,int(vector.station),system_id,int(vector.type))
		check(not exterior.is_empty() and exterior.faction==cat.tables.systems[system_id].fields[exterior.system_faction_field],"Ordinary station exterior lost its system faction")
		for layer in exterior.model_ids.size():
			var path: String=bindings.resolve(int(exterior.model_ids[layer]),"mesh")
			check(lib.manifest.files.has(path),"An original station exterior model is absent")
			var reader: RefCounted=load("res://src/content/aem.gd").new()
			var model: Dictionary=reader.decode(lib.read_resource(path,reader.MAX_BYTES))
			if model.is_empty():check(false,reader.error);return
			check(model.version==4 and not model.surfaces.is_empty(),"An ordinary exterior uses an unsupported source mesh")
			for surface in model.surfaces:check(load("res://src/content/station_exterior_resources.gd").initial_transform_supported(surface,layer==2),"An ordinary exterior needs unsupported transform or light animation")
		var volumes: RefCounted=load("res://src/content/station_collision_volumes.gd").new()
		var collision: Dictionary=volumes.decode(lib.read_resource(exterior.collision_resource,volumes.MAX_BYTES),int(vector.station),int(exterior.collision_record_limit),float(exterior.collision_sphere_scale))
		check(not collision.is_empty() and not collision.get("shapes",collision.get("boxes",[])).is_empty(),"An ordinary station has no supported original docking volumes")
		for row in state.entries:check(lib.manifest.files.has(row.texture_path),"A planet texture is absent from the source content")
		var invalid: Dictionary=bindings.mido_travel.local_arrival_environment.duplicate(true);invalid.planet_sizes.replacement_groups[0].types=[]
		check(planets.arrange(int(vector.station),int(vector.type),station_ids,false,invalid).is_empty(),"Changed size declarations were accepted")
