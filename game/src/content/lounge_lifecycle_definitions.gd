extends RefCounted
## Retain original quotes and consumed contacts until their location is evicted.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"mido_station_contact_retention","capacity":3,"replacement_order":"oldest_insertion","revisit_changes_order":false,"cached_quotes_repriced":false}
const SPANS = {"lounge_lifecycle_lookup":[855620,94],"lounge_lifecycle_insert":[855396,204],"lounge_lifecycle_identity":[853288,22],"lounge_lifecycle_current":[855731,20],"lounge_lifecycle_arrival":[856712,38],"lounge_lifecycle_generation":[856903,62],"lounge_lifecycle_ordinary_stock":[857285,83]}

const MAC_SPANS = {"lounge_lifecycle_lookup":[856252,94],"lounge_lifecycle_insert":[856028,204],"lounge_lifecycle_identity":[853920,22],"lounge_lifecycle_current":[856363,20],"lounge_lifecycle_arrival":[857344,38],"lounge_lifecycle_generation":[857535,62],"lounge_lifecycle_ordinary_stock":[857917,83]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.early_contracts.get("station_lounges"))
