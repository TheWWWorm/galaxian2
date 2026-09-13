extends SceneTree
const Pass = preload("res://src/simulation/ordinary_scenery_contacts.gd")
const Shots = preload("res://src/simulation/ordinary_projectiles.gd")
const Bodies = preload("res://src/simulation/scenery_bodies.gd")
const Resources = preload("res://src/content/scenery_body_resources.gd")
const Fixture = preload("res://tests/scenery_fixture.gd")
const Field = preload("res://src/simulation/scenery_field.gd")
const Generator = preload("res://src/simulation/seeded_random.gd")
const Resolver = preload("res://src/simulation/weapon_loadout.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/bindings/visual triples")
	for index in range(0,args.size()-2,3): check_profile(args[index],args[index+1])
	print("Ordinary scenery contacts: %d failures" % failures)
	quit(1 if failures else 0)

func check_synthetic() -> void:
	var operation := Pass.new()
	check(operation.evaluate(null,null,[]).is_empty(),"Missing contact owners accepted")
	var data := Fixture.make()
	var bindings: RefCounted = data[0]
	bindings.weapon_parameters={"ordinary_hit_policy":{"additional_damage_property":10,"missing_additional_damage":-1,"nonplayer_damage_scale":1.0,"provenance":{}}}
	var resources := Resources.new()
	# Deliberately synthetic radius and source declarations, not original assets.
	resources._state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"radii":{400:1000.0,500:1000.0,600:1000.0,700:1000.0}}
	var weapon := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"item_id":2,"category":0,"kind":0,"damage":6,"interval_ms":10,"lifetime_ms":50,
		"speed_units_per_millisecond":2.0,"launch_mode":"ordinary","projectile_capacity":2,
		"collision_bounds":{"mode":"target"},"ordinary_hit_policy":{"additional_damage_required":false,"additional_damage":-1,"nonplayer_damage":6}}
	var shots := launch(weapon,Vector3.ZERO)
	check(not shots.advance(11).is_empty(),shots.error)
	var position: Vector3 = shots.snapshot().slots[0].position
	check(shots.fire(position,Vector3.RIGHT,true).fired,shots.error)
	var field := make_field(bindings,[position,position,position])
	var bodies := Bodies.new()
	check(bodies.configure(bindings,field,resources),bodies.error)
	check(bodies.normal_hit(0,125).accepted,"Could not prepare a near-dead target")
	check(bodies.set_permissions(1,true,false),bodies.error)
	bodies._rows[0].motion_scalar=5.0
	bodies._rows[1].motion_scalar=7.0
	var before_bodies := bodies.snapshot()
	var before_shots: Dictionary = shots.snapshot()
	var result := operation.evaluate(shots,bodies,[0,1,2])
	check(not result.is_empty(),operation.error)
	if result.is_empty(): return
	check(result.contacts.size()==6,"Overlaps, immunity or mid-target death suppressed source contact marking")
	var order := [];var accepted := 0;var destroyed := 0
	for contact in result.contacts:
		order.append([contact.object_index,contact.slot])
		if contact.damage.accepted: accepted+=1
		if contact.damage.destroyed_now: destroyed+=1
	check(order==[[0,0],[0,1],[1,0],[1,1],[2,0],[2,1]],"Source target-outer/slot-inner order changed")
	check(accepted==3 and destroyed==1,"Damage denial or death idempotence changed")
	var after: Dictionary = result.bodies.snapshot()
	check(after.objects[2].vitals.hull==118,"Scenery did not receive full nonplayer damage")
	check(after.objects[0].destruction_pending and after.objects[0].active,"Contact pass completed unsupported destruction progression")
	check(after.objects[1].vitals.hull==130 and not after.objects[1].damaged and after.objects[1].hit_feedback==0.0,"Immune contact changed damage state")
	check(after.objects[0].motion_scalar==0.0 and after.objects[1].motion_scalar==0.0,"Scenery contact prelude was skipped on denied damage")
	check(result.last_contact_object_index==2,"Last contact did not preserve ordered target identity")
	for row in after.objects:
		check(row.contact and row.impact_vector==Vector3(-2,0,0),"Contact did not store the last slot's inverse velocity")
		var bits := PackedFloat32Array([row.impact_vector.y,row.impact_vector.z]).to_byte_array()
		check(bits.decode_u32(0)==0x80000000 and bits.decode_u32(4)==0x80000000,"Impact sign negation lost negative zero")
	for projectile in result.projectiles.snapshot().slots:
		check(projectile.remaining_ms==-1000000 and projectile.position==position,"Contact cleared or moved retained geometry")
	check(bodies.snapshot()==before_bodies and shots.snapshot()==before_shots,"Evaluation changed input owners before commit")
	var repeated := operation.evaluate(shots,bodies,[2,2])
	check(repeated.contacts.size()==4 and repeated.bodies.snapshot().objects[2].vitals.hull==106,"Duplicate targets were sorted or removed")
	check(operation.evaluate(shots,bodies,[0,0]).contacts.size()==2,"Duplicate target did not resample death after the first target pass")
	var inactive: RefCounted = bodies.fork_for_frame()
	check(inactive.set_permissions(2,false,true),inactive.error)
	check(operation.evaluate(shots,inactive,[2]).contacts.is_empty(),"Inactive scenery participated")
	inactive=bodies.fork_for_frame();inactive._rows[2].collision_enabled=false
	check(operation.evaluate(shots,inactive,[2]).contacts.is_empty(),"Geometry-disabled scenery participated")
	var empty := operation.evaluate(shots,bodies,[])
	check(empty.contacts.is_empty() and empty.last_contact_object_index==null,"Empty list invented a target or stale last contact")
	check(operation.evaluate(result.projectiles,result.bodies,[2]).contacts.size()==2,"Prior impact sentinel excluded retained geometry")
	check(not result.projectiles.advance(0).is_empty(),result.projectiles.error)
	check(operation.evaluate(result.projectiles,result.bodies,[2]).contacts.is_empty(),"Cleaned or unused slots produced phantom contacts")
	var expired: RefCounted = shots.fork_state()
	check(not expired.advance(51).is_empty(),expired.error)
	check(operation.evaluate(expired,bodies,[2]).contacts.size()==2,"Naturally expired retained slots were skipped")
	var single := launch(weapon,Vector3.ZERO)
	var face := Bodies.new()
	check(face.configure(bindings,make_field(bindings,[Vector3(700,0,-2)]),resources),face.error)
	check(operation.evaluate(single,face,[0]).contacts.is_empty(),"Exact open-cube face was treated as a contact")
	check(operation.evaluate(single,face,[0],{"mode":"fixed","half_extent":701}).contacts.size()==1,"Fixed weapon extent was ignored")
	check(operation.evaluate(single,face,[0],{"mode":"fixed","half_extent":0}).contacts.is_empty(),"Zero extent hit")
	var legacy_weapon := weapon.duplicate(true);legacy_weapon.erase("collision_bounds")
	var legacy := launch(legacy_weapon,Vector3.ZERO)
	check(operation.evaluate(legacy,bodies,[]).is_empty(),"Missing bounds were silently invented")
	check(not operation.evaluate(legacy,bodies,[],{"mode":"target"}).is_empty(),"Explicit legacy bounds were rejected")
	for bad in [null,[3],[true],[0.0],["0"],[0,999]]:
		check(operation.evaluate(shots,bodies,bad).is_empty(),"Invalid target list accepted")
	for bad in [{},{"mode":"target","extra":true},{"mode":"fixed"},{"mode":"fixed","half_extent":true},{"mode":"sphere","half_extent":1}]:
		check(operation.evaluate(shots,bodies,[2],bad).is_empty(),"Malformed bounds accepted")
	var foreign_weapon := weapon.duplicate(true);foreign_weapon.binding_id="c".repeat(64)
	check(operation.evaluate(launch(foreign_weapon,Vector3.ZERO),bodies,[2]).is_empty(),"Cross-binding weapon accepted")
	var unsupported_weapon := weapon.duplicate(true);unsupported_weapon.ordinary_hit_policy.additional_damage_required=true
	check(operation.evaluate(launch(unsupported_weapon,Vector3.ZERO),bodies,[2]).is_empty(),"Unsupported additional damage path accepted")
	var extreme := launch(weapon,Vector3(-3e38,0,0))
	var far := Bodies.new()
	check(far.configure(bindings,make_field(bindings,[Vector3(-3e38,0,0),Vector3(3e38,0,0)]),resources),far.error)
	var old_far := far.snapshot();var old_extreme: Dictionary = extreme.snapshot()
	check(operation.evaluate(extreme,far,[0,1]).is_empty(),"Overflowing late contact query succeeded")
	check(far.snapshot()==old_far and extreme.snapshot()==old_extreme,"Late failure committed earlier staged contacts")
	check(bodies.snapshot()==before_bodies and shots.snapshot()==before_shots,"Later queries aliased original owners")
	print("Synthetic scenery: ordered overlaps, denied damage, retained slots, strict bounds, identity and rollback verified")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var resources := Resources.new();var field_owner := Field.new();var bodies := Bodies.new();var resolver := Resolver.new()
	if not resources.configure(library,bindings) or not field_owner.configure(bindings,catalogues,78,false,false,0) or not resolver.configure(bindings,catalogues,catalogues.content_id):
		check(false,resources.error+field_owner.error+resolver.error);return
	var random := Generator.new();random.seed_from(12345)
	var field := field_owner.generate(Vector3.ZERO,random.snapshot())
	check(bodies.configure(bindings,field,resources),bodies.error)
	var weapon := resolver.resolve(2,[])
	var shots := launch(weapon,field.objects[0].position)
	var before := bodies.snapshot()
	var operation := Pass.new()
	var result := operation.evaluate(shots,bodies,[0])
	check(not result.is_empty(),operation.error)
	if result.is_empty(): return
	check(result.contacts.size()==1 and result.contacts[0].damage.accepted,"Source scenery contact did not apply ordinary weapon damage")
	check(result.bodies.snapshot().objects[0].vitals.hull==maxi(0,before.objects[0].vitals.hull-weapon.damage),"Source scenery hull accounting differs")
	check(result.projectiles.snapshot().slots[0].remaining_ms==-1000000,"Source scenery impact did not retain sentinel geometry")
	check(bodies.snapshot()==before,"Source scenery evaluator mutated its input")
	print(library.manifest.profile.edition,": authored field, model radius and ordinary weapon contact verified")

func launch(weapon: Dictionary, position: Vector3) -> RefCounted:
	var shots := Shots.new()
	check(shots.configure(weapon),shots.error)
	check(not shots.advance(1).is_empty(),shots.error)
	check(shots.fire(position,Vector3.BACK,true).get("fired",false),shots.error)
	return shots

func make_field(bindings: RefCounted, positions: Array) -> Dictionary:
	var field := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"objects":[]}
	for index in positions.size():
		field.objects.append({"index":index,"item_id":0,"model_variant":0,"model_id":400,
			"source_size_value":7,"large":true,"position":positions[index],"scale":1.0})
	return field

func check(condition: bool, message: String) -> void:
	if not condition: failures+=1;push_error(message)
