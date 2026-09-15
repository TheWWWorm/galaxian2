extends RefCounted
## Verified early ship-contract result timing and settlement.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Life=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Delivery=preload("res://src/content/delivery_result_definitions.gd")
const VALUES = {"scope":"mido_contract_flight_results","campaign_cursor":13,"ship_kinds":[4,12],"success_poll_milliseconds":5001,"success_requires_idle_radio":true,"reset_missed_poll":true,"failure_uses_success_gate":false,"success_result_mode":1,"failure_result_mode":2,"success_count_on_open":true,"reputation_excluded_kinds":[12,183],"penalty_kind":12,"penalty_uses_base_reward":true,"empty_mission_kind":-1,"retain_flight_after_acknowledgement":true}
const SPANS = {"flight_result_success_poll":[385744,2546],"flight_result_failure_poll":[388290,794],"flight_result_failure_controller":[118652,24],"flight_result_result_flags":[-693644,164],"flight_result_result_content":[-692464,5780],"flight_result_acknowledgement":[348260,11612],"flight_result_side_slot":[859522,22],"flight_result_active_slot":[858112,14],"flight_result_objective_slots":[118602,22],"flight_result_poll_clock":[365135,8],"flight_result_poll_order":[377531,71]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

# Native helpers.
static func available(bindings: RefCounted) -> bool:
	return Life.available(bindings) and parameters(bindings.early_contracts.get("flight_results")) and Delivery.parameters(bindings.early_contracts.get("delivery_results"))

static func standing_after(terms: Dictionary,prior: Dictionary,kind: int,faction: int,difficulty: float) -> Dictionary:
	if not parameters(terms.get("flight_results")) or not Delivery.parameters(terms.get("delivery_results")):return {}
	if terms.flight_results.reputation_excluded_kinds.any(func(value):return int(value)==kind):return prior.duplicate(true)
	return Delivery.standing_after(terms.delivery_results,prior,faction,difficulty)
