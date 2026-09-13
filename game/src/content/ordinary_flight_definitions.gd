extends RefCounted
## Shared context selection above the individual mission declaration readers.
const Mining=preload("res://src/content/full_hold_flight_definitions.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
const MiningStory=preload("res://src/content/full_hold_story_definitions.gd")
const MiningReturn=preload("res://src/content/full_hold_return_definitions.gd")
const FirstReturn=preload("res://src/content/station_return_definitions.gd")

static func select(bindings: RefCounted, cursor: Variant) -> Dictionary:
	if bindings==null or not cursor is int:return {}
	return Training.flight(bindings) if cursor==7 else Mining.flight(bindings,cursor)

static func briefing(bindings: RefCounted,cursor: Variant) -> Dictionary:
	return Training.briefing(bindings) if cursor==7 else MiningStory.briefing(bindings,cursor)

static func objective(bindings: RefCounted,cursor: Variant) -> Dictionary:
	return Training.objective(bindings) if cursor==7 else MiningStory.objective(bindings,cursor)

static func docking(bindings: RefCounted,cursor: Variant) -> Dictionary:
	if cursor!=8:return MiningReturn.select(bindings,cursor)
	if bindings==null or not Training.parameters(bindings.combat_training_story) or not FirstReturn.parameters(bindings.station_return):return {}
	var complete:=Training.station_return(bindings)
	if not complete.is_empty():return complete
	var result: Dictionary=bindings.station_return.duplicate(true)
	result.departing_cursor=7;result.campaign_cursor=8;result.minimum_delivered_cargo=0
	return result

static func docking_parameters(rules: Dictionary) -> bool:
	if FirstReturn.parameters(rules) or MiningReturn.parameters(rules):return true
	if Training.station_return_parameters(rules):return true
	if rules.get("departing_cursor")!=7 or rules.get("campaign_cursor")!=8 or rules.get("minimum_delivered_cargo")!=0:return false
	var original:=rules.duplicate(true)
	for key in ["departing_cursor","campaign_cursor","minimum_delivered_cargo"]:original[key]=FirstReturn.VALUES[key]
	return FirstReturn.parameters(original)

static func station_return(bindings: RefCounted,cursor: Variant) -> Dictionary:
	return Training.station_return(bindings) if cursor==8 else MiningReturn.select(bindings,cursor)
