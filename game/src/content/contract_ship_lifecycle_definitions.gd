extends RefCounted
## Native contract combat uses the shared ordinary ship lifecycle.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const ShipCombat=preload("res://src/content/contract_ship_combat_definitions.gd")
const TrainingDeath=preload("res://src/content/combat_training_destruction_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const VALUES = {"scope":"mido_contract_ship_lifecycle","campaign_cursor":13,"selection_skipped_modes":[3,4],"initial_death_modes":[0,1],"retains_forced_friendship":true,"reputation":{"factions":[0,1,2,3,8],"axes":[0,0,1,1,1],"lethal_changes":[-5,5,-5,5,-1]},"reactions":{"primary_faction":3,"eligible_factions":[3,2],"radio_requires_empty_mission":true,"empty_mission_kind":-1,"force_matching_faction_only":true},"cargo_models":[{"actor_kind":0,"cargo_model_id":16992,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_003_terran.aem"},{"actor_kind":1,"cargo_model_id":16991,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_004_vossk.aem"},{"actor_kind":2,"cargo_model_id":16993,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_002_nivelian.aem"},{"actor_kind":3,"cargo_model_id":16990,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_001_midorian.aem"},{"actor_kind":8,"cargo_model_id":16993,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_002_nivelian.aem"}],"objectives":{"pirate_kind":18,"challenge_success_kind":20,"challenge_failure_kind":21,"challenge_first_actor":1,"challenge_actor_kind":8,"destroyed_mode":4,"challenge_requires_player_majority":true}}
const SPANS = {"ship_lifecycle_normal_hit":[538936,1846],"ship_lifecycle_lethal_reputation":[807862,184],"ship_lifecycle_reputation_axis":[808046,184],"ship_lifecycle_secondary_faction":[734674,76],"ship_lifecycle_faction_response":[113780,214],"ship_lifecycle_empty_mission":[400436,14],"ship_lifecycle_reaction_exclusion":[-77806,14],"ship_lifecycle_base_actor":[-81548,948],"ship_lifecycle_npc_update":[610766,17180],"ship_lifecycle_world_death":[106510,1044],"ship_lifecycle_nonhostile_death":[107650,12],"ship_lifecycle_objectives":[481000,1170],"ship_lifecycle_cargo_model":[-77266,246],"ship_lifecycle_radio_gate":[114020,59]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

# Native setup helpers.
static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.early_contracts.get("ship_lifecycle")) and ShipCombat.parameters(bindings.early_contracts.get("ship_combat")) and TrainingDeath.parameters(bindings.combat_training_destruction) and Travel.parameters(bindings.mido_travel)

static func supported_kinds(kinds: Array) -> bool:
	if kinds.size() not in [2,3,4] or not kinds.all(func(value):return value is int):return false
	if kinds.all(func(value):return value==8):return true
	return kinds.size()==4 and kinds[0] in [0,1,2,3] and kinds.slice(1)==[8,8,8]

static func npc_hit(data: Dictionary,weapon: Dictionary) -> bool:
	if data.get("campaign_cursor") not in [13,14] or not data.get("npc_weapons") is Array:return false
	for row in data.npc_weapons:
		var matches:=true
		for key in ["item_id","category","kind","damage","nonplayer_source"]:
			if weapon.get(key)!=row.get(key):matches=false;break
		if matches:return true
	return false

static func population(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if not available(bindings):return {}
	var data:=ShipCombat.population(bindings,packet)
	if data.is_empty() or not supported_kinds(data.actor_kinds):return {}
	data.lifecycle=bindings.early_contracts.ship_lifecycle.duplicate(true)
	data.reputation_state=packet.contract_encounter.context.reputation.duplicate(true)
	data.mission=packet.contract_encounter.mission.duplicate(true)
	data.cargo=bindings.combat_training_destruction.cargo.duplicate(true)
	data.selection_skipped_modes=data.lifecycle.selection_skipped_modes.map(func(mode):return int(mode))
	data.nonhostile_remaining_delta=int(bindings.combat_training_destruction.nonhostile_remaining_delta)
	data.actors=[]
	for actor in packet.actors:
		var row: Dictionary={}
		for key in ["actor_id","actor_kind","hull_catalogue_id","subtype","population_group"]:row[key]=actor[key]
		row.hostile=actor.population_group=="pirate"
		for model in data.lifecycle.cargo_models:
			if int(model.actor_kind)==actor.actor_kind:
				row.cargo_model_id=int(model.cargo_model_id);row.cargo_model_resource=model.cargo_model_resource
		if not row.has("cargo_model_id"):return {}
		data.actors.append(row)
	return data
