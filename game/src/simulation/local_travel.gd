extends RefCounted
const Frames=preload("res://src/simulation/frame_clock.gd")
## Planet acquisition and the ordinary departure timer. The flight frame owns
## guidance, movement and preparation of the destination world.
## No mission, reward, current location or inventory changes during acquisition.
const Definitions=preload("res://src/content/mido_travel_definitions.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Planets=preload("res://src/simulation/opening_planet_layout.gd")
const TargetProjection=preload("res://src/presentation/target_projection.gd")
var error:=""
var _identity:={}
var _rules:={}
var _stations:=[]
var _state:={}
var _max_frame_ms:=0
var _layout:={}
var _perspective:={}
var _positions:={}
var _sample:={}

func configure_flight(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, entry: Dictionary) -> bool:
	error=""
	var next: RefCounted=get_script().new()
	if not next.configure(bindings,catalogues,equipment,int(entry.get("campaign_cursor",-1)),entry.get("departure",{}).get("mission",{})):return reject(next.error)
	for key in next._identity:
		if entry.get(key)!=next._identity[key]:return reject("Local targeting belongs to another prepared flight")
	var planets:=Planets.new()
	var layout:=planets.for_departure(bindings,catalogues,entry.get("departure",{}).get("player_cache"),"high",equipment)
	if layout.is_empty():return reject(planets.error)
	var projection:=TargetProjection.new()
	if not projection.configure(bindings.flight_projection,Vector2i.ONE):return reject(projection.error)
	_identity=next._identity;_rules=next._rules;_stations=next._stations;_max_frame_ms=next._max_frame_ms;_state=next._state
	_layout=layout;_perspective=bindings.flight_projection.duplicate(true);_positions={};_sample={}
	for row in layout.entries:
		if row.kind=="planet":_positions[int(row.station_id)]=row.origin
	return true

func configure(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted, cursor: int, mission: Dictionary) -> bool:
	error=""
	if bindings==null or catalogues==null or not equipment is Equipment or not Definitions.parameters(bindings.mido_travel):return reject("This pack has no supported local journey")
	var content: Dictionary=bindings.mido_travel
	if Definitions.free_local_navigation(content,cursor) and not load("res://src/content/ordinary_generation_definitions.gd").available(bindings):return reject("Ordinary travel requires destination stock and contact generation")
	var rules: Dictionary=content.travel
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false):return reject("Finish the station equipment exchange before local travel")
	var seed: Dictionary=owned.loadout
	if seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Local travel belongs to another content identity")
	var destinations:=Definitions.navigation_stations(content,cursor,int(seed.station_id))
	if destinations.is_empty():return reject("This mission has no supported local destinations")
	if not Definitions.navigation_mission(content,cursor,mission):return reject("Local travel requires the retained source-defined story objective")
	var stations:=[]
	for id in destinations:
		if Definitions.free_local_navigation(content,cursor) and id!=seed.station_id and not load("res://src/content/free_navigation_definitions.gd").destination_supported(bindings,cursor,mission,id):continue
		if not Numbers.integer(id,0,catalogues.tables.stations.size()-1):return reject("Local destination is absent from the catalogue")
		var row: Dictionary=catalogues.tables.stations[int(id)]
		if not Definitions.location_supported(content,int(id),int(row.system_id),int(row.planet_type)):return reject("Local destination uses an unsupported environment")
		stations.append(int(id))
	var duration:=int(rules.default_acquisition_ms)
	for id in seed.equipment_ids:
		var properties: Dictionary=catalogues.tables.items[id].properties
		if properties.get(2)!=int(rules.scanner_subtype):continue
		var value: Variant=properties.get(int(rules.scanner_duration_property))
		if not Numbers.integer(value,1,2147483647):return reject("The installed scanner has no supported acquisition duration")
		duration=int(value);break
	if not Numbers.integer(bindings.frame_clock.get("max_frame_milliseconds"),1,2147483647):return reject("Local travel needs the ordinary flight clock")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_rules=rules.duplicate(true);_stations=stations;_max_frame_ms=Frames.simulation_limit(bindings)
	_state={"campaign_cursor":cursor,"station_id":int(seed.station_id),"system_id":int(seed.system_id),
		"phase":"flight","candidate_station_id":-1,"acquired_station_id":-1,
		"acquisition_ms":0,"acquisition_duration_ms":duration,"launch_ms":0,"destination_station_id":-1,"event_serial":0,"events":[]}
	_layout={};_perspective={};_positions={};_sample={}
	return true

