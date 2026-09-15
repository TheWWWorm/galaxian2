extends RefCounted
## Resolve source weapon parameters for explicit owned equipment. This does not
## establish ownership, ammo use, projectile-kind support or a valid hit target.
const Definitions = preload("res://src/content/weapon_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const TrainingWeapons = preload("res://src/content/combat_training_weapon_definitions.gd")
const Fitting=preload("res://src/content/ordinary_fitting_definitions.gd")
var error := ""
var base_content_id := ""
var binding_id := ""
var _data := {}
var _items := []
var _training := {}
var _fitting := {}

func clear() -> void:
	error = ""
	base_content_id = ""
	binding_id = ""
	_data = {}
	_items = []
	_training = {}
	_fitting = {}

func configure(bindings: RefCounted, catalogues: RefCounted, content_id: String) -> bool:
	clear()
	if bindings==null or catalogues==null or not Library.valid_hash(content_id) or content_id!=bindings.base_content_id or content_id!=catalogues.content_id or not Library.valid_hash(bindings.binding_id):
		return reject("Weapon loadout requires matching content and bindings")
	if not Definitions.parameters(bindings.weapon_parameters) or not catalogues.tables.get("items") is Array:
		return reject("This content has no supported weapon parameter declarations")
	_data = bindings.weapon_parameters.duplicate(true)
	# JSON numbers arrive as floats; Array membership compares Variant types.
	# Normalize declared IDs before using them with integer catalogue indices.
	if not _data.get("launch_modes",{}).is_empty():
		for i in _data.launch_modes.alternate_item_ids.size():
			_data.launch_modes.alternate_item_ids[i]=int(_data.launch_modes.alternate_item_ids[i])
	_items = catalogues.tables.items.duplicate(true)
	if TrainingWeapons.parameters(bindings.combat_training_weapons):_training=bindings.combat_training_weapons.player_primary.duplicate(true)
	if Fitting.available(bindings):_fitting=bindings.mido_travel.ordinary_fitting.duplicate(true)
	base_content_id = content_id
	binding_id = bindings.binding_id
	return true

func resolve(item_id: Variant, equipment_ids: Array) -> Dictionary:
	error = ""
	if _data.is_empty(): return fail("Configure the weapon loadout before resolving an item")
	if not item_index(item_id) or equipment_ids.size()>4096: return fail("Weapon or equipment list is outside this catalogue")
	var item: Dictionary = _items[item_id]
	var category: Variant = item_value(item,int(_data.item_category_value_index))
	var kind: Variant = item_value(item,int(_data.item_type_value_index))
	if not Vitals.integer(category) or category>2 or not Vitals.integer(kind): return fail("Selected item has no supported weapon category/type")
	var properties: Variant = item.get("properties")
	if not properties is Dictionary: return fail("Weapon has no property table")
	var values := {}
	for field in ["damage", "interval", "lifetime", "speed"]:
		var value: Variant = properties.get(int(_data[field+"_property"]))
		if not Vitals.integer(value): return fail("Weapon lacks a supported "+field+" property")
		values[field] = value
	var damage_factor := float(_data.default_multiplier)
	var interval_factor := damage_factor
	var selected := -1
	# Source equipment order matters: the last matching modifier replaces factors.
	for id in equipment_ids:
		if not item_index(id): return fail("Installed equipment is outside this catalogue")
		var other: Dictionary = _items[id]
		var other_type: Variant = item_value(other,int(_data.item_type_value_index))
		if not Vitals.integer(other_type): return fail("Installed equipment lacks its source type")
		if other_type!=int(_data.modifier_type): continue
		var other_properties: Variant = other.get("properties")
		if not other_properties is Dictionary: return fail("Weapon modifier has no property table")
		var reduction: Variant = other_properties.get(int(_data.interval_percent_property))
		var bonus: Variant = other_properties.get(int(_data.damage_percent_property))
		if not signed_integer(reduction) or not signed_integer(bonus): return fail("Weapon modifier lacks required percentages")
		interval_factor = Vitals.single(float(_data.default_multiplier)-Vitals.single(Vitals.single(float(reduction))/float(_data.percent_divisor)))
		damage_factor = Vitals.single(float(_data.default_multiplier)+Vitals.single(Vitals.single(float(bonus))/float(_data.percent_divisor)))
		if interval_factor==float(_data.missing_multiplier): interval_factor=float(_data.default_multiplier)
		if damage_factor==float(_data.missing_multiplier): damage_factor=float(_data.default_multiplier)
		selected=id
	var damage: int = values.damage
	var interval: int = values.interval
	if category==int(_data.primary_category):
		var scaled_damage := float(damage)
		var scaled_interval := 0.0
		if damage_factor<0 and damage<int(_data.low_damage_threshold):
			scaled_interval=Vitals.single(Vitals.single(interval_factor*float(_data.low_damage_interval_scale))*Vitals.single(float(interval)))
		else:
			scaled_damage=Vitals.single(Vitals.single(float(damage))*damage_factor)
			scaled_interval=Vitals.single(Vitals.single(float(interval))*interval_factor)
		if not convertible(scaled_damage) or not convertible(scaled_interval): return fail("Weapon modifiers produce unsupported damage or interval")
		damage=int(scaled_damage)
		interval=int(scaled_interval)
	if interval<1 or values.lifetime<1 or values.speed<1: return fail("Weapon requires a separate non-projectile or zero-interval implementation")
	var launch_mode := "unsupported"
	var modes: Dictionary = _data.get("launch_modes",{})
	if category==0 and kind==0 and not modes.is_empty():
		launch_mode="alternate" if item_id in modes.get("alternate_item_ids",[]) else "ordinary"
	var dispersed: bool=not _training.is_empty() and item_id==int(_training.item_id) and category==int(_training.category) and kind==int(_training.kind)
	if dispersed:launch_mode="ordinary"
	var fitted:=Fitting.primary(_fitting,item_id,int(kind)) if category==0 and not _fitting.is_empty() else {}
	if not fitted.is_empty() and item_id not in modes.get("alternate_item_ids",[]):launch_mode="ordinary"
	var result := {"base_content_id":base_content_id,"binding_id":binding_id,"item_id":item_id,"category":category,"kind":kind,
		"damage":damage,"interval_ms":interval,"lifetime_ms":values.lifetime,"speed_units_per_millisecond":Vitals.single(float(values.speed)),
		"modifier_item_id":selected,"damage_multiplier":damage_factor,"interval_multiplier":interval_factor,"launch_mode":launch_mode}
	if launch_mode=="ordinary" and not _data.get("projectile_capacity",{}).is_empty():
		result.projectile_capacity=int(_data.projectile_capacity.slots)
	if dispersed:
		result.projectile_capacity=int(_training.projectile_capacity)
		result.dispersion=_training.dispersion.duplicate(true)
	if not fitted.is_empty() and launch_mode=="ordinary":
		result.projectile_capacity=fitted.projectile_capacity
		result.fitting_primary=true
		if fitted.has("dispersion"):result.dispersion=fitted.dispersion
	var hit_policy: Dictionary = _data.get("ordinary_hit_policy",{})
	if launch_mode=="ordinary" and not hit_policy.is_empty():
		var additional: Variant = properties.get(int(hit_policy.additional_damage_property),int(hit_policy.missing_additional_damage))
		if not signed_integer(additional): return fail("Malformed additional damage property")
		result.ordinary_hit_policy = {"additional_damage":additional,
			"additional_damage_required":additional!=int(hit_policy.missing_additional_damage),
			"nonplayer_damage":damage}
	if launch_mode=="ordinary" and not _data.get("collision_bounds",{}).is_empty():
		result.collision_bounds={"mode":_data.collision_bounds.mode}
	return result

func item_index(value: Variant) -> bool:
	return value is int and value>=0 and value<_items.size() and _items[value] is Dictionary

func item_value(item: Dictionary, index: int) -> Variant:
	var arrays: Variant = item.get("arrays")
	if not arrays is Array or arrays.size()!=3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or index>=arrays[2].size(): return null
	return arrays[2][index]

static func signed_integer(value: Variant) -> bool:
	return value is int and value>=-2147483648 and value<=2147483647

static func convertible(value: float) -> bool:
	return is_finite(value) and value>=0 and value<=Vitals.MAX_SHIELD

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
