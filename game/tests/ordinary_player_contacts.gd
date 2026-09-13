extends SceneTree
const Player = preload("res://src/simulation/opening_player_state.gd")
const Damage = preload("res://src/simulation/ordinary_player_damage.gd")
const Contacts = preload("res://src/simulation/ordinary_player_contacts.gd")
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Guns = preload("res://src/simulation/opening_npc_weapons.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Definitions = preload("res://src/content/player_hit_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	check_damage()
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3): check_profile(args[index],args[index+1])
	print("Ordinary player contact checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_damage() -> void:
	var policy := {"nonhostile_scale":0.20000000298023224,"special_flight_multipliers":[3.0,0.25],"rounding":"binary32_then_truncate","nonhostile_precedes_special":true,"provenance":{}}
	var resolver := Damage.new()
	for row in [[3,true,true,false,3,"ordinary"],[3,false,false,false,3,"ordinary"],
		[3,true,false,false,0,"nonhostile"],[3,true,false,true,0,"nonhostile"],
		[3,true,true,true,2,"special_flight"],[3,false,false,true,2,"special_flight"],
		[5,true,false,false,1,"nonhostile"],[16777219,true,false,false,3355444,"nonhostile"],
		[16777219,true,true,true,12582915,"special_flight"],[2147483647,true,true,false,2147483647,"ordinary"]]:
		var result := resolver.resolve(row[0],policy,row[1],row[2],row[3])
		check(result.get("amount")==row[4] and result.get("branch")==row[5],"Player scaling or branch precedence changed: "+str(row))
	for amount in [-1,0.5,true,2147483648]: check(resolver.resolve(amount,policy,true,true,false).is_empty(),"Invalid damage accepted")
	check(resolver.resolve(3,policy,1,true,false).is_empty(),"Implicit shooter presence accepted")
	var bad := policy.duplicate(true);bad.special_flight_multipliers=[0.75]
	check(resolver.resolve(3,bad,true,true,true).is_empty(),"Special flight skipped source multiplication order")

func gun(weapon: Dictionary, position: Vector3) -> RefCounted:
	var result := Projectiles.new()
	check(result.configure(weapon),result.error)
	result.advance(1)
	check(result.fire(position,Vector3.BACK,true).get("fired",false),result.error)
	return result

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var player := Player.new();var weapons := Guns.new()
	if not player.configure(bindings,catalogues) or not weapons.configure(bindings,catalogues): check(false,player.error+weapons.error);return
	var weapon: Dictionary=weapons.snapshot().actors[0].projectiles.weapon
	var operation := Contacts.new()
	if bindings.weapon_parameters.get("player_hit_policy",{}).is_empty():
		check(operation.evaluate(gun(weapon,Vector3.ZERO),player,Transform3D.IDENTITY,true,true,false).is_empty(),"Legacy player invented a hit policy")
		return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var policy: Dictionary=bindings.weapon_parameters.player_hit_policy
	check(Definitions.validate(policy,header.source_executable_bytes,header.architecture,bindings.weapon_parameters).is_empty(),"Source hit provenance rejected")
	var invalid := policy.duplicate(true);invalid.provenance.damage_route.offset+=2
	check(not Definitions.validate(invalid,header.source_executable_bytes,header.architecture,bindings.weapon_parameters).is_empty(),"Foreign collision route accepted")
	var shot: RefCounted=gun(weapon,Vector3.ZERO)
	var before := {"player":player.snapshot(),"shots":shot.snapshot()}
	var contact := operation.evaluate(shot,player,Transform3D.IDENTITY,true,true,false)
	if contact.is_empty():check(false,operation.error);return
	check(contact.contacts.size()==1 and contact.player.snapshot().vitals.shield==217.0,"Opening gun did not damage the source player shield")
	check(contact.contacts[0].damage.resolution.amount==3 and contact.last_contact_actor==null,"NPC damage or null player actor link changed")
	check(contact.player.snapshot().contact and contact.player.snapshot().impact_vector==Vector3(0,0,-16),"Player impact metadata changed")
	check(contact.projectiles.snapshot().slots[0].remaining_ms==Projectiles.HIT_LIFETIME_SENTINEL,"Player contact immediately retired geometry")
	check(player.snapshot()==before.player and shot.snapshot()==before.shots,"Contact pass mutated an input owner")
	contact.projectiles.advance(0)
	check(contact.projectiles.snapshot().slots[0]==null,"Zero-time cleanup retained player impact")
	player.set_permissions(true,false)
	contact=operation.evaluate(shot,player,Transform3D.IDENTITY,true,true,false)
	check(contact.contacts.size()==1 and not contact.contacts[0].damage.accepted and contact.player.snapshot().contact and contact.player.snapshot().vitals.shield==220.0,"Damage denial suppressed geometric contact metadata")
	player.set_permissions(false,true)
	contact=operation.evaluate(shot,player,Transform3D.IDENTITY,true,true,false)
	check(contact.contacts.is_empty() and not contact.player.snapshot().contact,"Inactive player accepted contact")
	player.set_permissions(true,true)
	for x in [1200.0,1199.0]:
		contact=operation.evaluate(gun(weapon,Vector3(x,0,16)),player,Transform3D.IDENTITY,true,true,false)
		check(contact.contacts.size()==(0 if x==1200.0 else 1),"Player contact bounds lost strict boundary behavior")
	var expired: RefCounted=gun(weapon,Vector3(0,0,-48000))
	expired.advance(3000)
	contact=operation.evaluate(expired,player,Transform3D.IDENTITY,true,true,false)
	check(contact.contacts.size()==1,"Retained expired projectile was skipped before cleanup")
	var saved_player := player.snapshot();var saved_shots: Dictionary=shot.snapshot()
	check(operation.evaluate(shot,player,Transform3D.IDENTITY,true,1,false).is_empty(),"Invalid shooter state accepted")
	check(operation.evaluate(shot,player,Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),true,true,false).is_empty(),"Invalid player pose accepted")
	check(player.snapshot()==saved_player and shot.snapshot()==saved_shots,"Rejected query mutated owners")
	check_death(bindings,catalogues,weapon)
	check_group(bindings,catalogues)
	print(library.manifest.profile.edition,": scaling, ordered contacts, source pools, cleanup and rollback verified")

