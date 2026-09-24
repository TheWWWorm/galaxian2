extends RefCounted
## Original Kappa fighter lifecycle and EMP faction reactions.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"kappa_ordinary_combat_lifecycle","campaign_cursor":21,"system_id":11,"actor_kinds":[0,0,0,0],"primary_faction":0,"reaction_factions":[0,1],"system_faction_field":2,"terran_hostility":{"axis":0,"hostile_below":-70,"friendly_above":70},"systems":{"initial_requested_damage":0,"requested_damage_bits":32,"warning_divisor":3,"requires_primary_faction":true,"skips_script_hostile":true,"nonplayer_provokes":false,"depletion_forces_matching_faction":true,"depletion_response_radio":false,"reputation_axis":0,"reputation_change":-2,"repeated_depletion_changes_reputation":true,"first_disable_counts_player_event":true},"actor_suppression_flags":[false,false,false]}
const SPANS = {"kappa_lifecycle_systems_hit":[538094,842],"kappa_lifecycle_normal_hit":[538936,1846],"kappa_lifecycle_systems_reputation":[808262,16],"kappa_lifecycle_reputation_adjust":[808046,184],"kappa_lifecycle_current_system":[872722,14],"kappa_lifecycle_system_faction":[734664,10],"kappa_lifecycle_actor_constructor":[-81548,948],"kappa_lifecycle_attached_actor":[-77806,14],"kappa_lifecycle_warning":[119652,34],"kappa_lifecycle_response":[113780,214],"kappa_lifecycle_mission_radio_filter":[113994,2616],"kappa_lifecycle_persistent_hostility":[535624,28]}

# Native composition.
const Fighters=preload("res://src/content/kappa_fighters_definitions.gd")
const MAC_SPANS = {"kappa_lifecycle_systems_hit":[538630,842],"kappa_lifecycle_normal_hit":[539472,1846],"kappa_lifecycle_systems_reputation":[808894,16],"kappa_lifecycle_reputation_adjust":[808678,184],"kappa_lifecycle_current_system":[873354,14],"kappa_lifecycle_system_faction":[735296,10],"kappa_lifecycle_actor_constructor":[-81548,948],"kappa_lifecycle_attached_actor":[-77806,14],"kappa_lifecycle_warning":[119652,34],"kappa_lifecycle_response":[113780,214],"kappa_lifecycle_mission_radio_filter":[113994,2616],"kappa_lifecycle_persistent_hostility":[536160,28]}

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)
static func available(bindings: RefCounted) -> bool:
	return Fighters.available(bindings) and parameters(bindings.mido_travel.get("kappa_lifecycle"))
