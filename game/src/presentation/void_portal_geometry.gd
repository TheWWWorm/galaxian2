extends "res://src/presentation/portal_geometry.gd"
const Definitions=preload("res://src/content/void_portal_definitions.gd")

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted,context: Dictionary) -> bool:
	if bindings==null or not Definitions.selected(bindings.mido_travel,context):return reject("This world has no returning Void portal")
	var rules: Dictionary=bindings.mido_travel.void_portal
	return _build_portal(library,visuals,bindings,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":int(context.campaign_cursor),"system_id":int(context.system_id),"station_id":int(context.station_id),
		"mission_kind":int(context.mission_kind),"model_id":int(rules.portal.model_id),"slot":int(rules.portal.environment_slot)})
