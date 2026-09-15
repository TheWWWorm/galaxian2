extends RefCounted
## Imported environment parameters; campaign authorization belongs to the station.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Life=preload("res://src/content/alioth_lifecycle_definitions.gd")
const VALUES = {"scope":"alioth_flight_environment","campaign_cursor":16,"station_id":98,"system_id":19,"portal":{"model_id":16994,"environment_slot":3,"initial_elapsed_ms":0,"initial_extent":4096,"open_duration_ms":3000,"close_start_ms":60000,"hide_at_ms":63001,"extent_scale":4096,"model_scale_shift":4,"model_scale_fraction":1.52587890625e-05,"facing_x_offset":0.5,"animation_advances_while_hidden":true,"closed_relocates":false}}
const SPANS = {"alioth_flight_portal_update":[655588,1380],"alioth_flight_portal_vtable":[2401610,192],"alioth_flight_portal_draw":[656968,34],"alioth_flight_portal_facing":[655548,26],"alioth_flight_portal_duration":[1546010,4],"alioth_flight_portal_extent":[1588942,4],"alioth_flight_portal_scale":[1575014,4],"alioth_flight_portal_facing_offset":[1544586,4]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return Life.available(bindings) and parameters(bindings.mido_travel.get("alioth_flight"))
