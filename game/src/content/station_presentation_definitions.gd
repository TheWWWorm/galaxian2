extends RefCounted
## Recovered first-station view constants; scoped separately from progression.
const Values=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"first_station_presentation","station_id":78,"hangar_row":3,"camera":{"position":[1800,800,-1778],"angles":[-0.20000000298023224,2.569999933242798,-0.029999999329447746],"rotation_order":"YXZ","projection":[0.800000011920929,200.0,100000.0],"initial_jitter_bound":150,"phase_start":4.71238899230957,"phase_limit":7.853981852531433,"phase_rate":9.58738019107841e-05,"endpoint_tolerance":5.0,"endpoint_min":[18,30,50],"endpoint_range":[131,120,100],"max_frame_ms":150},"light":{"initial_camera_yaw":0.39269909262657166,"direction_bias":[-0.20000000298023224,-0.30000001192092896,0],"material_ambient":0.699999988079071,"diffuse":[1,1,1],"ambient":[0.44999998807907104,0.25,0.25],"specular":[0.5,0.5,0.5],"specular_power":96.0},"portraits":{"0":{"status":"fixed","family":0,"parts":[0,0,0,0]},"2":{"status":"fixed","family":2,"parts":[1,1,1,1]},"16":{"status":"fixed","family":11,"parts":[1,0,0,2]}},"dialogue":{"next_text_id":179,"final_text_id":180,"start_delay_ms":1000,"silent_text_id":1696,"voice_event_ids":[267,268,277,278,279,280,281,282,283,284,269,270,271,272,273,274,275,276],"stop_previous_voice":true,"atmosphere_event_id":122}}
const SPANS := {"scene_kind":[414874,39],"projection":[-700407,39],"initial_camera":[-700353,193],"light_direction":[422340,141],"station_lights":[425834,467],"environment_row":[422497,222],"camera_seed":[422719,800],"camera_jitter":[423519,273],"frame_clock":[442938,75],"camera_update":[444038,942],"rotation_dispatch":[1243229,38],"rotation_yxz":[1243901,307],"tween_sample":[1324538,180],"tween_reset":[1324826,74],"tween_clock":[1324906,166],"next_label_and_voice_stop":[-692441,90],"final_label_and_voice_start":[-686960,143],"voice_lookup":[-215216,68],"voice_not_found":[-212901,14],"atmosphere_start":[425005,38],"dialogue_delay":[444980,14],"portrait_selection":[-692155,24],"portrait_composition":[-86396,159],"mission_no_actor":[399358,16],"mission_actor_getter":[401310,10],"position_table":[1585242,120],"pitch_table":[1585370,40],"yaw_table":[1585418,40],"alternate_yaw_table":[1585466,40],"roll":[1585034,4],"projection_values":[1545978,12],"initial_yaw":[1545998,4],"direction_x_bias":[1582946,4],"direction_y_bias":[1582914,4],"light_material_ambient":[1556918,4],"light_diffuse":[1544610,4],"light_ambient_rg":[1585054,8],"light_ambient_gb":[1556906,4],"light_specular":[1544586,4],"light_power":[1585062,4],"tween_phase":[1596354,16],"tween_tau":[1587986,8],"tween_half":[1582354,8],"endpoint_tolerance":[1557114,4],"rotation_slots":[1245194,24],"light_slots":[426302,32],"voice_lookup_table":[1560154,12032],"portrait_pointer_0":[2396762,8],"portrait_pointer_2":[2396778,8],"portrait_pointer_16":[2396890,8],"portrait_gunant":[2411386,20],"portrait_instruction":[2411834,20],"zero_fill_section":[-750798,80]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Values.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, station: Dictionary) -> String:
	if not data is Dictionary:return "Missing station presentation declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or station.get("scope")!="first_station_entry":return "Unsupported station presentation"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Station presentation lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid station presentation provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid station presentation extent: "+key
	return ""
