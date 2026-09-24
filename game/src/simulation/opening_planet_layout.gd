extends RefCounted
## Deterministic constructor layout for the ordinary opening and rescue.
## This owns placement only. Camera size adjustments, sun flare, rendering and
## escape-time scale changes are separate owners and must not be inferred here.
const Sun = preload("res://src/simulation/sun_placement.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Resources = preload("res://src/content/planet_resource_definitions.gd")
const Arrival = preload("res://src/simulation/arrival_location.gd")
const Travel = preload("res://src/content/mido_travel_definitions.gd")
const LocalArrival = preload("res://src/content/local_arrival_environment_definitions.gd")
const Worlds = preload("res://src/content/ordinary_world_definitions.gd")
var error := ""

static func view_position(entry: Dictionary, camera_position: Vector3) -> Vector3:
	return entry.origin+camera_position

func for_opening(bindings: RefCounted, catalogues: RefCounted, base_content_id: String, quality := "high") -> Dictionary:
	error=""
	var data: Dictionary=bindings.opening_sky.get("planet_resources",{})
	if not Resources.parameters(data):return reject("Opening planet resources are unavailable; prepare current declarations")
	var loadout:=Loadout.new()
	if not loadout.configure(bindings,catalogues,base_content_id):return reject(loadout.error)
	var opening:=loadout.snapshot()
	return _for_location(bindings,catalogues,opening,data,base_content_id,quality,false)

func for_arrival(bindings: RefCounted, catalogues: RefCounted, arrival_cache: Variant, quality := "high") -> Dictionary:
	error=""
	var location:=Arrival.new()
	var source:=location.resolve(bindings,catalogues,arrival_cache)
	if source.is_empty():return reject(location.error)
	return _for_location(bindings,catalogues,source,bindings.opening_sky.planet_resources,bindings.base_content_id,quality,true)

func for_departure(bindings: RefCounted, catalogues: RefCounted, cache: Variant, quality := "high", equipment: RefCounted=null) -> Dictionary:
	error=""
	var location:=Arrival.new()
	var source:=location.resolve_departure(bindings,catalogues,cache,equipment)
	if source.is_empty():return reject(location.error)
	return _for_location(bindings,catalogues,source,bindings.opening_sky.planet_resources,bindings.base_content_id,quality,true)

func for_lounge(bindings: RefCounted,catalogues: RefCounted,station_id: int,cursor: int,quality:="high") -> Dictionary:
	error=""
	var location:=Arrival.new()
	var source:=location.resolve_lounge(bindings,catalogues,station_id,cursor)
	if source.is_empty():return reject(location.error)
	return _for_location(bindings,catalogues,source,bindings.opening_sky.planet_resources,bindings.base_content_id,quality,true)

static func supports_station(bindings: RefCounted,catalogues: RefCounted,station_id: int) -> bool:
	var world: Dictionary=Worlds.catalogue_location(bindings,catalogues,station_id)
	if world.is_empty():return false
	var station: Dictionary=catalogues.tables.stations[station_id]
	return LocalArrival.available(bindings) and int(station.planet_type) in LocalArrival.SUPPORTED_TYPES and int(world.sky_index) not in [11,12] and int(world.sky_index)<=14

func for_station(bindings: RefCounted,catalogues: RefCounted,station_id: int,cursor: int,quality:="high") -> Dictionary:
	error=""
	if not supports_station(bindings,catalogues,station_id):return reject("This station has no supported exterior planet layout")
	var station: Dictionary=catalogues.tables.stations[station_id]
	var resources: Dictionary=bindings.opening_sky.planet_resources
	if not Resources.parameters(resources):return reject("Station planet resources are unavailable")
	var context:={"station_id":station_id,"system_id":int(station.system_id),"campaign_cursor":cursor,
		"current_planet_texture_id":int(resources.near_textures[int(station.planet_type)])}
	return _for_location(bindings,catalogues,context,resources,bindings.base_content_id,quality,true,true)

func _for_location(bindings: RefCounted, catalogues: RefCounted, opening: Dictionary, data: Dictionary, base_content_id: String, quality: String, ordinary: bool, station_preview:=false) -> Dictionary:
	var system: Dictionary=catalogues.tables.systems[opening.system_id]
	var station: Dictionary=catalogues.tables.stations[opening.station_id]
	# Other planet types and special system/campaign constructors need their own
	# verified selector. A familiar mesh is not evidence those contexts work.
	var travel_context:=ordinary and Travel.location_supported(bindings.mido_travel,int(opening.station_id),int(opening.system_id),int(station.planet_type))
	var local_arrival:=ordinary and LocalArrival.location_supported(bindings,catalogues,int(opening.station_id),int(opening.get("campaign_cursor",-1)))
	travel_context=travel_context or local_arrival or station_preview
	if (station.planet_type!=0 and not travel_context) or opening.system_id==27 or not Numbers.integer(system.get("sky_index"),0,14):
		return reject("This planet layout requires an ordinary supported location")
	var ordered:=[]
	# The original station loader scans catalogue records, filtering membership.
	# The supplied Mido lists are sorted, but their list order is not the rule.
	for row in catalogues.tables.stations:
		if system.station_ids.has(row.id):
			if not Numbers.integer(row.get("planet_type"),0,int(data.far_textures.size())-1):return reject("Station planet type is outside the resource table")
			ordered.append(int(row.id))
	var layout:=arrange(int(opening.station_id),int(station.planet_type),ordered,not ordinary,bindings.mido_travel.local_arrival_environment if local_arrival or station_preview else {})
	if layout.is_empty():return {}
	var mesh_path: String=bindings.resolve(int(data.mesh_id),"mesh")
	if mesh_path.is_empty():return reject(bindings.error)
	for entry in layout.entries:
		var id: int
		if entry.kind=="sun":id=int(data.sun_textures[int(system.sky_index)])
		elif entry.current:id=int(opening.current_planet_texture_id) if ordinary else int(data.opening_texture_id)
		else:id=int(data.far_textures[int(catalogues.tables.stations[entry.station_id].planet_type)])
		var path: String=bindings.resolve_texture(id,quality)
		if path.is_empty():return reject(bindings.error)
		entry.texture_id=id;entry.texture_path=path
	layout.base_content_id=base_content_id;layout.binding_id=bindings.binding_id
	layout.station_id=opening.station_id;layout.system_id=opening.system_id
	layout.sky_index=int(system.sky_index)
	layout.mesh_id=int(data.mesh_id);layout.mesh_path=mesh_path
	if ordinary:layout.campaign_cursor=int(opening.campaign_cursor)
	return layout

func arrange(station_id: Variant, planet_type: Variant, ordered_station_ids: Variant, opening_scale := true,arrival_rules: Dictionary={}) -> Dictionary:
	error=""
	var sun:=Sun.new()
	var first:=sun.for_station(station_id,planet_type)
	if first.is_empty():return reject(sun.error)
	if not arrival_rules.is_empty() and not LocalArrival.parameters(arrival_rules):return reject("Planet placement requires verified ordinary size declarations")
	if planet_type not in ([0,4,10,11,12,18] if arrival_rules.is_empty() else LocalArrival.SUPPORTED_TYPES) or (opening_scale and planet_type!=0):return reject("Planet placement requires a supported ordinary planet type")
	if not ordered_station_ids is Array or ordered_station_ids.is_empty() or ordered_station_ids.size()>24:
		return reject("Planet placement requires ordered station records")
	var previous: int=-2147483649
	var selected:=-1
	for index in ordered_station_ids.size():
		var id: Variant=ordered_station_ids[index]
		if not id is int or id<=previous or id>2147483647:return reject("Planet station IDs must be unique signed integers in catalogue order")
		previous=id
		if id==station_id:selected=index+1
	if selected<1:return reject("Current station is absent from its planet membership")
	var generator:=Random.new()
	if not generator.restore(first.random_state):return reject(generator.error)
	var entries:=[placement("sun",-1,false,first.angular_slot,first.angles,sun.angle(32768),15000.0/65536.0,generator.snapshot())]
	# The sun's slot stays the reference throughout the loop. The selected planet
	# uses slot zero; it does not replace that reference for later stations.
	var occupied:={int(first.angular_slot):true}
	for id in ordered_station_ids:
		var current: bool=id==station_id
		var slot:=0;var pitch:=0;var size_value:=0.0
		var flip: bool=first.angular_slot>11
		if current:
			# Cursor zero halves the original integer size with truncation before
			# conversion to the source's fixed-point scale.
			var sizes: Dictionary=arrival_rules.get("planet_sizes",{})
			var size_units:=generator.next_int(int(sizes.get("initial_bound",20000)))+int(sizes.get("initial_add",20000))
			if opening_scale:size_units=int(float(size_units)*0.5)
			# Kernstal and Alioth both belong to the original larger-size group.
			# Consume the ordinary draw before its type-specific replacement.
			if not sizes.is_empty():
				for group in sizes.replacement_groups:
					if group.types.any(func(type):return int(type)==planet_type):size_units=generator.next_int(int(group.bound))+int(group.add)
			elif planet_type in [11,12]:size_units=generator.next_int(15000)+35000
			size_value=float(size_units)/65536.0
		else:
			var available:=false
			for candidate in range(7,18):
				if absi(candidate-int(first.angular_slot))>=3 and not occupied.has(candidate):available=true
			if not available:return reject("Station membership exhausts the original angular slots")
			var attempts:=0
			while true:
				slot=generator.next_int(11)+7;attempts+=1
				if absi(slot-int(first.angular_slot))>=3 and not occupied.has(slot):break
				if attempts>=4096:return reject("Planet angular selection exceeded its safety bound")
			size_value=f32((float(generator.next_int(40))*0.01+0.800000011920929)*0.03509521484375)
			flip=not (int(first.angular_slot)>slot and int(first.angular_slot)-slot<12)
			pitch=generator.next_int(4096)-2048
		occupied[slot]=true
		var angles:=Vector3(sun.angle(pitch),sun.angle(slot*2730),0)
		entries.append(placement("planet",id,current,slot,angles,sun.angle(32768) if flip else 0.0,size_value,generator.snapshot()))
	return {"entries":entries,"selected_index":selected,"sun":first,
		"random_state":generator.snapshot(),"sun_flare_scale":Vector3(30000.0,3000.0,15000.0)/65536.0}

func placement(kind: String, station_id: int, current: bool, slot: int, angles: Vector3, yaw_addition: float, scale_value: float, random_state: Dictionary) -> Dictionary:
	var placement_basis:=Basis.from_euler(angles,EULER_ORDER_XYZ)
	var visual_angles:=Vector3(angles.x,f32(angles.y+yaw_addition),angles.z)
	return {"kind":kind,"station_id":station_id,"current":current,"angular_slot":slot,
		"angles":angles,"visual_angles":visual_angles,"basis":Basis.from_euler(visual_angles,EULER_ORDER_XYZ),
		"origin":-placement_basis.z.normalized()*Sun.DISTANCE,"scale":f32(scale_value),"random_state":random_state.duplicate()}

func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

func reject(message: String) -> Dictionary:
	error=message
	return {}
