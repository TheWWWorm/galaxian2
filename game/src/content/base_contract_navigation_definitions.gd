extends RefCounted
## Original navigation rules and the supported captured-station quotation.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"base_contract_navigation","arrival_station_id":98,"arrival_system_id":19,"arrival_cursor":15,"availability_field":1,"valkyrie_system_id":25,"links_array":2,"position_fields":[3,4,5],"depth_divisor":10,"distance_multiplier":18.850000381469727,"excluded_station_ids":[10,22,27,29,30,48,55,56,76,79,91,98,1,33,47,86,58,65,66,74,81,100,101,102,103,104,105,106,107,108,83,85,92,109,110,11,113,121,126,131,38,90,91,93,94,82,40,15,60,95,70,80],"excluded_station_range":[109,113],"global_station_bound":135,"system_count":34,"local_override_system":15}
const SPANS = {"base_navigation_system_fields":[-673257,102],"base_navigation_system_arguments":[-672644,107],"base_navigation_system_constructor":[734118,211],"base_navigation_availability_getter":[735376,12],"base_navigation_availability_initial":[882509,61],"base_navigation_availability_expansion":[883536,25],"base_navigation_availability_accessors":[855338,30],"base_navigation_destination":[-237234,450],"base_navigation_excluded_stations":[1557514,208],"base_navigation_links_getter":[735314,10],"base_navigation_distance":[-658498,346],"base_navigation_distance_scale":[1557062,4],"base_navigation_distance_fields":[734968,30],"base_navigation_distance_subtract":[1058634,96],"base_navigation_quote_destination":[-233980,129],"base_navigation_quote_early_gate":[-233617,136],"base_navigation_quote_distance_reward":[-232466,157],"base_navigation_alioth_factory":[861428,38]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.early_contracts.get("base_navigation"))
