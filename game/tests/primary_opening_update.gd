extends SceneTree
const Primary = preload("res://src/simulation/primary_weapons.gd")
const Mixed = preload("res://src/simulation/ordinary_opening_contacts.gd")
const Inventory = preload("res://src/simulation/opening_target_inventory.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Bodies = preload("res://src/simulation/scenery_bodies.gd")
const Scenery = preload("res://src/simulation/opening_scenery.gd")
const BodyResources = preload("res://src/content/scenery_body_resources.gd")
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const Mounts = preload("res://src/content/weapon_mounts.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
var failures := 0

func _initialize() -> void:
	check(Primary.new().evaluate_opening_update(null,null,null,0).is_empty(),"Unconfigured opening update accepted")
	check(Mixed.new().evaluate(null,null,null,null).is_empty(),"Missing mixed contact owners accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/binding/visual triples")
	for index in range(0,args.size()-2,3): check_profile(args[index],args[index+1])
	print("Primary opening updates: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library) or not library.select_language("gb"):
		check(false,library.error+bindings.error+catalogues.error);return
	var mounts := Mounts.new();var loadout := Loadout.new();var owner := Primary.new()
	var scenery := Scenery.new();var resources := BodyResources.new();var inventory := Inventory.new()
	if not mounts.open(library,catalogues) or not loadout.configure(bindings,catalogues,catalogues.content_id) or not owner.configure(bindings,catalogues,mounts,loadout.snapshot()):
		check(false,mounts.error+loadout.error+owner.error);return
	if not scenery.configure(bindings,catalogues,1789100000) or not resources.configure(library,bindings):
		check(false,scenery.error+resources.error);return
	var field := scenery.snapshot()
	# Controlled contact geometry using actual source models, scales and counts.
	# This arrangement is a test fixture, not a claim about authored placement.
	for index in field.objects.size(): field.objects[index].position=Vector3.ZERO if index==0 else Vector3(25000,25000,25000)
	var bodies := Bodies.new();var combat := Combat.new();var timeline := Timeline.new()
	var counts := [];counts.resize(23);counts.fill(1)
	check(bodies.configure(bindings,field,resources),bodies.error)
	check(combat.configure(bindings,catalogues,0.5),combat.error)
	check(timeline.configure(bindings,catalogues,library,counts),timeline.error)
	var scene: Dictionary = timeline.snapshot().scene
	var radio: Dictionary = timeline.snapshot().radio;radio.finished[7]=true
	for actor in scene.actors: actor.position=Vector3.ZERO;actor.erase("pose")
	check(combat.update(scene,3,radio),combat.error)
	check(combat.normal_hit(0,144).accepted,"Could not stage NPC death")
	check(combat._actors[1].set_permissions(true,false,true),"Could not stage damage immunity")
	check(bodies.normal_hit(0,bodies.snapshot().objects[0].initial_hull-6).accepted,"Could not stage scenery death")
	check(inventory.configure(bindings,catalogues,field),inventory.error)
	check(inventory.validate_owners(combat.snapshot(),bodies.snapshot()),inventory.error)
	check(not owner.advance(1).is_empty(),owner.error)
	var volley := owner.fire(Transform3D.IDENTITY,true)
	check(volley.weapons[0].slot==1 and volley.weapons[1].slot==0,"Firing order changed")
	var before := owner.snapshot();var before_combat := combat.snapshot();var before_bodies := bodies.snapshot();var before_inventory := inventory.snapshot()
	for gun in before.guns: check(not gun.contact_pass_evaluated and gun.last_contact_target==null,"New gun invented an evaluated contact result")
	var result := owner.evaluate_opening_update(combat,bodies,inventory,0)
	check(not result.is_empty(),owner.error)
	if result.is_empty(): return
	var order := [];var deaths := 0;var accepted := 0
	for event in result.weapons:
		for contact in event.contacts:
			order.append([event.slot,contact.target.group,contact.target.index])
			if contact.damage.destroyed_now: deaths+=1
			if contact.damage.accepted: accepted+=1
		check(event.motion.cleared.size()==1 and event.motion.moved.is_empty(),"Mixed impact cleanup did not run after the full zero-time pass")
	check(order==[[0,"npc",0],[0,"npc",1],[0,"npc",2],[0,"scenery",0],[1,"npc",1],[1,"npc",2]],"Cross-group availability or per-gun eligibility/order changed")
	check(deaths==2 and accepted==4,"Mixed deaths or immunity changed")
	check(result.weapons[0].last_contact_target=={"group":"scenery","index":0} and result.weapons[1].last_contact_target=={"group":"npc","index":2},"Last contact lost its target group")
	check(result.combat.snapshot().actors[2].vitals.hull==138 and result.bodies.has_pending_destruction(),"Mixed live state was not retained")
	check(result.combat.snapshot().actors[1].contact and not result.combat.snapshot().actors[1].damage_allowed,"Immune NPC lost contact metadata")
	check(result.bodies.snapshot().objects[0].contact,"Cross-group shot lost scenery contact metadata")
	for gun in result.primaries.snapshot().guns:
		check(gun.projectiles.slots[0]==null and gun.projectiles.elapsed_ms==0,"Mixed zero-time update moved time or retained an impact")
		check(gun.contact_pass_evaluated and gun.last_contact_target==({"group":"scenery","index":0} if gun.equipment.slot==0 else {"group":"npc","index":2}),"Gun did not retain its evaluated last target")
	check(owner.snapshot()==before and combat.snapshot()==before_combat and bodies.snapshot()==before_bodies and inventory.snapshot()==before_inventory,"Mixed update changed input owners")
	var retained: Dictionary = result.primaries.snapshot()
	result.weapons[0].last_contact_target.index=999
	var detached: Dictionary = result.primaries.snapshot();detached.guns[0].last_contact_target.index=999
	check(result.primaries.snapshot()==retained,"Last-target event or snapshot aliases the gun owner")
	var next: Dictionary = result.primaries.evaluate_opening_update(result.combat,result.bodies,inventory,1)
	check(not next.is_empty(),result.primaries.error)
	for event in next.weapons: check(event.contacts.is_empty() and event.last_contact_target==null,"Cleared shots damaged again or retained stale last contact")
	for gun in next.primaries.snapshot().guns: check(gun.contact_pass_evaluated and gun.last_contact_target==null,"Empty contact pass retained a stale gun target")
	# An earlier gun contacts both groups and clears its shot in staging before
	# the later gun's time overflow invalidates the complete result.
	var extreme: RefCounted = owner.fork_state();extreme._guns[0].projectiles._elapsed_ms=2147483647
	var extreme_before: Dictionary = extreme.snapshot()
	check(extreme.evaluate_opening_update(combat,bodies,inventory,1).is_empty(),"Later gun time overflow accepted")
	check(extreme.snapshot()==extreme_before and combat.snapshot()==before_combat and bodies.snapshot()==before_bodies,"Later gun failure committed staged cross-group hits")
	var legacy: RefCounted = owner.fork_state()
	for gun in legacy._guns: gun.projectiles._weapon.erase("collision_bounds")
	check(legacy.evaluate_opening_update(combat,bodies,inventory,0).is_empty(),"Missing weapon bounds were invented")
	check(not legacy.evaluate_opening_update(combat,bodies,inventory,0,{"mode":"target"}).is_empty(),"Explicit legacy bounds rejected")
	for delta in [null,true,-1,0.5,2147483648]: check(owner.evaluate_opening_update(combat,bodies,inventory,delta).is_empty(),"Invalid mixed update time accepted")
	var foreign: RefCounted = bodies.fork_for_frame();foreign._identity.binding_id="e".repeat(64)
	check(owner.evaluate_opening_update(combat,foreign,inventory,0).is_empty(),"Foreign body owner accepted")
	var missing: RefCounted = bodies.fork_for_frame();missing._rows.pop_back();missing._vitals.pop_back()
	check(owner.evaluate_opening_update(combat,missing,inventory,0).is_empty(),"Incomplete world target group accepted")
	var unarmed := Primary.new();var changed := loadout.snapshot();changed.slots.fill(null);changed.equipment_ids=[]
	check(unarmed.configure(bindings,catalogues,mounts,changed),unarmed.error)
	check(unarmed.evaluate_opening_update(combat,bodies,inventory,0).is_empty(),"Changed loadout silently reused fresh optional-group absence")
	# Inject a failing body query after NPC hits have already been staged. This
	# tests transactional failure, not a reachable source-population bound.
	var invalid_bodies: RefCounted = bodies.fork_for_frame()
	invalid_bodies._rows[0].half_extent=-1
	var projectile: RefCounted = owner._guns[0].projectiles.fork_state()
	var old_projectile: Dictionary = projectile.snapshot();var old_invalid_bodies: Dictionary = invalid_bodies.snapshot()
	var operation := Mixed.new()
	check(operation.evaluate(projectile,combat,invalid_bodies,inventory).is_empty(),"Late scenery query failure accepted")
	check(projectile.snapshot()==old_projectile and combat.snapshot()==before_combat and invalid_bodies.snapshot()==old_invalid_bodies,"Failed scenery query committed earlier NPC contacts")
	print(library.manifest.profile.edition,": full target order, cross-group retention, per-gun cleanup, sequential damage and rollback verified")

func check(condition: bool, message: String) -> void:
	if not condition: failures+=1;push_error(message)
