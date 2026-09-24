extends RefCounted
const FlightStages=preload("res://src/content/flight_stages.gd")
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Recovered first-station view constants; scoped separately from progression.
const Values=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Alioth=preload("res://src/content/alioth_arrival_definitions.gd")
const Worlds=preload("res://src/content/ordinary_world_definitions.gd")
## Source camera tables select by hangar row. Row2 belongs to the recovered
## Sahi system9 hangar; both supported Mac executables contain these values.
const ROW_TWO={"position":[-2247,1010,-1845],
	"angles":[-0.18000000715255737,-2.049999952316284,-0.029999999329447746],
	"ambient":[0.15000000596046448,0.15000000596046448,0.3499999940395355]}
const VALUES := {"scope":"first_station_presentation","station_id":78,"hangar_row":3,"camera":{"position":[1800,800,-1778],"angles":[-0.20000000298023224,2.569999933242798,-0.029999999329447746],"rotation_order":"YXZ","projection":[0.800000011920929,200.0,100000.0],"initial_jitter_bound":150,"phase_start":4.71238899230957,"phase_limit":7.853981852531433,"phase_rate":9.58738019107841e-05,"endpoint_tolerance":5.0,"endpoint_min":[18,30,50],"endpoint_range":[131,120,100],"max_frame_ms":150},"light":{"initial_camera_yaw":0.39269909262657166,"direction_bias":[-0.20000000298023224,-0.30000001192092896,0],"material_ambient":0.699999988079071,"diffuse":[1,1,1],"ambient":[0.44999998807907104,0.25,0.25],"specular":[0.5,0.5,0.5],"specular_power":96.0},"portraits":{"0":{"status":"fixed","family":0,"parts":[0,0,0,0]},"2":{"status":"fixed","family":2,"parts":[1,1,1,1]},"16":{"status":"fixed","family":11,"parts":[1,0,0,2]}},"dialogue":{"next_text_id":179,"final_text_id":180,"start_delay_ms":1000,"silent_text_id":1696,"voice_event_ids":[267,268,277,278,279,280,281,282,283,284,269,270,271,272,273,274,275,276],"stop_previous_voice":true,"atmosphere_event_id":122}}
const SPANS := {"scene_kind":[414874,39],"projection":[-700407,39],"initial_camera":[-700353,193],"light_direction":[422340,141],"station_lights":[425834,467],"environment_row":[422497,222],"camera_seed":[422719,800],"camera_jitter":[423519,273],"frame_clock":[442938,75],"camera_update":[444038,942],"rotation_dispatch":[1243229,38],"rotation_yxz":[1243901,307],"tween_sample":[1324538,180],"tween_reset":[1324826,74],"tween_clock":[1324906,166],"next_label_and_voice_stop":[-692441,90],"final_label_and_voice_start":[-686960,143],"voice_lookup":[-215216,68],"voice_not_found":[-212901,14],"atmosphere_start":[425005,38],"dialogue_delay":[444980,14],"portrait_selection":[-692155,24],"portrait_composition":[-86396,159],"mission_no_actor":[399358,16],"mission_actor_getter":[401310,10],"position_table":[1585242,120],"pitch_table":[1585370,40],"yaw_table":[1585418,40],"alternate_yaw_table":[1585466,40],"roll":[1585034,4],"projection_values":[1545978,12],"initial_yaw":[1545998,4],"direction_x_bias":[1582946,4],"direction_y_bias":[1582914,4],"light_material_ambient":[1556918,4],"light_diffuse":[1544610,4],"light_ambient_rg":[1585054,8],"light_ambient_gb":[1556906,4],"light_specular":[1544586,4],"light_power":[1585062,4],"tween_phase":[1596354,16],"tween_tau":[1587986,8],"tween_half":[1582354,8],"endpoint_tolerance":[1557114,4],"rotation_slots":[1245194,24],"light_slots":[426302,32],"voice_lookup_table":[1560154,12032],"portrait_pointer_0":[2396762,8],"portrait_pointer_2":[2396778,8],"portrait_pointer_16":[2396890,8],"portrait_gunant":[2411386,20],"portrait_instruction":[2411834,20],"zero_fill_section":[-750798,80]}