func target_position(station_id: int) -> Variant:
	error=""
	if _layout.is_empty() or _state.phase!="flight" or not _stations.has(station_id) or station_id==_state.station_id or not _positions.has(station_id):
		reject("This planet has no supported local destination flight");return null
	return _positions[station_id]

func rebase_campaign(bindings: RefCounted,cursor: int,mission: Dictionary) -> bool:
	error=""
	var campaign=load("res://src/content/free_campaign_definitions.gd")
	var visit: Dictionary=campaign.dialogue_rules(bindings,_state.get("campaign_cursor"),campaign.mission(bindings.mido_travel,int(_state.get("campaign_cursor",-1))))
	if _state.get("phase")!="flight" or not campaign.visit_at(bindings.mido_travel,_state.get("campaign_cursor"),_state.get("station_id")) or visit.is_empty() or cursor!=int(visit.next_cursor) or not Definitions.navigation_mission(bindings.mido_travel,cursor,mission):return reject("Local navigation lost its acknowledged campaign visit")
	_state.campaign_cursor=cursor
	_stations=Definitions.navigation_stations(bindings.mido_travel,cursor,_state.station_id).filter(func(id):return id==_state.station_id or load("res://src/content/free_navigation_definitions.gd").destination_supported(bindings,cursor,mission,id))
	if not _stations.has(_state.candidate_station_id):_state.candidate_station_id=-1;_state.acquisition_ms=0
	if not _stations.has(_state.acquired_station_id):_state.acquired_station_id=-1
	return true

func supports_destination(station_id: int) -> bool:
	return not _state.is_empty() and station_id!=_state.station_id and _stations.has(station_id)

func sample_frame(camera: Transform3D, aim: Dictionary, milliseconds: int, autopilot_station_id: int, enabled: bool, mining_selected:=false) -> bool:
	error=""
	if _layout.is_empty() or not Numbers.integer(milliseconds,0,_max_frame_ms):return reject("Planet targeting requires a prepared bounded flight frame")
	for key in _identity:
		if aim.get(key)!=_identity[key]:return reject("Planet targeting aim belongs to another content identity")
	var point: Variant=aim.get("point");var viewport: Variant=aim.get("viewport_size")
	if not point is Vector3 or not point.is_finite() or not viewport is Vector2i:return reject("Invalid planet targeting aim")
	var projection:=TargetProjection.new()
	if not projection.configure(_perspective,viewport):return reject(projection.error)
	var width: int=viewport.x/int(_rules.target_window_divisor)
	var lower:=Vector2(TargetProjection.single(point.x-float(width>>1)),TargetProjection.single(point.y-float(width>>1)))
	for value in [lower.x,lower.y,lower.x+width,lower.y+width]:
		if not TargetProjection.safe_pixel(value):return reject("Planet targeting window exceeds source pixels")
	var low:=Vector2i(int(lower.x),int(lower.y));var high:=low+Vector2i(width,width)
	var positions:={};var markers:=[];var candidate:=-1;var unsupported:=-1
	# Background drawing updates every planet before the HUD pass. Guidance in
	# the next player pass will use these retained camera-relative positions.
	for row in _layout.entries:
		if row.kind!="planet":continue
		var id:=int(row.station_id)
		var position:=Planets.view_position(row,camera.origin)
		var projected:=projection.project_point(camera,position)
		if projected.has("error"):return reject(projection.error)
		if not TargetProjection.safe_pixel(projected.screen_position.x) or not TargetProjection.safe_pixel(projected.screen_position.y):return reject("Planet projection exceeds source pixels")
		positions[id]=position
		var pixel:=Vector2i(int(projected.screen_position.x),int(projected.screen_position.y))
		var inside: bool=projected.in_view and pixel.x>low.x and pixel.x<high.x and pixel.y>low.y and pixel.y<high.y
		var supported: bool=_stations.has(id) and id!=_state.station_id
		markers.append({"station_id":id,"position":position,"pixels":pixel,"in_view":projected.in_view,
			"in_scan_window":inside,"current":id==_state.station_id,"supported":supported})
		if inside and id!=_state.station_id and not mining_selected and candidate<0 and unsupported<0:
			if supported:candidate=id
			else:unsupported=id
	# Hidden entry/cinematic draws retain acquisition; launch owns its own clock.
	if enabled and _state.phase=="flight":
		if not sample_acquisition(milliseconds,candidate,autopilot_station_id,candidate>=0):return false
	_positions=positions
	_sample={"visible":enabled and _state.phase=="flight","markers":markers,"viewport_size":viewport,
		"aim_pixels":Vector2i(int(point.x),int(point.y)),"window_low":low,"window_high":high,
		"unsupported_station_id":unsupported if enabled else -1}
	return true

