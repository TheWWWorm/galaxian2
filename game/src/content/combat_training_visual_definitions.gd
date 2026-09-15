extends RefCounted
## Original ordinary weapon models and captured firing orientation for training.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Weapons=preload("res://src/content/combat_training_weapon_definitions.gd")
const Projectiles=preload("res://src/content/projectile_visual_definitions.gd")
const Impacts=preload("res://src/content/projectile_impact_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")

const VALUES := {"scope":"combat_training_ordinary_visuals","campaign_cursor":7,"weapons":[{"owner":"player","actor_ids":[],"item_id":0,"kind":0,"capacity":20,"projectile_model_id":6754,"projectile_resource":"resources/data/assets/main/3d/meshes/fx/projectile_000_anim_add.aem","impact_model_id":14600,"impact_resource":"resources/data/assets/main/3d/meshes/fx/impact_000_lookat_anim_add.aem"},{"owner":"player","actor_ids":[],"item_id":22,"kind":2,"capacity":25,"projectile_model_id":6798,"projectile_resource":"resources/data/assets/main/3d/meshes/fx/projectile_022_anim_add.aem","impact_model_id":14606,"impact_resource":"resources/data/assets/main/3d/meshes/fx/impact_006_lookat_anim_add.aem"},{"owner":"npc","actor_ids":[0,1,2],"item_id":19,"kind":1,"capacity":4,"projectile_model_id":6795,"projectile_resource":"resources/data/assets/main/3d/meshes/fx/projectile_019_anim_add.aem","impact_model_id":14605,"impact_resource":"resources/data/assets/main/3d/meshes/fx/impact_005_lookat_anim_add.aem"},{"owner":"npc","actor_ids":[3],"item_id":25,"kind":0,"capacity":4,"projectile_model_id":6802,"projectile_resource":"resources/data/assets/main/3d/meshes/fx/projectile_026_anim_add.aem","impact_model_id":14606,"impact_resource":"resources/data/assets/main/3d/meshes/fx/impact_006_lookat_anim_add.aem"}],"player_effect_setup_before_field_seed":true,"player_impact_assignments":1,"impact_random_flip_used":false}
const SPANS := {"wrapper_default":[475185,6],"captured_up_draw":[479454,55],"captured_up_launch":[-186411,59],"matrix_up":[1241222,15],"player_flag":[-187812,14],"impact_0":[1572842,4],"impact_19":[1572918,4],"impact_22":[1572930,4],"impact_25":[1572942,4],"projectile_0":[1576458,4],"projectile_22":[1576546,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, weapons: Dictionary, staging: Dictionary) -> String:
	if not data is Dictionary:return "Missing training weapon visuals"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported training weapon visuals"
	if not Weapons.parameters(weapons) or not Projectiles.parameters(staging.get("projectile_visuals")) or not Impacts.parameters(staging.get("projectile_impacts")):return "Training visuals lack shared weapon and animation declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Training visuals lack their source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid training visual provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid training visual extent: "+key
	return ""

static func model(data: Dictionary, weapon: Dictionary, key: String, impact: bool) -> Dictionary:
	if not parameters(data) or weapon.get("campaign_cursor")!=7 or weapon.get("category")!=0:return {}
	for row in data.weapons:
		if weapon.get("item_id")!=row.item_id or weapon.get("kind")!=row.kind or weapon.get("projectile_capacity")!=row.capacity:continue
		if row.owner=="player":
			if not key.begins_with("player:") or weapon.get("nonplayer_source",false):continue
		else:
			if not weapon.get("nonplayer_source",false) or not row.actor_ids.any(func(id):return key=="npc:%d"%int(id)):continue
		return {"id":int(row.impact_model_id if impact else row.projectile_model_id),
			"resource":row.impact_resource if impact else row.projectile_resource,"captured_up":row.owner=="player"}
	return {}

static func local_model(data: Dictionary, travel: Dictionary, weapon: Dictionary, key: String, impact: bool) -> Dictionary:
	if not parameters(data) or not Travel.parameters(travel) or weapon.get("campaign_cursor") not in [10,11,12] or weapon.get("category")!=0:return {}
	if weapon.campaign_cursor in [11,12] and Travel.journey(travel,weapon.campaign_cursor).is_empty():return {}
	# The same catalogue weapons use the same original model assignments.
	# Only population membership changes: local kind-3 ships occupy 0..3.
	var source:=weapon.duplicate(true)
	source.campaign_cursor=7
	if key.begins_with("player:"):
		if weapon.get("item_id")!=22:return {}
		return model(data,source,key,impact)
	if weapon.get("item_id")!=int(travel.traffic_combat.weapon.item_id):return {}
	if weapon.campaign_cursor==10 and key not in ["npc:0","npc:1","npc:2","npc:3"]:return {}
	if not key.begins_with("npc:") or not key.substr(4).is_valid_int() or int(key.substr(4))<0:return {}
	return model(data,source,"npc:3",impact)
