extends RefCounted
## Original delivery eligibility and acknowledged settlement rules.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"mido_delivery_results","delivery_kinds":[0,11],"active_flight_excluded_kinds":[11],"success_result_mode":1,"acknowledgement_result":1,"clear_first_marked_item_ids":[116,117],"completion_increment":1,"completion_rank_weight":2,"notification_sound_id":36,"maximum_station_reward":1000000,"maximum_credit_delta":1000000000,"credit_bits":32,"minimum_credits":0,"reputation":{"faction_axes":[0,0,1,1],"faction_signs":[1,-1,1,-1],"success_change":5,"hardest_difficulty":1.5,"hardest_multiplier":2,"minimum":-100,"maximum":100}}
const SPANS = {"delivery_objective":[873444,251],"delivery_target":[875132,33],"delivery_dispatch":[874924,16],"delivery_kind_table":[875394,28],"delivery_result_construction":[-694652,84],"delivery_result_flags":[-693644,164],"delivery_acknowledgement":[427938,40],"delivery_unloading":[428261,649],"delivery_settlement":[431448,261],"delivery_success_counter":[859750,12],"delivery_retirement":[875530,304],"delivery_credit_delta":[872054,48],"delivery_credit_notification":[-50878,68],"delivery_reputation_result":[-688141,37],"delivery_reputation_delta":[808246,16],"delivery_reputation_apply":[808046,184],"delivery_reputation_difficulty":[873106,34],"delivery_reputation_difficulty_value":[1545698,4],"delivery_client_faction":[-233851,28],"delivery_faction_argument":[-231877,51],"delivery_faction_constructor":[398988,19],"delivery_faction_getter":[400764,10],"delivery_rank_score":[876028,136],"delivery_active_selection":[856965,661]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func standing_after(rules: Dictionary,prior: Dictionary,faction: int,difficulty: float) -> Dictionary:
	var result:=prior.duplicate(true)
	var reputation: Dictionary=rules.reputation
	if faction>=0 and faction<reputation.faction_axes.size():
		var axis:=int(reputation.faction_axes[faction])
		var delta:=int(reputation.success_change)*int(reputation.faction_signs[faction])
		if difficulty==float(reputation.hardest_difficulty):delta*=int(reputation.hardest_multiplier)
		result.axes[axis]=clampi(result.axes[axis]+delta,int(reputation.minimum),int(reputation.maximum))
	return result
