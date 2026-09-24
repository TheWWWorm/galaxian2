extends "res://src/presentation/portal_geometry.gd"
## Alioth admission for the shared original wormhole renderer.
const Definitions=preload("res://src/content/alioth_flight_definitions.gd")

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	if not Definitions.available(bindings):return reject("This pack has no supported Alioth portal")
	return _build_portal(library,visuals,bindings,{"base_content_id":bindings.base_content_id,
		"binding_id":bindings.binding_id,"campaign_cursor":16,"model_id":16994,"slot":3})
