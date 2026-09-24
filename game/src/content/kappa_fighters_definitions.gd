extends RefCounted
## Original common fighter systems and target rules for Kappa.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"kappa_shared_fighters","campaign_cursor":21,"systems":{"capacity_base":40,"capacity_rank_multiplier":5,"capacity_rank_limit":20,"capacity_limit":140,"recovery_ms":15000,"subtype":0},"frame":{"recover_before_guidance":true,"disabled_root_commit":false,"disabled_bank_commit":true,"disabled_fire_permission_unchanged":true},"player_weapon_targets":[0,1,2,3],"npc_target_memberships":[[-1],[-1],[-1],[-1]],"initial_permanent_friendly":false,"holding_proximity_requires_hostile":true,"holding_target_requires_hostile":false}
const SPANS = {"kappa_fighters_shared_factory":[77944,3478],"kappa_fighters_systems_initializer":[535708,56],"kappa_fighters_systems_update":[612681,60],"kappa_fighters_disabled_motion":[624443,343],"kappa_fighters_target_membership":[59038,2050],"kappa_fighters_fire_gate":[542670,494],"kappa_fighters_holding_activation":[617194,408],"kappa_fighters_target_activation":[619682,255]}

# Native composition.
const MAC_SPANS = {"kappa_fighters_shared_factory":[77944,3478],"kappa_fighters_systems_initializer":[536244,56],"kappa_fighters_systems_update":[613229,60],"kappa_fighters_disabled_motion":[624991,343],"kappa_fighters_target_membership":[59038,2050],"kappa_fighters_fire_gate":[543206,494],"kappa_fighters_holding_activation":[617742,408],"kappa_fighters_target_activation":[620230,255]}

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("kappa_fighters"))

static func systems(bindings: RefCounted,rank: int) -> Dictionary:
	if not available(bindings) or rank<0:return {}
	var source: Dictionary=bindings.mido_travel.kappa_fighters.systems
	var capacity:=int(source.capacity_limit)
	if rank<=int(source.capacity_rank_limit):capacity=int(source.capacity_base)+rank*int(source.capacity_rank_multiplier)
	return {"capacity":capacity,"recovery_ms":int(source.recovery_ms)}