func check_death(bindings: RefCounted, catalogues: RefCounted, weapon: Dictionary) -> void:
	var saved_hull: Variant=bindings.opening_actors.player_current_hull_override
	var shield: Variant=catalogues.tables.items[54].properties[18]
	var armor: Variant=catalogues.tables.items[59].properties[20]
	bindings.opening_actors.player_current_hull_override=1
	catalogues.tables.items[54].properties[18]=0;catalogues.tables.items[59].properties[20]=0
	var player := Player.new();check(player.configure(bindings,catalogues),player.error)
	bindings.opening_actors.player_current_hull_override=saved_hull
	catalogues.tables.items[54].properties[18]=shield;catalogues.tables.items[59].properties[20]=armor
	var shot: RefCounted=gun(weapon,Vector3(0,0,-9616))
	shot.advance(601);check(shot.fire(Vector3.ZERO,Vector3.BACK,true).fired,shot.error)
	var operation := Contacts.new();var result := operation.evaluate(shot,player,Transform3D.IDENTITY,true,true,false)
	check(result.contacts.size()==2 and result.contacts[0].damage.destroyed_now and not result.contacts[1].damage.accepted,"Early death changed the current target's slot eligibility")
	check(result.player.snapshot().vitals.hull==0,"Player hull was not clamped at zero")
	var next := operation.evaluate(result.projectiles,result.player,Transform3D.IDENTITY,true,true,false)
	check(next.contacts.is_empty(),"Already dead player entered a new target pass")

func check_group(bindings: RefCounted, catalogues: RefCounted) -> void:
	var player := Player.new();var weapons := Guns.new();var combat := Combat.new()
	check(player.configure(bindings,catalogues),player.error)
	check(weapons.configure(bindings,catalogues),weapons.error)
	check(combat.configure(bindings,catalogues,0.5),combat.error)
	for id in 3:
		combat._actors[id].set_permissions(true,true,true)
		combat._actors[id].set_pose(Transform3D(Basis(Vector3.UP,PI),Vector3(0,0,2000)))
	weapons.advance(1);weapons.fire(combat,[0,1,2])
	var contexts := [{"present":true,"hostile":true},{"present":true,"hostile":true},{"present":true,"hostile":true}]
	var original := {"player":player.snapshot(),"weapons":weapons.snapshot()}
	var result := weapons.evaluate_player_update(player,Transform3D.IDENTITY,contexts,false,100)
	if result.is_empty():check(false,weapons.error);return
	check(result.player.snapshot().vitals.shield==220.0,"Group moved projectiles before checking contacts")
	check(player.snapshot()==original.player and weapons.snapshot()==original.weapons,"Group update mutated its inputs")
	var next: Dictionary=result.weapons.evaluate_player_update(result.player,Transform3D.IDENTITY,contexts,false,0)
	if next.is_empty():check(false,result.weapons.error);return
	check(next.player.snapshot().vitals.shield==211.0,"Shared player damage was not retained across guns")
	for id in 3:
		check(next.actors[id].actor_id==id and next.actors[id].contacts.size()==1,"NPC contact order changed")
		check(next.actors[id].contacts[0].damage.after.shield==217.0-id*3.0,"Later gun missed preceding player damage")
		check(next.weapons.snapshot().actors[id].projectiles.slots[0]==null,"Per-gun cleanup was delayed beyond its target pass")
	result.weapons._guns[2]._elapsed_ms=2147483647
	var saved := {"player":result.player.snapshot(),"weapons":result.weapons.snapshot()}
	check(result.weapons.evaluate_player_update(result.player,Transform3D.IDENTITY,contexts,false,1).is_empty(),"Late gun overflow was accepted")
	check(result.player.snapshot()==saved.player and result.weapons.snapshot()==saved.weapons,"Late failure committed earlier contact damage or cleanup")
	check(result.weapons.evaluate_player_update(result.player,Transform3D.IDENTITY,contexts.slice(0,2),false,0).is_empty(),"Incomplete shooter state accepted")
	var copy: RefCounted=player.fork_for_frame();copy.set_permissions(false,false)
	check(player.snapshot()==original.player,"Player fork aliases lifecycle permissions")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)
