extends "res://src/presentation/portal_geometry.gd"
## Sahi admission and phase guards; the flight owner supplies every clock/pose.
const Stage=preload("res://src/content/sahi_stage_definitions.gd")
var _rules:={}

func build(library: RefCounted,visuals: RefCounted,bindings: RefCounted,context: Dictionary) -> bool:
	if bindings==null or not Stage.selected(bindings.mido_travel,context):return reject("This world has no selected Sahi portal stage")
	var rules: Dictionary=Stage.declarations(bindings.mido_travel,context)
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":int(rules.campaign_cursor),"system_id":int(rules.system_id),
		"station_id":int(rules.station_id),"mission_kind":int(rules.mission_kind),
		"model_id":int(rules.portal.model_id),"slot":int(rules.portal.environment_slot)}
	if not _build_portal(library,visuals,bindings,identity):return false
	_rules=rules;visible=false
	return true

func prepare_state(state: Dictionary) -> Dictionary:
	var phase: Variant=state.get("phase")
	var elapsed: Variant=state.get("elapsed_ms")
	if _rules.is_empty() or not phase is int or not elapsed is int:return failed("Sahi portal requires its accepted native phase and elapsed time")
	if phase<int(_rules.sequence.initial_phase) or phase>int(_rules.sequence.open_phase):return failed("Sahi portal phase is outside the selected stage")
	if elapsed<int(_rules.portal.open_elapsed_ms) or not state.get("visible") is bool:return failed("Sahi portal lost its native appearance clock")
	if phase<int(_rules.sequence.open_phase):
		if state.visible or elapsed!=0:return failed("Sahi portal opened before its native open phase")
	elif state.visible!=(elapsed<int(_rules.portal.hide_at_ms)):
		return failed("Sahi portal visibility disagrees with its native appearance clock")
	return super.prepare_state(state)
