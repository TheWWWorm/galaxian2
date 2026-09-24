extends RefCounted
## A catalogue-backed local map. Its private layout RNG never advances flight,
## and confirming a selection only requests the existing planet guidance owner.
const Definitions=preload("res://src/content/mido_travel_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
var error:=""
var _state:={}

func configure(library: RefCounted, bindings: RefCounted, catalogues: RefCounted, flight: Dictionary, display_system_id: int=-1) -> bool:
	error=""
	if library==null or bindings==null or catalogues==null or not Definitions.parameters(bindings.mido_travel):return reject("This content has no supported local map")
	var base: String=bindings.base_content_id
	if library.manifest.get("content_id")!=base or catalogues.content_id!=base or flight.get("base_content_id")!=base or flight.get("binding_id")!=bindings.binding_id:return reject("Local map belongs to another flight or content identity")
	var rules: Dictionary=bindings.mido_travel.map
	var location: Dictionary=flight.get("location",{})
	var travel: Dictionary=flight.get("local_travel",{})
	var docked: bool=flight.get("station_map",false)
	var cursor:=int(flight.get("campaign_cursor",-1))
	var stations:=Definitions.navigation_stations(bindings.mido_travel,cursor,int(location.get("station_id",-1)))
	if Definitions.free_local_navigation(bindings.mido_travel,cursor):stations=stations.filter(func(id):return id==location.get("station_id") or load("res://src/content/free_navigation_definitions.gd").destination_supported(bindings,cursor,flight.get("mission",{}),id))
	if stations.is_empty() or location.get("system_id")!=Definitions.navigation_system(bindings.mido_travel,cursor,int(location.get("station_id",-1))) or (not docked and travel.get("phase")!="flight"):return reject("The local map is unavailable at this campaign boundary")
	if (Definitions.navigation_available(bindings.mido_travel,cursor) or Definitions.free_local_navigation(bindings.mido_travel,cursor)) and not Definitions.navigation_mission(bindings.mido_travel,cursor,flight.get("mission",{})):return reject("The local map lost the pending story objective")
	# The same original system display serves both local courses and a gate's
	# destination choice. Displaying another system never changes flight state.
	var systems: Array=[int(location.system_id)]
	var destinations: Array=flight.get("gate_destinations",[])
	for destination in destinations:
		if not destination is int:return reject("Gate map destinations must be imported station identifiers")
		var request:={"base_content_id":base,"binding_id":bindings.binding_id,"from_station_id":int(location.station_id),"destination_station_id":destination}
		var arrival:=GateArrival.packet(bindings,catalogues,request,cursor)
		if arrival.is_empty():return reject("Gate map destination has no supported arrival")
		if not systems.has(arrival.system_id):systems.append(arrival.system_id)
	var gate_map: bool=flight.get("gate_transit",{}).get("phase")=="map"
	if gate_map:systems.erase(int(location.system_id))
	if systems.is_empty():return reject("This gate has no supported destination map")
	if display_system_id<0:display_system_id=int(systems[0])
	if not systems.has(display_system_id):return reject("This flight cannot select a destination in that system")
	var gate_selection: bool=display_system_id!=int(location.system_id)
	if gate_selection:stations=destinations.duplicate()
	var choices:=[]
	for id in systems:choices.append({"system_id":id,"name":catalogues.tables.systems[id].name})
	var system: Dictionary=catalogues.tables.systems[display_system_id]
	var labels:={}
	for key in rules.labels:
		var id:=int(rules.labels[key])
		if id<0 or id>=library.strings.size() or library.strings[id].is_empty():return reject("Local map text is absent from this language")
		labels[key]=library.strings[id]
	var ordered:=[]
	for station in catalogues.tables.stations:
		if system.station_ids.has(station.id):ordered.append(station)
	if ordered.is_empty() or ordered.size()>24:return reject("Unsupported local map catalogue extent")
	var random:=Random.new()
	if not random.seed_from(display_system_id*int(rules.seed_multiplier)):return reject(random.error)
	var used:={};var rows:=[];var radius:=0
	for station in ordered:
		var type:=int(station.planet_type)
		if type<0 or type>=rules.planet_sizes.size():return reject("Local map planet type is unsupported")
		var sector:=random.next_int(ordered.size()+1)
		while used.has(sector):sector=random.next_int(ordered.size()+1)
		used[sector]=true
		var angle_units: int=sector*(int(rules.angle_units)/(ordered.size()+1))
		radius=(int(rules.first_radius) if rows.is_empty() else radius+int(rules.radius_step))+random.next_int(int(rules.radius_draw_bound))
		var angle:=float(angle_units)/float(rules.angle_units)*TAU
		var resource_id:=int(rules.model_base)+type
		var path: String=bindings.resolve(resource_id,"mesh")
		if path.is_empty():return reject(bindings.error)
		var material: Dictionary=bindings.material_for_mesh(path,"high")
		if material.is_empty() or material.get("id")!=int(rules.material_id) or material.get("render_type")!=int(rules.render_type) or int(material.texture_ids[0])!=int(rules.texture_id):return reject("Local map planet material is unsupported")
		rows.append({"station_id":int(station.id),"name":station.name,"planet_type":type,
			"current":int(station.id)==int(location.station_id),
			"supported":stations.has(int(station.id)) and int(station.id)!=int(location.station_id),
			"mission_target":int(station.id)==int(flight.get("mission",{}).get("station_id",-1)) or int(station.id)==int(flight.get("contracts",{}).get("mission",{}).get("station_id",-1)),
			"model_id":resource_id,"model_path":path,"radius":radius,"angle_units":angle_units,
			"position":Vector3(-sin(angle)*radius,0,cos(angle)*radius),
			"scale":float(rules.planet_sizes[type])*float(rules.size_multiplier)})
	var layout_random:=random.snapshot()
	var art: Dictionary=rules.visuals
	for row in rows:row.orbit_angle=float(random.next_int(int(art.orbit_angle_bound)))/float(art.orbit_angle_divisor)
	var ui: Dictionary=rules.ui
	var faction:=int(system.fields[2]);var security:=int(system.fields[1])
	if faction<0 or faction>=ui.faction_image_ids.size() or security<0 or security*3+2>=ui.security_colors.size():return reject("Unsupported system map classification")
	labels.faction=library.strings[int(ui.faction_text_base)+faction]
	labels.security=library.strings[int(ui.security_text_base)+security]
	labels.legend=[]
	for entry in ui.legend:labels.legend.append({"image_id":int(entry.image_id),"text":library.strings[int(entry.text_id)]})
	_state={"base_content_id":base,"binding_id":bindings.binding_id,"language":library.active_language,
		"campaign_cursor":int(flight.campaign_cursor),"station_id":int(location.station_id),
		"system_id":display_system_id,"system_name":system.name,"labels":labels,"rows":rows,
		"route_mode":"gate" if gate_selection else "local","system_choices":choices,
		"selected_station_id":-1,"confirmation_visible":false,"diagnostic":"",
		"ambient":float(rules.ambient),"diffuse":float(rules.diffuse),"layout_random":layout_random,
		"orbit_random":random.snapshot(),"visuals":art.duplicate(true),"ui":ui.duplicate(true),
		"sun_texture_id":int(art.sun_texture_ids[int(system.sky_index)]),"faction_image_id":int(ui.faction_image_ids[faction]),
		"security_color":Color(float(ui.security_colors[security*3])/255.0,float(ui.security_colors[security*3+1])/255.0,float(ui.security_colors[security*3+2])/255.0)}
	return true

func select_station(station_id: int) -> bool:
	error=""
	if _state.is_empty() or _state.confirmation_visible:return reject("Local map selection is inactive")
	var index:=_index(station_id)
	if index<0:return reject("Station is absent from the displayed system")
	_state.selected_station_id=station_id;_state.diagnostic=""
	return true

func move_selection(direction: int) -> bool:
	if _state.is_empty() or direction not in [-1,1]:return reject("Invalid local map selection")
	var index:=_index(int(_state.selected_station_id))
	var next:=posmod(index+direction,_state.rows.size()) if index>=0 else 0
	return select_station(int(_state.rows[next].station_id))

func request_confirmation() -> bool:
	error=""
	if _state.is_empty() or _state.confirmation_visible:return reject("Local map confirmation is inactive")
	var index:=_index(int(_state.selected_station_id))
	if index<0:return reject("Select a planet before setting its course")
	var row: Dictionary=_state.rows[index]
	if row.current:_state.diagnostic=_state.labels.current;return true
	if not row.supported:_state.diagnostic="Travel to %s is not implemented yet."%row.name;return true
	_state.confirmation_visible=true;_state.diagnostic=""
	return true

func cancel_confirmation() -> bool:
	if _state.is_empty() or not _state.confirmation_visible:return reject("There is no pending local course")
	_state.confirmation_visible=false
	return true

func destination() -> int:
	return int(_state.selected_station_id) if not _state.is_empty() and _state.confirmation_visible else -1

func snapshot() -> Dictionary:return _state.duplicate(true)
func clear() -> void:_state={};error=""
func _index(id: int) -> int:
	for index in _state.get("rows",[]).size():
		if _state.rows[index].station_id==id:return index
	return -1
func reject(message: String) -> bool:error=message;return false