const MAC_ALTERNATE := {"scene_kind":[415292,39],"projection":[-706303,39],"initial_camera":[-706249,193],"light_direction":[422758,141],"station_lights":[426262,467],"environment_row":[422915,222],"camera_seed":[423137,800],"camera_jitter":[423937,273],"frame_clock":[443450,75],"camera_update":[444550,942],"rotation_dispatch":[1236085,37],"rotation_yxz":[1236756,307],"tween_sample":[1315234,157],"tween_reset":[1315490,74],"tween_clock":[1315570,166],"next_label_and_voice_stop":[-698337,90],"final_label_and_voice_start":[-692849,143],"voice_lookup":[-216172,68],"voice_not_found":[-213857,14],"atmosphere_start":[425432,38],"dialogue_delay":[445492,14],"portrait_selection":[-698051,24],"portrait_composition":[-86396,159],"mission_no_actor":[399874,16],"mission_actor_getter":[401826,10],"position_table":[1560306,120],"pitch_table":[1560434,40],"yaw_table":[1560482,40],"alternate_yaw_table":[1560530,40],"roll":[1560098,4],"projection_values":[1520962,12],"initial_yaw":[1520982,4],"direction_x_bias":[1558010,4],"direction_y_bias":[1557978,4],"light_material_ambient":[1531918,4],"light_diffuse":[1519594,4],"light_ambient_rg":[1560118,8],"light_ambient_gb":[1531906,4],"light_specular":[1519570,4],"light_power":[1560126,4],"tween_phase":[1571434,16],"tween_tau":[1563050,8],"tween_half":[1557418,8],"endpoint_tolerance":[1532114,4],"rotation_slots":[1238050,24],"light_slots":[426730,32],"voice_lookup_table":[1535218,12032],"portrait_pointer_0":[2374194,8],"portrait_pointer_2":[2374210,8],"portrait_pointer_16":[2374322,8],"portrait_gunant":[2388818,20],"portrait_instruction":[2389266,20],"zero_fill_section":[-756982,80]}
const MAC_VALUES := {"scope":"first_station_presentation","station_id":78,"hangar_row":3,"camera":{"position":[1800,800,-1778],"angles":[-0.20000000298023224,2.569999933242798,-0.029999999329447746],"rotation_order":"YXZ","projection":[0.800000011920929,200.0,100000.0],"initial_jitter_bound":150,"phase_start":4.71238899230957,"phase_limit":7.853981852531433,"phase_rate":9.58738019107841e-05,"endpoint_tolerance":5.0,"endpoint_min":[18,30,50],"endpoint_range":[131,120,100],"max_frame_ms":150},"light":{"initial_camera_yaw":0.39269909262657166,"direction_bias":[-0.20000000298023224,-0.30000001192092896,0],"material_ambient":0.699999988079071,"diffuse":[1,1,1],"ambient":[0.44999998807907104,0.25,0.25],"specular":[0.5,0.5,0.5],"specular_power":96.0},"portraits":{"0":{"status":"fixed","family":0,"parts":[0,0,0,0]},"2":{"status":"fixed","family":2,"parts":[1,1,1,1]},"16":{"status":"fixed","family":11,"parts":[1,0,0,2]}},"dialogue":{"next_text_id":179,"final_text_id":180,"start_delay_ms":1000,"silent_text_id":1707,"voice_event_ids":[267,268,277,278,279,280,281,282,283,284,269,270,271,272,273,274,275,276],"stop_previous_voice":true,"atmosphere_event_id":122}}

static func parameters(data: Variant) -> bool:
	return _parameters(data,VALUES) or _parameters(data,MAC_VALUES)

static func _parameters(data: Variant,expected: Dictionary) -> bool:
	if not data is Dictionary or data.size()!=expected.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in expected:
		if not Values.equal_value(data.get(key),expected[key]):return false
	return true

static func select(bindings: RefCounted, station_id: int, cursor: int) -> Dictionary:
	if bindings==null or not parameters(bindings.station_presentation):return {}
	if station_id==98:
		if not Alioth.available(bindings):return {}
		if cursor not in [15,16] and not (cursor in ([17]+FlightStages.FREE) and load("res://src/content/alioth_return_definitions.gd").available(bindings)):return {}
		return alioth_view(bindings.station_presentation)
	var world: Dictionary=Worlds.location(bindings.mido_travel,station_id)
	if load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,cursor) and not world.is_empty():
		if not load("res://src/content/local_arrival_environment_definitions.gd").available(bindings):return {}
		# System9 carries its source system fields. The catalogue resolver still
		# checks the selected row against the imported station at scene entry.
		var row:=source_hangar_row(world,int(bindings.hangars.get("system_field",-1)))
		return ordinary_view(bindings.station_presentation,station_id,row)
	return bindings.station_presentation.duplicate(true)

static func alioth_view(shared: Dictionary) -> Dictionary:
	var data:=shared.duplicate(true)
	var view: Dictionary=Alioth.VALUES.presentation
	data.scope="alioth_station_presentation";data.station_id=98;data.hangar_row=int(view.hangar_row)
	data.camera.position=view.camera_position.duplicate();data.camera.angles=view.camera_angles.duplicate()
	data.light.ambient=view.ambient.duplicate()
	data.portraits.merge(view.portraits.duplicate(true),true)
	return data

static func source_hangar_row(world: Dictionary,field: int) -> int:
	if not world.has("system_fields"):return 0
	if field<0 or field>=world.system_fields.size():return -1
	return int(world.system_fields[field])

static func ordinary_view(shared: Dictionary,station_id: int,row: int=0) -> Dictionary:
	if row not in [0,2]:return {}
	var data:=alioth_view(shared)
	if row==2:
		data.hangar_row=2
		data.camera.position=ROW_TWO.position.duplicate()
		data.camera.angles=ROW_TWO.angles.duplicate()
		data.light.ambient=ROW_TWO.ambient.duplicate()
	data.scope="augmenta_station_presentation" if station_id in [95,96,97,99] else "ordinary_station_presentation";data.station_id=station_id
	return data

static func view_parameters(data: Dictionary) -> bool:
	if parameters(data):return true
	if not data.get("provenance") is Dictionary:return false
	for expected in [VALUES,MAC_VALUES]:
		var shared: Dictionary=expected.duplicate(true);shared.provenance=data.provenance
		# Reuse the supported source locations so admission and the selected
		# Terran view cannot diverge when another verified system is connected.
		var source_world: Dictionary={}
		for world in Worlds.SYSTEMS.values():
			if world.station_ids.has(data.get("station_id")):source_world=world;break
		if data.get("station_id")!=98 and not source_world.is_empty():
			if Values.equal_value(data,ordinary_view(shared,int(data.station_id),source_hangar_row(source_world,2))):return true
		elif Values.equal_value(data,alioth_view(shared)):return true
	return false

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, station: Dictionary) -> String:
	if not data is Dictionary:return "Missing station presentation declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or station.get("scope")!="first_station_entry":return "Unsupported station presentation"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Station presentation lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid station presentation provenance"
	var layouts: Array=[]
	if _parameters(data,VALUES):layouts.append(SPANS)
	if _parameters(data,MAC_VALUES):layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid station presentation extent"
