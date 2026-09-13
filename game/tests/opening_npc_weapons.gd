extends SceneTree
const Guns = preload("res://src/simulation/opening_npc_weapons.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Definitions = preload("res://src/content/opening_npc_weapon_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	var guns := Guns.new()
	check(not guns.configure(null,null),"Unconfigured NPC guns accepted content")
	check(guns.advance(1).is_empty() and guns.fire(null,[]).is_empty(),"Unconfigured NPC guns ran")
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("Opening NPC weapon checks: %d failures" % failures)
	quit(1 if failures else 0)

func active_group(bindings: RefCounted, catalogues: RefCounted) -> RefCounted:
	var combat := Combat.new()
	if not combat.configure(bindings,catalogues,0.5):
		check(false,combat.error)
		return combat
	var scene := combat.snapshot()
	for id in scene.actors.size():
		var pose := Transform3D(Basis(Vector3.UP,PI/2),Vector3(id*100,200,300))
		scene.actors[id].position=pose.origin
		scene.actors[id].pose=pose
	var finished := []
	finished.resize(bindings.opening_dialogue.events.size())
	finished.fill(false)
	finished[7]=true
	check(combat.update(scene,3,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":finished}),combat.error)
	return combat

func check_profile(content: String, bindings_path: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(bindings_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error)
		return
	var guns := Guns.new()
	var data: Dictionary = bindings.opening_actors.npc_initialization.get("primary_weapon",{})
	if data.is_empty():
		check(not guns.configure(bindings,catalogues) and guns.snapshot().is_empty(),"Legacy content invented NPC weapons")
		return
	if not guns.configure(bindings,catalogues):
		check(false,guns.error)
		return
	check(Definitions.parameters(data),"Imported NPC weapon parameters rejected")
	for key in data:
		var bad := data.duplicate(true)
		bad.erase(key)
		check(not Definitions.parameters(bad),"Missing NPC weapon field accepted: "+key)
	var state := guns.snapshot()
	check(state.actors.size()==3 and state.definition.damage==3 and state.definition.interval_ms==600 and state.definition.lifetime_ms==3000 and state.definition.speed_units_per_millisecond==16,"Source NPC parameters changed")
	for actor in state.actors:
		check(actor.projectiles.weapon.kind==1 and actor.projectiles.weapon.item_id==19 and actor.projectiles.slots.size()==4,"NPCs inherited the player's item or pool")
	var inactive := Combat.new()
	check(inactive.configure(bindings,catalogues,0.5),inactive.error)
	guns.advance(1)
	var result := guns.fire(inactive,[2,1,0])
	check(not result.is_empty(),guns.error)
	for actor in result.get("actors",[]): check(not actor.outcome.fired and actor.outcome.reason=="permission","Inactive enemy fired")
	var combat := active_group(bindings,catalogues)
	var before: Dictionary = combat.snapshot()
	result=guns.fire(combat,[2,0,1])
	check(result.get("actors",[]).size()==3,guns.error)
	for id in result.get("actors",[]).size():
		var actor: Dictionary = result.actors[id]
		check(actor.actor_id==id and actor.outcome.fired,"NPC fire did not follow actor order")
		if not actor.outcome.fired: continue
		var shot: Dictionary = actor.outcome.projectile
		check(shot.position==Vector3(id*100,200,300),"NPC muzzle acquired the player's Z offset")
		check(shot.velocity.is_equal_approx(Vector3(16,0,0)) and shot.remaining_ms==3000,"NPC forward launch differs from source coordinates")
	check(combat.snapshot()==before,"Firing changed combat actors or their damage")
	check(guns.advance(600).actors[0].update.moved[0].position.is_equal_approx(Vector3(9600,200,300)),"NPC millisecond movement changed")
	result=guns.fire(combat,[0])
	check(result.actors[0].outcome.reason=="interval","NPC fired at interval equality")
	guns.advance(1)
	check(guns.fire(combat,[0]).actors[0].outcome.fired,"NPC failed just beyond its interval")
	check(guns.snapshot().actors[1].projectiles.elapsed_ms==601,"One enemy reset another's firing timer")
	var saved := guns.snapshot()
	for ids in [[0,0],[-1],[3],[0.0],[true]]:
		check(guns.fire(combat,ids).is_empty() and guns.snapshot()==saved,"Invalid request partly fired an enemy")
	for delta in [-1,0.5,true]:
		check(guns.advance(delta).is_empty() and guns.snapshot()==saved,"Invalid NPC time mutated state")
	var invalid := active_group(bindings,catalogues)
	# A body now retains its constructor pose even without a scene pose override.
	# Corrupt the final actor explicitly to exercise late firing rollback.
	invalid._actors[2]._state.erase("pose")
	guns.advance(601)
	saved=guns.snapshot()
	check(guns.fire(invalid,[0,2]).is_empty() and guns.snapshot()==saved,"Late invalid pose partly committed NPC fire")
	var other := active_group(bindings,catalogues)
	other._identity.binding_id="f".repeat(64)
	check(guns.fire(other,[0]).is_empty() and guns.snapshot()==saved,"Cross-profile NPC fire accepted")
	var copy: RefCounted = guns.fork_for_frame()
	check(copy.advance(1).size()>0 and guns.snapshot()==saved,"NPC fork aliases original projectiles")
	combat.normal_hit(1,150)
	combat._actors[2].set_permissions(true,true,false)
	result=guns.fire(combat,[0,1,2])
	check(result.actors[0].outcome.fired and not result.actors[1].outcome.fired and not result.actors[2].outcome.fired,"Death or firing permission ignored")
	# Late overflow must preserve every prior actor's projectile update.
	guns._guns[2]._elapsed_ms=2147483647
	saved=guns.snapshot()
	check(guns.advance(1).is_empty() and guns.snapshot()==saved,"Late timer overflow partly advanced NPC weapons")
	check(guns.configure(bindings,catalogues),guns.error)
	combat=active_group(bindings,catalogues)
	guns.advance(1)
	check(guns.fire(combat,[0]).actors[0].outcome.fired,guns.error)
	result=guns.advance(3000)
	check(result.actors[0].update.expired.size()==1 and guns.snapshot().actors[0].projectiles.slots[0]!=null,"NPC expiry skipped the final movement")
	guns.advance(0)
	check(guns.snapshot().actors[0].projectiles.slots[0]==null,"NPC zero-time cleanup retained an expired slot")
	var original: Dictionary = bindings.opening_actors.npc_initialization.primary_weapon
	bindings.opening_actors.npc_initialization.primary_weapon={}
	check(not guns.configure(bindings,catalogues) and guns.snapshot().is_empty(),"Failed reconfiguration retained NPC guns")
	bindings.opening_actors.npc_initialization.primary_weapon=original
	print(library.manifest.profile.edition,": independent NPC pools, source poses, timing and rollback verified")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)
