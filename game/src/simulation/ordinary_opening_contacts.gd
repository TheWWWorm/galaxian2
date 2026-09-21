extends RefCounted
## Complete target-group ordering for the verified fresh opening. Each group
## keeps its own damage semantics; shots remain available across group boundaries.
## This operation does not advance projectiles or complete an encounter.
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Bodies = preload("res://src/simulation/scenery_bodies.gd")
const Inventory = preload("res://src/simulation/opening_target_inventory.gd")
const NpcContacts = preload("res://src/simulation/ordinary_npc_contacts.gd")
const SceneryContacts = preload("res://src/simulation/ordinary_scenery_contacts.gd")
var error := ""

func evaluate(projectiles: RefCounted, combat: RefCounted, bodies: RefCounted, inventory: RefCounted, bounds_selection: Variant = null) -> Dictionary:
	error=""
	if projectiles==null or projectiles.get_script()!=Projectiles or combat==null or combat.get_script()!=Combat or bodies==null or bodies.get_script()!=Bodies:
		return fail("Opening contacts require ordinary projectiles and both native target owners")
	if inventory==null or inventory.get_script()!=Inventory:
		return fail("Opening contacts require the verified fresh target inventory")
	if not inventory.validate_owners(combat.snapshot(),bodies.read_snapshot()): return fail(inventory.error)
	var targets: Dictionary = inventory.snapshot()
	var npc_operation := NpcContacts.new()
	var npc := npc_operation.evaluate(projectiles,combat,targets.npc_ids,bounds_selection)
	if npc.is_empty(): return fail(npc_operation.error)
	# Impact marking retains position/velocity. The same real projectile can
	# consequently contact a scenery body after contacting an overlapping NPC.
	var scenery_operation := SceneryContacts.new()
	var scenery := scenery_operation.evaluate(npc.projectiles,bodies,targets.scenery_indices,bounds_selection)
	if scenery.is_empty(): return fail(scenery_operation.error)
	var contacts := []
	for hit in npc.contacts:
		contacts.append(tagged(hit,"npc",hit.actor_id))
	for hit in scenery.contacts:
		contacts.append(tagged(hit,"scenery",hit.object_index))
	var last_target: Variant = null
	if not contacts.is_empty(): last_target=contacts.back().target.duplicate()
	return {"projectiles":scenery.projectiles,"combat":npc.combat,"bodies":scenery.bodies,
		"contacts":contacts,"last_contact_target":last_target}

static func tagged(hit: Dictionary, group: String, index: int) -> Dictionary:
	var result := hit.duplicate(true)
	result.erase("actor_id");result.erase("object_index")
	result.target={"group":group,"index":index}
	return result

func fail(message: String) -> Dictionary:
	error=message;return {}
