extends RefCounted
## Original authored contacts and population rules. Services remain separate.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Layouts=preload("res://src/content/declaration_layouts.gd")
const Ordinary=preload("res://src/content/ordinary_generation_definitions.gd")
const VALUES = {"scope":"persistent_blueprint_lounge_contacts","supported_contact_ids":[5],"station_id":10,"system_id":6,"first_cursor":17,"fields":{"id":0,"station":1,"system":2,"faction":3,"male":4,"role4_parameter":5,"blueprint":6,"role8_parameter":7,"price":8},"male_value":1,"blueprint_role":3,"count":{"minimum":3,"draw_bound":2,"probe_maximum":4,"maximum":5},"portrait":{"family_index":0,"parts_start":1,"part_count":4},"authored_first":true,"authored_order":"table","hostile_replacement_requires_generated":true}
const SPANS = {"persistent_count":[-236767,267],"persistent_loader":[-675370,696],"persistent_constructor":[-720294,434],"persistent_station":[-719568,10],"persistent_system":[-719578,10],"persistent_roster":[-235772,178],"persistent_hostile_replacement":[-235591,387],"persistent_insertion":[-236439,667],"persistent_role_getter":[-719598,10],"persistent_generated_getter":[-719502,14],"persistent_portrait_setter":[-719488,14],"persistent_constructor_wrapper":[-720362,68],"persistent_blueprint_getter":[-718898,10],"persistent_price_getter":[-718660,10]}
const MAC_SPANS = {"persistent_count":[-237787,267],"persistent_loader":[-681258,696],"persistent_constructor":[-726190,434],"persistent_station":[-725464,10],"persistent_system":[-725474,10],"persistent_roster":[-236792,178],"persistent_hostile_replacement":[-236611,387],"persistent_insertion":[-237459,667],"persistent_role_getter":[-725494,10],"persistent_generated_getter":[-725398,14],"persistent_portrait_setter":[-725384,14],"persistent_constructor_wrapper":[-726258,68],"persistent_blueprint_getter":[-724794,10],"persistent_price_getter":[-724556,10]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant,source_bytes: int,architecture: String,arrival: Dictionary,ordinary_generation: Dictionary) -> String:
	if not data is Dictionary:return "Missing persistent contact declarations"
	if data.is_empty():return ""
	if architecture!="x86_64" or not parameters(data) or not Ordinary.parameters(ordinary_generation):return "Unsupported persistent contact declarations"
	var source: Variant=arrival.get("provenance")
	if not source is Dictionary:return "Persistent contacts lack their source anchor"
	var anchor: Variant=source.get("actor")
	if not Fonts.extent(anchor,"offset","bytes",[315],source_bytes):return "Persistent contacts lack their source anchor"
	return "" if Layouts.matches(data.provenance,int(anchor.offset),source_bytes,[SPANS,MAC_SPANS]) else "Invalid persistent contact extents"

# Additional native locations using the same proved blueprint-contact branch.
# Identity, portrait, offer and price remain in the player's original table.
const BLUEPRINT_LOCATIONS={5:{"system_id":1,"contact_ids":[6]},32:{"system_id":2,"contact_ids":[1]},43:{"system_id":8,"contact_ids":[4]},90:{"system_id":18,"contact_ids":[9]}}

static func contact_ids(data: Dictionary,station_id: int,system_id: int) -> Array:
	if not parameters(data):return []
	if station_id==int(data.station_id) and system_id==int(data.system_id):return data.supported_contact_ids
	var location: Dictionary=BLUEPRINT_LOCATIONS.get(station_id,{})
	return location.contact_ids if location.get("system_id",-1)==system_id else []

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and bindings.get("source_architecture")=="x86_64" and parameters(bindings.get("persistent_contacts")) and Ordinary.available(bindings)
