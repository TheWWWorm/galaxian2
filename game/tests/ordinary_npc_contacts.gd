extends SceneTree
const Pass = preload("res://src/simulation/ordinary_npc_contacts.gd")
const Shots = preload("res://src/simulation/ordinary_projectiles.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Resolver = preload("res://src/simulation/weapon_loadout.gd")
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	var operation := Pass.new()
	check(operation.evaluate(null,null,[],{"mode":"target"}).is_empty(),"Missing owners accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):check_profile(args[i],args[i+1])
	print("Ordinary NPC contacts: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String,pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library) or not library.select_language("gb"):
		check(false,library.error+bindings.error+catalogues.error);return
	var resolver := Resolver.new();var group := Combat.new();var timeline := Timeline.new()
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	check(group.configure(bindings,catalogues,0.5),group.error)
	var counts := [];counts.resize(23);counts.fill(1)
	check(timeline.configure(bindings,catalogues,library,counts),timeline.error)
	var scene: Dictionary = timeline.snapshot().scene
	var radio: Dictionary = timeline.snapshot().radio
	radio.finished[7]=true
	var weapon: Dictionary = resolver.resolve(2,[])
	var shots := Shots.new()
	check(shots.configure(weapon),shots.error)
	check(not shots.advance(1).is_empty(),shots.error)
	check(shots.fire(Vector3.ZERO,Vector3.BACK,true).fired,shots.error)
	check(not shots.advance(381).is_empty(),shots.error)
	var position: Vector3 = shots.snapshot().slots[0].position
	check(shots.fire(position,Vector3.BACK,true).fired,shots.error)
	for actor in scene.actors:
		actor.position=position
		actor.erase("pose")
	check(group.update(scene,3,radio),group.error)
	check(group.normal_hit(0,144).accepted,group.error)
	check(group._actors[1].set_permissions(true,false,true),"Cannot set independent immunity")
	var before_group: Dictionary = group.snapshot()
	var before_shots: Dictionary = shots.snapshot()
	var operation := Pass.new()
	var result: Dictionary = operation.evaluate(shots,group,[0,1,2],{"mode":"target"})
	check(not result.is_empty(),operation.error)
	if result.is_empty():return
	if weapon.has("collision_bounds"):
		var automatic: Dictionary = operation.evaluate(shots,group,[0,1,2])
		check(not automatic.is_empty() and automatic.contacts==result.contacts,"Source bounds default changed contacts")
		check(automatic.combat.snapshot()==result.combat.snapshot(),"Source bounds default changed damage")
		var detached: Dictionary = shots.snapshot()
		detached.weapon.collision_bounds.mode="fixed"
		check(shots.fork_state().snapshot().weapon.collision_bounds=={"mode":"target"},"Bounds metadata aliases a snapshot")
	else:
		check(operation.evaluate(shots,group,[0,1,2]).is_empty(),"Legacy weapon invented automatic bounds")
	var legacy := Shots.new()
	var legacy_weapon := weapon.duplicate(true)
	legacy_weapon.erase("collision_bounds")
	check(legacy.configure(legacy_weapon),legacy.error)
	check(operation.evaluate(legacy,group,[]).is_empty(),"Missing source bounds invented a default")
	check(not operation.evaluate(legacy,group,[],{"mode":"target"}).is_empty(),"Legacy explicit bounds rejected")
	for bad_bounds in [null,{}, {"mode":"fixed","half_extent":1000},{"mode":"target","extra":true}]:
		var bad_weapon := weapon.duplicate(true)
		bad_weapon.collision_bounds=bad_bounds
		check(not legacy.configure(bad_weapon) and legacy.snapshot().is_empty(),"Malformed source bounds accepted or retained state")
	check(result.contacts.size()==6,"Contact pass failed to retain shots across overlapping targets or target death")
	var order := [];var deaths := 0;var accepted := 0
	for contact in result.contacts:
		order.append([contact.actor_id,contact.slot])
		if contact.damage.destroyed_now:deaths+=1
		if contact.damage.accepted:accepted+=1
	check(order==[[0,0],[0,1],[1,0],[1,1],[2,0],[2,1]],"Target-outer/slot-inner source order changed")
	check(deaths==1 and accepted==3,"Death or immunity incorrectly suppressed marking or accepted repeated damage")
	check(result.combat.snapshot().actors[2].vitals.hull==138,"Repeated overlapping contact lost damage")
	check(result.last_contact_actor_id==2,"NPC pass lost its last source target")
	for actor in result.combat.snapshot().actors:
		check(actor.contact and actor.impact_vector==Vector3(0,0,-20),"Denied or accepted hit lost unnormalized inverse-velocity metadata")
		var bits := PackedFloat32Array([actor.impact_vector.x,actor.impact_vector.y]).to_byte_array()
		check(bits.decode_u32(0)==0x80000000 and bits.decode_u32(4)==0x80000000,"NPC contact lost sign-negated zero")
	var differently_aimed := Shots.new()
	check(differently_aimed.configure(weapon),differently_aimed.error)
	differently_aimed.advance(1)
	check(differently_aimed.fire(Vector3.ZERO,Vector3.BACK,true).fired,differently_aimed.error)
	differently_aimed.advance(381)
	check(differently_aimed.fire(position,Vector3.RIGHT,true).fired,differently_aimed.error)
	var last_slot: Dictionary = operation.evaluate(differently_aimed,group,[0,1,2],{"mode":"target"})
	check(not last_slot.is_empty() and last_slot.contacts.size()==6,"Differently aimed overlapping slots lost contacts")
	if not last_slot.is_empty():
		for actor in last_slot.combat.snapshot().actors:
			check(actor.impact_vector==Vector3(-20,0,0),"Last slot did not replace impact direction after damage denial or death")
	check(group.snapshot()==before_group and shots.snapshot()==before_shots,"Contact evaluation changed original owners before commit")
	for projectile in result.projectiles.snapshot().slots:
		if projectile!=null:
			check(projectile.remaining_ms==-1000000 and projectile.position==position,"Impact did not defer cleanup or moved geometry")
	check(not result.projectiles.advance(0).is_empty() and result.projectiles.snapshot().slots[0]==null,"Zero-time update failed to clean marked projectile")
	check(not result.projectiles.advance(1).is_empty() and result.projectiles.snapshot().slots[0]==null,"Positive update recreated a cleared projectile")
	var empty: Dictionary = operation.evaluate(result.projectiles,result.combat,[0,1,2],{"mode":"target"})
	check(not empty.is_empty() and empty.contacts.is_empty(),"Cleaned or never-launched slots produced phantom hits")
	check(empty.last_contact_actor_id==null,"No-hit pass retained a stale last target")
	var repeated: Dictionary = operation.evaluate(shots,group,[2,2],{"mode":"target"})
	check(repeated.contacts.size()==4 and repeated.combat.snapshot().actors[2].vitals.hull==126,"Source target-list duplicates were removed or reordered")
	check(repeated.last_contact_actor_id==2,"Duplicate target pass lost last target")
	var reversed: Dictionary = operation.evaluate(shots,group,[2,1],{"mode":"target"})
	check(reversed.last_contact_actor_id==1,"Last contact was sorted or required accepted damage")
	var inactive: RefCounted = group.fork_for_frame()
	check(inactive._actors[2].set_permissions(false,true,true),"Cannot deactivate target")
	check(operation.evaluate(shots,inactive,[2],{"mode":"target"}).contacts.is_empty(),"Inactive target participated")
	var no_targets: Dictionary = operation.evaluate(shots,result.combat,[],{"mode":"target"})
	check(no_targets.contacts.is_empty() and no_targets.last_contact_actor_id==null,"Empty explicit list invented or retained a last target")
	check(no_targets.combat.snapshot()==result.combat.snapshot(),"Empty target pass reset actor-owned contact state")
	# Even a pass with no contacts must return independently mutable owners.
	var no_hit_source: RefCounted=group.fork_for_frame()
	var no_hit: Dictionary=operation.evaluate(shots,no_hit_source,[],{"mode":"target"})
	var no_hit_before: Dictionary=no_hit.combat.snapshot()
	check(no_hit_source.set_pose(2,Transform3D(Basis.IDENTITY,Vector3(100,200,300))),no_hit_source.error)
	check(no_hit.combat.snapshot()==no_hit_before,"No-hit result aliases later input mutations")
	var source_before: Dictionary=no_hit_source.snapshot()
	check(no_hit.combat.normal_hit(2,1).accepted,no_hit.combat.error)
	check(no_hit.combat.record_contact(2,Vector3.ONE),no_hit.combat.error)
	check(no_hit_source.snapshot()==source_before,"No-hit result leaked damage or contact metadata to its input")
	check(no_hit.projectiles.mark_impact(1),no_hit.projectiles.error)
	check(shots.snapshot()==before_shots,"No-hit result aliases the original projectile pool")
	for bad in [null,[3],[true],[0.0],["player"]]:
		check(operation.evaluate(shots,group,bad,{"mode":"target"}).is_empty(),"Invalid or unsupported target accepted")
	for bad in [{}, {"mode":"target","half_extent":1},{"mode":"fixed"},{"mode":"fixed","half_extent":true},{"mode":"sphere","half_extent":1}]:
		check(operation.evaluate(shots,group,[0,2],bad).is_empty(),"Unknown bounds selection accepted")
	var face: RefCounted = group.fork_for_frame()
	var face_scene := scene.duplicate(true)
	face_scene.actors[2].position=position+Vector3(1000,0,-20)
	check(face.update(face_scene,3,radio),face.error)
	check(operation.evaluate(shots,face,[2],{"mode":"target"}).contacts.is_empty(),"Exact open-cube face hit")
	if weapon.has("collision_bounds"): check(operation.evaluate(shots,face,[2]).contacts.is_empty(),"Automatic bounds ignored the target extent")
	check(operation.evaluate(shots,face,[2],{"mode":"fixed","half_extent":1001}).contacts.size()==2,"Explicit weapon extent was ignored")
	check(operation.evaluate(shots,face,[2],{"mode":"fixed","half_extent":0}).contacts.is_empty(),"Zero extent hit")
	var expired: RefCounted = shots.fork_state()
	check(not expired.advance(2000).is_empty(),expired.error)
	var expired_group: RefCounted = group.fork_for_frame()
	var expired_scene := scene.duplicate(true)
	expired_scene.actors[2].position=expired.snapshot().slots[0].position
	check(expired_group.update(expired_scene,3,radio),expired_group.error)
	check(operation.evaluate(expired,expired_group,[2],{"mode":"target"}).contacts.size()==2,"Naturally expired retained shots were incorrectly excluded")
	# A late geometry failure must discard earlier staged damage and impact marks.
	var extreme := Shots.new()
	check(extreme.configure(weapon),extreme.error)
	extreme.advance(1)
	check(extreme.fire(Vector3(-3e38,0,0),Vector3.BACK,true).fired,extreme.error)
	var extreme_group: RefCounted = group.fork_for_frame()
	var extreme_scene := scene.duplicate(true)
	extreme_scene.actors[0].position=Vector3(-3e38,0,0)
	extreme_scene.actors[2].position=Vector3(3e38,0,0)
	check(extreme_group.update(extreme_scene,3,radio),extreme_group.error)
	var old_group: Dictionary = extreme_group.snapshot();var old_shots: Dictionary = extreme.snapshot()
	check(operation.evaluate(extreme,extreme_group,[0,2],{"mode":"target"}).is_empty(),"Overflowing contact arithmetic accepted")
	check(extreme_group.snapshot()==old_group and extreme.snapshot()==old_shots,"Late failure committed partial hit state")
	check(group.snapshot()==before_group and shots.snapshot()==before_shots,"Read-only evaluations damaged running owners")
	print(library.manifest.profile.edition,": ordered contacts, overlaps, death/immunity, expiry, explicit bounds and atomic rollback verified")

func check(condition: bool,message: String) -> void:
	if not condition:failures+=1;push_error(message)
