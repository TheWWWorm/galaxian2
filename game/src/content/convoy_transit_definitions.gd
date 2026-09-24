extends RefCounted
## Ordinary Mido travel keeps the acknowledged story and independent side slot.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"mido_convoy_transit","campaign_cursor":14,"system_id":15,"story_kind":4,"story_station_id":79,"story_reward":0,"requires_target_match":true,"story_precedes_side_mission":true,"retains_side_mission":true,"npc_weapon_interval_ms":572}
const SPANS = {"convoy_transit_selection":[856506,1129],"convoy_transit_story_factory":[861385,38],"convoy_transit_story_slot":[859544,122],"convoy_transit_departure_selection":[428158,29],"convoy_transit_departure_state":[431869,126],"convoy_transit_weapon_interval":[57315,107]}

const MAC_SPANS = {"convoy_transit_selection":[857138,1129],"convoy_transit_story_factory":[862017,38],"convoy_transit_story_slot":[860176,122],"convoy_transit_departure_selection":[428586,29],"convoy_transit_departure_state":[432297,126],"convoy_transit_weapon_interval":[57315,107]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(data: Dictionary) -> bool:
	return parameters(data.get("convoy_transit"))

static func supports(data: Dictionary,cursor: Variant) -> bool:
	return cursor is int and (cursor==13 or (cursor==14 and available(data)))

static func mission(data: Dictionary) -> Dictionary:
	if not available(data):return {}
	var rules: Dictionary=data.convoy_transit
	return {"kind":int(rules.story_kind),"station_id":int(rules.story_station_id),"reward":int(rules.story_reward),"bonus":0,"source_parameter":0}

static func selected(data: Dictionary,cursor: Variant,station_id: Variant,story: Dictionary) -> bool:
	return cursor==14 and available(data) and story==mission(data) and station_id==int(data.convoy_transit.story_station_id)
