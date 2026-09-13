extends SceneTree
const Primary = preload("res://src/simulation/primary_weapons.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const Mounts = preload("res://src/content/weapon_mounts.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
const Opening = preload("res://src/simulation/opening_loadout.gd")
var failures := 0

func _initialize() -> void:
	check(Primary.new().evaluate_npc_update(null,[],0).is_empty(),"Unconfigured primary update accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/binding/visual triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Primary NPC updates: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library) or not library.select_language("gb"):
		check(false,library.error+bindings.error+catalogues.error);return
	var mounts := Mounts.new();var opening := Opening.new();var owner := Primary.new()
	if not mounts.open(library,catalogues) or not opening.configure(bindings,catalogues,catalogues.content_id) or not owner.configure(bindings,catalogues,mounts,opening.snapshot()):
		check(false,mounts.error+opening.error+owner.error);return
	var combat := Combat.new();var timeline := Timeline.new()
	var counts := [];counts.resize(23);counts.fill(1)
	check(combat.configure(bindings,catalogues,0.5),combat.error)
	check(timeline.configure(bindings,catalogues,library,counts),timeline.error)
	var scene: Dictionary = timeline.snapshot().scene
	var radio: Dictionary = timeline.snapshot().radio
	radio.finished[7]=true
	for actor in scene.actors:
		actor.position=Vector3.ZERO
		actor.erase("pose")
	check(combat.update(scene,3,radio),combat.error)
	check(combat.normal_hit(0,144).accepted,combat.error)
	check(combat._actors[1].set_permissions(true,false,true),"Cannot set independent immunity")
	owner.advance(1)
	var volley: Dictionary = owner.fire(Transform3D.IDENTITY,true)
	check(volley.weapons[0].slot==1 and volley.weapons[1].slot==0,"Firing order changed")
	var before: Dictionary = owner.snapshot();var before_combat: Dictionary = combat.snapshot()
	var result: Dictionary = owner.evaluate_npc_update(combat,[0,1,2],0)
	check(not result.is_empty(),owner.error)
	if result.is_empty():return
	check(result.weapons.size()==2 and result.weapons[0].slot==0 and result.weapons[1].slot==1,"NPC update reused reverse firing order")
	check(result.weapons[0].mount_id==volley.weapons[1].mount_id and result.weapons[1].mount_id==volley.weapons[0].mount_id,"Update changed logical gun identities")
	var pairs := [];var deaths := 0;var accepted := 0
	for event in result.weapons:
		for contact in event.contacts:
			pairs.append([event.slot,contact.actor_id])
			if contact.damage.destroyed_now:deaths+=1
			if contact.damage.accepted:accepted+=1
		check(event.motion.cleared.size()==1 and event.motion.moved.is_empty(),"Impact did not clear in the same zero-duration gun update")
	check(pairs==[[0,0],[0,1],[0,2],[1,1],[1,2]],"Damage from an earlier gun did not affect later target eligibility")
	check(deaths==1 and accepted==3 and result.combat.snapshot().actors[2].vitals.hull==138,"Sequential gun damage or immunity changed")
	check(owner.snapshot()==before and combat.snapshot()==before_combat,"Evaluation mutated original owners")
	for gun in result.primaries.snapshot().guns:
		check(gun.projectiles.slots[0]==null and gun.projectiles.elapsed_ms==0,"Zero-duration commit retained impacts or advanced time")
	var after: Dictionary = result.primaries.evaluate_npc_update(result.combat,[0,1,2],1)
	check(not after.is_empty(),result.primaries.error)
	for event in after.weapons:check(event.contacts.is_empty(),"Cleared shots damaged targets again")
	var empty: Dictionary = owner.evaluate_npc_update(combat,[],1)
	check(empty.combat.snapshot()==before_combat,"Empty target list invented damage")
	for event in empty.weapons:
		check(event.contacts.is_empty() and event.motion.moved.size()==1,"Empty target list suppressed independent motion")
	# The first gun hits and clears in staging before the later gun's time fails.
	var extreme: RefCounted = owner.fork_state()
	extreme._guns[0].projectiles._elapsed_ms=2147483647
	var extreme_before: Dictionary = extreme.snapshot()
	check(extreme.evaluate_npc_update(combat,[0,1,2],1).is_empty(),"Later gun time overflow accepted")
	check(extreme.snapshot()==extreme_before and combat.snapshot()==before_combat,"Later gun failure committed earlier damage or impact cleanup")
	var legacy: RefCounted = owner.fork_state()
	for gun in legacy._guns:gun.projectiles._weapon.erase("collision_bounds")
	check(legacy.evaluate_npc_update(combat,[0,1,2],0).is_empty(),"Legacy gun invented automatic bounds")
	check(not legacy.evaluate_npc_update(combat,[0,1,2],0,{"mode":"target"}).is_empty(),"Legacy explicit bounds failed")
	check(owner.snapshot()==before,"Forked weapon metadata aliases original primary owner")
	for delta in [null,true,-1,0.5,2147483648]:
		check(owner.evaluate_npc_update(combat,[0,1,2],delta).is_empty(),"Invalid primary update time accepted")
	for targets in [null,[3],[true],[0.0],["player"]]:
		check(owner.evaluate_npc_update(combat,targets,0).is_empty(),"Unsupported target accepted")
	var other: RefCounted = combat.fork_for_frame()
	other._identity.binding_id="f".repeat(64)
	check(owner.evaluate_npc_update(other,[],0).is_empty(),"Mismatched NPC content accepted")
	check(owner.evaluate_npc_update(null,[],0).is_empty(),"Missing NPC owner accepted")
	var unarmed := Primary.new();var loadout := opening.snapshot()
	loadout.slots.fill(null);loadout.equipment_ids=[]
	check(unarmed.configure(bindings,catalogues,mounts,loadout),unarmed.error)
	var no_guns: Dictionary = unarmed.evaluate_npc_update(combat,[0,1,2],0)
	check(not no_guns.is_empty() and no_guns.weapons.is_empty() and no_guns.combat.snapshot()==before_combat,"Unarmed owner invented contacts")
	check(unarmed.evaluate_npc_update(combat,[3],0).is_empty(),"Unarmed owner accepted an unknown target")
	check(owner.snapshot()==before and combat.snapshot()==before_combat,"Failed or detached operations changed inputs")
	print(library.manifest.profile.edition,": creation-order contacts, same-update cleanup, sequential damage and atomic multi-gun rollback verified")

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
