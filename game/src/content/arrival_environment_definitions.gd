extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Source ordinary sky and planet selection after the opening escape.
const Declarations=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"fresh_rescue_environment","campaign_cursor":1,"world_type":3,"special_system_id":27,"maximum_sky_index":14,"supported_planet_type":0,"sky_mesh_base":17800,"sky_texture_base":10065,"current_planet_size_factor":1,"current_planet_texture_source":"near_textures"}
const SPANS := {"x86_64":{"sky_gate":[0,94],"sky_plain":[437,106],"sky_special":[913951,78],"planet_scale":[884606,74],"constant_1832e5":[1585893,4],"planet_current":[882686,64],"planet_near":[882765,61],"constant_18e615":[1631765,8]},"armv7":{"sky_gate":[0,78],"sky_plain":[130,76],"sky_special":[853656,56],"planet_scale":[824158,70],"planet_half":[823828,4],"planet_current":[823196,56],"planet_near":[823088,60]}}

const MAC_ALTERNATE := {"sky_gate":[0,94],"sky_plain":[437,106],"sky_special":[914583,78],"planet_scale":[885238,74],"constant_1832e5":[1560877,4],"planet_current":[883318,64],"planet_near":[883397,61],"constant_18e615":[1606861,8]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Declarations.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, bytes: int, arch: String, sky: Dictionary, actors: Dictionary, arrival: Dictionary) -> String:
	if not data is Dictionary:return "Missing rescue environment capability"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(arch):return "Unsupported rescue environment declarations"
	if actors.get("player_initialization",{}).get("flight_cache",{}).is_empty() or arrival.get("campaign_cursor")!=1 or sky.get("planet_resources",{}).is_empty():return "Rescue environment lacks its source player, sky or staging context"
	var origin: Variant=sky.get("provenance",{}).get("opening")
	if not Fonts.extent(origin,"offset","bytes",[71 if arch=="x86_64" else 62],bytes):return "Rescue environment lacks its sky anchor"
	if data.provenance.size()!=SPANS[arch].size():return "Invalid rescue environment provenance"
	var layouts: Array=[SPANS[arch]]
	if arch=="x86_64":layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(origin.offset),bytes,layouts) else "Disconnected rescue environment declaration"
