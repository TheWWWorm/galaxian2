extends RefCounted
## Optional station10 stock. Its medal flag must come from retained native
## profile state; this declaration does not award medals or infer a profile.
const Layouts=preload("res://src/content/declaration_layouts.gd")
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const BaseStock=preload("res://src/content/base_station_stock_definitions.gd")
const VALUES := {"scope":"deep_science_base_station_stock","station_id":10,"first_cursor":15,"last_cursor":83,"all_base_gold_count":1,"all_base_gold_ship_id":8,"base_medal_count":36,"gold_level":1,"required_medal_id":30,"required_campaign_cursor":45}
const SPANS := {"station10_count":[-240253,114],"station10_fixed_ship":[-240063,216],"all_base_gold":[-726102,106],"all_base_gold_getter":[-725984,12],"retained_medals":[-725630,110],"medal_dispatch":[-727879,128],"required_medal_dispatch":[-726378,4],"required_medal_predicate":[-726907,20],"required_medal_levels":[1544402,12],"required_campaign_progress":[858140,28]}
const MAC_SPANS := {"station10_count":[-241720,110],"station10_fixed_ship":[-241531,213],"all_base_gold":[-731998,106],"all_base_gold_getter":[-731880,12],"retained_medals":[-731526,110],"medal_dispatch":[-733775,128],"required_medal_dispatch":[-732274,4],"required_medal_predicate":[-732803,20],"required_medal_levels":[1519386,12],"required_campaign_progress":[858772,28]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant,source_bytes: int,arch: String,arrival: Dictionary,base_stock: Dictionary) -> String:
	if not data is Dictionary:return "Missing Deep Science stock declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not BaseStock.parameters(base_stock):return "Unsupported Deep Science stock declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Deep Science stock lacks its source anchor"
	var spans: Dictionary=MAC_SPANS if Equal.equal_value(base_stock,BaseStock.MAC_VALUES) else SPANS
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,[spans]) else "Invalid Deep Science stock extents"

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and bindings.get("source_architecture")=="x86_64" and parameters(bindings.get("deep_science_stock")) and BaseStock.available(bindings)
