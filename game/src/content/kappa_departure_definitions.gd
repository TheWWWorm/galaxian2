extends RefCounted
## Verified station launch rules, independent of mission completion predicates.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Outcome=preload("res://src/content/kappa_outcome_definitions.gd")
const VALUES = {"scope":"kappa_station_departure","preparation_cursor":20,"rescue_cursor":21,"target_station_only":true,"installed_item_ids":[41],"minimum_quantity":1,"refusal_text_id":520}
const SPANS = {"kappa_departure_launch":[437002,744],"kappa_departure_installed_quantity":[730284,106],"kappa_departure_item_id":[-84678,8],"kappa_departure_item_quantity":[-84494,9],"kappa_departure_station_id":[851352,9],"kappa_departure_mission_station":[400888,9],"kappa_departure_inventory":[858126,13],"kappa_departure_station":[858084,13],"kappa_departure_mission":[858168,20],"kappa_departure_cursor":[858156,12],"kappa_departure_installed_slots":[730042,10]}
const MAC_VALUES = {"scope":"kappa_station_departure","preparation_cursor":20,"rescue_cursor":21,"target_station_only":true,"installed_item_ids":[41,42,43],"minimum_quantity":1,"refusal_text_id":520}
const MAC_SPANS = {"kappa_departure_launch":[437438,820],"kappa_departure_installed_quantity":[730916,106],"kappa_departure_item_id":[-84678,8],"kappa_departure_item_quantity":[-84494,9],"kappa_departure_station_id":[851984,9],"kappa_departure_mission_station":[401404,9],"kappa_departure_inventory":[858758,13],"kappa_departure_station":[858716,13],"kappa_departure_mission":[858800,20],"kappa_departure_cursor":[858788,12],"kappa_departure_installed_slots":[730666,10]}

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES) or Equal.equal_value(data,MAC_VALUES)

static func available(bindings: RefCounted) -> bool:
	return Outcome.available(bindings) and parameters(bindings.mido_travel.get("kappa_departure"))