func sample_acquisition(milliseconds: int, station_id: int, autopilot_station_id: int, eligible: bool, paused:=false) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="flight" or not Numbers.integer(milliseconds,0,_max_frame_ms):return reject("Planet acquisition requires an ordinary active flight frame")
	for id in [station_id,autopilot_station_id]:
		if id!=-1 and (not _stations.has(id) or id==_state.station_id):return reject("The selected planet is not a supported travel destination")
	if paused:return true
	var next:=_state.duplicate(true);next.events=[]
	var previous_acquired: int=next.acquired_station_id
	next.acquired_station_id=-1
	if not eligible or station_id<0:
		next.acquisition_ms=0;next.candidate_station_id=-1
	else:
		if next.candidate_station_id!=station_id:next.acquisition_ms=0
		next.candidate_station_id=station_id
		if next.acquisition_ms>2147483647-milliseconds:return reject("Planet acquisition time exceeds the source range")
		next.acquisition_ms+=milliseconds
		if next.acquisition_ms>next.acquisition_duration_ms:
			if previous_acquired!=station_id:
				_sound(next,int(_rules.acquisition_sound_id))
			next.acquired_station_id=station_id
			if autopilot_station_id==station_id:_launch(next)
	_state=next
	return true

func launch_acquired() -> bool:
	error=""
	if _state.is_empty() or _state.phase!="flight" or _state.acquired_station_id<0:return reject("Acquire a planet before starting its departure")
	var next:=_state.duplicate(true);next.events=[]
	_launch(next);_state=next
	return true

func _launch(next: Dictionary) -> void:
	next.phase="launch";next.launch_ms=0
	next.destination_station_id=next.acquired_station_id
	_sound(next,int(_rules.launch_sound_id))

func _sound(next: Dictionary, source_id: int) -> void:
	# An acquired autopilot target emits both sounds in one batch. A manual
	# launch owns a new batch even though no ordinary flight tick has elapsed.
	if next.events.is_empty():next.event_serial+=1
	next.events.append({"kind":"sound","source_id":source_id})

func advance_launch(milliseconds: int, paused:=false) -> bool:
	error=""
	if _state.is_empty() or _state.phase not in ["launch","arrival_required"] or not Numbers.integer(milliseconds,0,_max_frame_ms):return reject("Planet departure requires its bounded launch frame")
	if paused:return true
	# The player clock can continue while death suppresses the world's arrival
	# query. A surviving frame stops at the pending destination boundary.
	if _state.launch_ms>2147483647-milliseconds:return reject("Planet departure time exceeds the source range")
	var next:=_state.duplicate(true);next.events=[]
	next.launch_ms+=milliseconds
	if next.launch_ms>int(_rules.launch_duration_ms):next.phase="arrival_required"
	_state=next
	return true

func prepare_arrival() -> Dictionary:
	error=""
	if _state.is_empty() or _state.phase!="arrival_required":reject("Finish planet departure before preparing the destination");return {}
	var result:=_identity.duplicate()
	result.merge({"campaign_cursor":_state.campaign_cursor,"from_station_id":_state.station_id,
		"station_id":_state.destination_station_id,"system_id":_state.system_id,
		"source_state":int(_rules.source_state),"world_type":int(_rules.world_type),"audio_selector":int(_rules.audio_selector)})
	return result

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_identity.duplicate();result.merge(_state.duplicate(true))
	result.launch_speed_per_ms=float(_rules.launch_speed_per_ms)
	if not _layout.is_empty():result.targeting=_sample.duplicate(true)
	return result

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._identity=_identity.duplicate();result._rules=_rules.duplicate(true);result._stations=_stations.duplicate()
	result._state=_state.duplicate(true);result._max_frame_ms=_max_frame_ms
	result._layout=_layout;result._perspective=_perspective;result._positions=_positions.duplicate();result._sample=_sample.duplicate(true)
	return result

func reject(message: String) -> bool:error=message;return false
