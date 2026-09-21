extends RefCounted
## Native ownership of ordinary primaries for an explicit player equipment state.
## Actor permission, world scheduling, target lists and consequences belong to
## the encounter owner. No unsupported primary is silently replaced or omitted.
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Weapons = preload("res://src/simulation/weapon_loadout.gd")
const Opening = preload("res://src/simulation/opening_loadout.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Library = preload("res://src/content/library.gd")
const Contacts = preload("res://src/simulation/ordinary_npc_contacts.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const OpeningContacts = preload("res://src/simulation/ordinary_opening_contacts.gd")
const TargetInventory = preload("res://src/simulation/opening_target_inventory.gd")
const SceneryBodies = preload("res://src/simulation/scenery_bodies.gd")
const Audio = preload("res://src/simulation/weapon_audio.gd")
const TrainingWeapons = preload("res://src/content/combat_training_weapon_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
var error := ""
var _loadout := {}
var _guns: Array = []
var _next_mount_id := 1

func clear() -> void:
	error = ""
	_loadout = {}
	_guns = []

func configure(bindings: RefCounted, catalogues: RefCounted, mounts: RefCounted, loadout: Dictionary) -> bool:
	clear()
	var content_id: Variant = loadout.get("base_content_id")
	if not Library.valid_hash(content_id) or bindings == null or catalogues == null or mounts == null:
		return reject("Primary weapons require an explicit content loadout")
	if loadout.get("binding_id") != bindings.binding_id or mounts.snapshot().get("base_content_id") != content_id:
		return reject("Primary equipment, mounts and bindings have different identities")
	if loadout.has("campaign_cursor") and (loadout.campaign_cursor not in [7,10,11,12,13,14,16,18,19] or not loadout.campaign_cursor is int or not TrainingWeapons.parameters(bindings.combat_training_weapons)):
		return reject("Unsupported primary encounter context")
	if loadout.get("campaign_cursor") in [10,11,12,13,14] and Travel.player_entry(bindings.mido_travel,int(loadout.get("station_id",-1)),int(loadout.campaign_cursor)).is_empty():return reject("Local primary entry requires its supported location")
	if loadout.get("campaign_cursor")==16 and (load("res://src/content/alioth_population_definitions.gd").flight(bindings,int(loadout.get("station_id",-1))).is_empty()):return reject("Alioth primary entry requires its supported location")
	if loadout.get("campaign_cursor") in [18,19] and (load("res://src/content/free_flight_definitions.gd").flight(bindings,int(loadout.get("station_id",-1)),int(loadout.campaign_cursor)).is_empty()):return reject("Ordinary primary entry requires its supported location")
	if loadout.get("campaign_cursor")==13 and not ContractLife.available(bindings):return reject("Contract primary contacts require supported lifecycle declarations")
	var resolver := Weapons.new()
	if not resolver.configure(bindings,catalogues,content_id): return reject(resolver.error)
	var ship_id: Variant = loadout.get("ship_id")
	if not Vitals.integer(ship_id): return reject("Invalid primary owner ship")
	var stats: Dictionary = catalogues.ship_stats(ship_id)
	if stats.is_empty(): return reject(catalogues.error)
	var slots: Variant = loadout.get("slots")
	if not slots is Array: return reject("Primary ownership requires ordered equipment slots")
	var counts := []
	var total := 0
	for property in Opening.SLOT_PROPERTIES:
		var count: Variant = stats.get(property)
		if not Vitals.integer(count) or count > 255: return reject("Unsupported ship equipment extent")
		counts.append(count)
		total += count
	if slots.size() != total: return reject("Equipment extent disagrees with the ship catalogue")
	var ordered_ids := []
	var primary := []
	var index := 0
	var items: Array = catalogues.tables.items
	for category in counts.size():
		for slot in counts[category]:
			var equipment: Variant = slots[index]
			index += 1
			if equipment == null: continue
			if not equipment is Dictionary: return reject("Invalid equipment slot record")
			for field in ["item_id", "category", "slot", "quantity"]:
				if not Vitals.integer(equipment.get(field)): return reject("Invalid equipment field: " + field)
			if equipment.category != category or equipment.slot != slot or equipment.item_id >= items.size():
				return reject("Equipment category, slot or item is outside its owner")
			if resolver.item_value(items[equipment.item_id],int(bindings.weapon_parameters.item_category_value_index)) != category:
				return reject("Installed equipment category disagrees with its source item")
			ordered_ids.append(equipment.item_id)
			if category == 0: primary.append(equipment.duplicate(true))
	if loadout.get("equipment_ids") != ordered_ids:
		return reject("Equipment modifier order disagrees with installed slots")
	# Source builds each category backwards while visiting installed slots forwards.
	# Empty slots stay absent; they do not shift the authored category-slot number.
	primary.reverse()
	var staged := []
	var resolved := []
	if _next_mount_id > 9223372036854775807 - primary.size(): return reject("Weapon handle limit exceeded")
	for equipment in primary:
		var weapon: Dictionary = resolver.resolve(equipment.item_id,ordered_ids)
		if weapon.is_empty(): return reject(resolver.error)
		if loadout.has("campaign_cursor"):weapon.campaign_cursor=loadout.campaign_cursor
		resolved.append(weapon)
		var mount: Dictionary = mounts.resolve(ship_id,0,equipment.slot)
		if mount.is_empty(): return reject(mounts.error)
		var projectiles := Projectiles.new()
		if not projectiles.configure(weapon): return reject(projectiles.error)
		# No contact result exists before the first pass. This native sentinel
		# does not assert an initialized source pointer before its verified reset.
		staged.append({"mount_id":_next_mount_id+staged.size(),"equipment":equipment,
			"mount":mount,"projectiles":projectiles,"contact_pass_evaluated":false,"last_contact_target":null,"audio":{}})
	var audio: Dictionary=bindings.weapon_parameters.get("audio",{})
	if not audio.is_empty():
		var entries := Audio.player_entries(audio,items,resolved)
		if entries.size()!=staged.size():return reject("Primary weapons lack supported sound selection")
		for i in staged.size():staged[i].audio=entries[i]
	_guns = staged
	_next_mount_id += staged.size()
	_loadout = {"base_content_id":content_id,"binding_id":bindings.binding_id,
		"ship_id":ship_id,"slots":slots.duplicate(true),"equipment_ids":ordered_ids}
	if loadout.has("campaign_cursor"):_loadout.campaign_cursor=loadout.campaign_cursor
	return true

func snapshot() -> Dictionary:
	if _loadout.is_empty(): return {}
	var guns := []
	for gun in _guns:
		guns.append({"mount_id":gun.mount_id,"equipment":gun.equipment.duplicate(true),
			"mount":gun.mount.duplicate(true),"projectiles":gun.projectiles.snapshot(),
			"audio":gun.audio.duplicate(),
			"contact_pass_evaluated":gun.contact_pass_evaluated,
			"last_contact_target":null if gun.last_contact_target==null else gun.last_contact_target.duplicate()})
	return {"loadout":_loadout.duplicate(true),"guns":guns}

func fork_state() -> RefCounted:
	var staged: RefCounted = get_script().new()
	staged._loadout = _loadout.duplicate(true)
	staged._next_mount_id = _next_mount_id
	for gun in _guns:
		staged._guns.append({"mount_id":gun.mount_id,"equipment":gun.equipment.duplicate(true),
			"mount":gun.mount.duplicate(true),"projectiles":gun.projectiles.fork_state(),
			"audio":gun.audio.duplicate(),
			"contact_pass_evaluated":gun.contact_pass_evaluated,
			"last_contact_target":null if gun.last_contact_target==null else gun.last_contact_target.duplicate()})
	return staged

func reset_fire_intervals() -> bool:
	error=""
	if _loadout.is_empty():return reject("Configure primary ownership before resetting firing intervals")
	var next:=fork_state()
	for gun in next._guns:
		if not gun.projectiles.reset_fire_interval():return reject(gun.projectiles.error)
	_guns=next._guns
	return true

func evaluate_npc_update(combat: RefCounted, ordered_actor_ids: Variant, delta_ms: Variant, bounds_selection: Variant = null) -> Dictionary:
	error = ""
	if _loadout.is_empty(): return fail("Configure primary ownership before NPC updates")
	if not Vitals.integer(delta_ms): return fail("Primary time must be nonnegative integer milliseconds")
	if combat==null or combat.get_script()!=Combat: return fail("Primary NPC updates require the opening NPC owner")
	var state: Dictionary = combat.snapshot()
	if state.get("base_content_id")!=_loadout.base_content_id or state.get("binding_id")!=_loadout.binding_id:
		return fail("Primary weapons and NPCs have different content identities")
	if not ordered_actor_ids is Array or ordered_actor_ids.size()>65536:
		return fail("Primary NPC updates require an explicit bounded ordered target list")
	var staged_combat: RefCounted = combat.fork_for_frame()
	for id in ordered_actor_ids:
		if staged_combat.collision_context(id).is_empty(): return fail(staged_combat.error)
	var staged: RefCounted = fork_state()
	var operation := Contacts.new()
	var events := []
	# Source wrappers append in equipment creation order and the world updates
	# that list forwards. The primary firing array itself was filled backwards.
	for index in range(staged._guns.size()-1,-1,-1):
		var gun: Dictionary = staged._guns[index]
		var contacts: Dictionary = operation.evaluate(gun.projectiles,staged_combat,ordered_actor_ids,bounds_selection)
		if contacts.is_empty(): return fail(operation.error)
		var motion: Dictionary = contacts.projectiles.advance(delta_ms)
		if motion.is_empty(): return fail(contacts.projectiles.error)
		gun.projectiles=contacts.projectiles
		gun.contact_pass_evaluated=true
		gun.last_contact_target=null if contacts.last_contact_actor_id==null else {"group":"npc","index":contacts.last_contact_actor_id}
		staged_combat=contacts.combat
		events.append({"mount_id":gun.mount_id,"slot":gun.equipment.slot,"item_id":gun.equipment.item_id,
			"contacts":contacts.contacts,"motion":motion})
	return {"primaries":staged,"combat":staged_combat,"weapons":events}

func evaluate_opening_update(combat: RefCounted, bodies: RefCounted, inventory: RefCounted, delta_ms: Variant, bounds_selection: Variant = null) -> Dictionary:
	error=""
	if _loadout.is_empty(): return fail("Configure primary ownership before opening updates")
	if not Vitals.integer(delta_ms): return fail("Primary time must be nonnegative integer milliseconds")
	if combat==null or combat.get_script()!=Combat or bodies==null or bodies.get_script()!=SceneryBodies:
		return fail("Opening primary updates require both native target owners")
	if inventory==null or inventory.get_script()!=TargetInventory:
		return fail("Opening primary updates require the verified fresh target inventory")
	# Even an unarmed owner must belong to the complete verified opening world.
	if not inventory.validate_loadout(_loadout) or not inventory.validate_owners(combat.snapshot(),bodies.read_snapshot()):
		return fail(inventory.error)
	var staged: RefCounted = fork_state()
	var staged_combat: RefCounted = combat.fork_for_frame()
	var staged_bodies: RefCounted = bodies.fork_for_frame()
	var operation := OpeningContacts.new()
	var events := []
	for index in range(staged._guns.size()-1,-1,-1):
		var gun: Dictionary = staged._guns[index]
		var result := operation.evaluate(gun.projectiles,staged_combat,staged_bodies,inventory,bounds_selection)
		if result.is_empty(): return fail(operation.error)
		# Cleanup belongs after this gun's COMPLETE target list, never between
		# NPCs and scenery or after every gun has completed a global contact pass.
		var motion: Dictionary = result.projectiles.advance(delta_ms)
		if motion.is_empty(): return fail(result.projectiles.error)
		gun.projectiles=result.projectiles
		gun.contact_pass_evaluated=true
		gun.last_contact_target=null if result.last_contact_target==null else result.last_contact_target.duplicate()
		staged_combat=result.combat;staged_bodies=result.bodies
		events.append({"mount_id":gun.mount_id,"slot":gun.equipment.slot,"item_id":gun.equipment.item_id,
			"contacts":result.contacts,"last_contact_target":result.last_contact_target,"motion":motion})
	return {"primaries":staged,"combat":staged_combat,"bodies":staged_bodies,"weapons":events}

func fire(firing_transform: Variant, firing_allowed: Variant, random_state: Variant=null) -> Dictionary:
	error = ""
	if _loadout.is_empty(): return fail("Configure primary ownership before firing")
	if not firing_transform is Transform3D or not firing_transform.is_finite() or not firing_allowed is bool:
		return fail("Primary firing requires a finite transform and explicit actor permission")
	var next_random: Variant=null
	if random_state!=null:
		var random:=Random.new()
		if not random.restore(random_state):return fail(random.error)
		next_random=random.snapshot()
	var staged := []
	var events := []
	for gun in _guns:
		var projectiles: RefCounted = gun.projectiles.fork_state()
		var result := {"fired":false,"reason":"quantity"}
		if gun.equipment.quantity > 0:
			result = projectiles.fire_forward_from_mount(gun.mount,firing_transform,firing_allowed,next_random)
		if result.is_empty(): return fail(projectiles.error)
		if result.has("random_state"):next_random=result.random_state
		staged.append(projectiles)
		events.append({"mount_id":gun.mount_id,"slot":gun.equipment.slot,
			"item_id":gun.equipment.item_id,"result":result})
		if not gun.audio.is_empty():
			var cues := []
			if result.fired:
				var cue := Audio.cue(gun.audio,firing_transform.origin)
				if not cue.is_empty():cues.append(cue)
			events[-1].audio_events=cues
	for i in _guns.size(): _guns[i].projectiles = staged[i]
	# Ordinary primary shots do not consume the installed item's quantity.
	var outcome:={"weapons":events}
	if next_random!=null:outcome.random_state=next_random
	return outcome

func advance(delta_ms: Variant) -> Dictionary:
	error = ""
	if _loadout.is_empty(): return fail("Configure primary ownership before advancing")
	if not Vitals.integer(delta_ms): return fail("Primary time must be nonnegative integer milliseconds")
	var staged := []
	var events := []
	for gun in _guns:
		var projectiles: RefCounted = gun.projectiles.fork_state()
		var result: Dictionary = projectiles.advance(delta_ms)
		if result.is_empty(): return fail(projectiles.error)
		staged.append(projectiles)
		events.append({"mount_id":gun.mount_id,"slot":gun.equipment.slot,
			"item_id":gun.equipment.item_id,"result":result})
	for i in _guns.size(): _guns[i].projectiles = staged[i]
	return {"weapons":events}

func retire(mount_id: Variant, projectile_id: Variant) -> bool:
	error = ""
	if not mount_id is int or mount_id < 1: return reject("Invalid weapon handle")
	for gun in _guns:
		if gun.mount_id == mount_id:
			if gun.projectiles.retire(projectile_id): return true
			return reject(gun.projectiles.error)
	return reject("Weapon handle is stale or belongs to another primary owner")

func mark_impact(mount_id: Variant, projectile_id: Variant) -> bool:
	error = ""
	if not mount_id is int or mount_id < 1: return reject("Invalid impact weapon handle")
	for gun in _guns:
		if gun.mount_id == mount_id:
			if gun.projectiles.mark_impact(projectile_id): return true
			return reject(gun.projectiles.error)
	return reject("Impact weapon handle is stale or belongs to another primary owner")

func reject(message: String) -> bool:
	error = message
	return false

func fail(message: String) -> Dictionary:
	error = message
	return {}
