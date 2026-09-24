extends SceneTree
## Source-derived opening components and the existing explicit second-trip
## component fixture. This check does not grant or replay campaign progress.
const NpcControl=preload("res://src/simulation/opening_npc_control.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const Constructor=preload("res://src/simulation/opening_npc_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const FullHoldFixture=preload("res://tests/full_hold_control.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected one identified content/binding/visual triple")
	if args.size()==3:verify(args)
	print("NPC control observation: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var resources:=Resources.new();var constructor:=Constructor.new()
	if not resources.configure(library,bindings) or not constructor.configure(bindings,cat):check(false,resources.error+constructor.error);return
	var construction:=constructor.generate({"state":280936762154123})
	if construction.is_empty():check(false,constructor.error);return
	verify_opening(bindings,cat,resources,constructor,construction)
	verify_full_hold(library,bindings,cat)

func verify_opening(bindings: RefCounted,cat: RefCounted,resources: RefCounted,constructor: RefCounted,construction: Dictionary) -> void:
	var source:=NpcControl.new();var combat:=Combat.new();var weapons:=Weapons.new()
	if not source.configure(bindings,cat,.5) or not combat.configure(bindings,cat,.5) or not weapons.configure(bindings,cat):check(false,source.error+combat.error+weapons.error);return
	var branch: RefCounted=source.fork_for_frame();var nested: RefCounted=branch.fork_for_frame()
	var original: Dictionary=source.snapshot()
	check(branch.snapshot()==original and nested.snapshot()==original,"Retained fork changed controller observations")
	check(branch.set_initial_route(0,constructor.route(0)),branch.error)
	check(source.snapshot()==original and nested.snapshot()==original,"Fork route setup mutated its parent or sibling")
	var branched: Dictionary=branch.snapshot()
	check(source.set_initial_route(1,constructor.route(1)),source.error)
	check(branch.snapshot()==branched and nested.snapshot()==original,"Parent route setup mutated a retained child")
	for id in 3:
		for owner in [source,branch,nested]:
			if owner.snapshot().actors[id].guidance.route.is_empty():check(owner.set_initial_route(id,constructor.route(id)),owner.error)
	check(source.snapshot()==branch.snapshot() and source.snapshot()==nested.snapshot(),"Independent route setup changed ordered observations")
	original=source.snapshot()
	var bad:=construction.duplicate(true);bad.actors[-1].cargo=[{"item_id":1,"quantity":1}]
	check(not branch.set_initial_destruction(resources,bad) and branch.snapshot()==original and source.snapshot()==original,"Late constructor failure partly changed a retained fork")
	check(branch.set_initial_destruction(resources,construction),branch.error)
	check(source.snapshot()==original and nested.snapshot()==original,"Fork destruction setup mutated its parent or sibling")
	branched=branch.snapshot()
	check(source.set_initial_destruction(resources,construction) and nested.set_initial_destruction(resources,construction),source.error+nested.error)
	check(branch.snapshot()==branched and source.snapshot()==branched,"Parent destruction setup changed a retained fork")
	var detached: RefCounted=branch.destruction_owner(0)
	check(detached.capture(Transform3D(Basis.IDENTITY,Vector3(10,20,30)),2),detached.error)
	check(source.snapshot()==branched and branch.snapshot()==branched and nested.snapshot()==branched,"Detached destruction accessor aliases a retained controller")
	var editable: Dictionary=branch.snapshot()
	editable.actors[0].guidance.route.waypoints.clear();editable.actors[1].destruction.fragments.clear();editable.death_accounting.events.append({"invalid":true})
	check(source.snapshot()==branched and branch.snapshot()==branched,"Public snapshot exposes shared route, death or accounting state")
	var player:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"pose":Transform3D(Basis.IDENTITY,Vector3(0,0,10000)),"active":true,"hull":9999999,"special_flight":false,"targeting_blocked":true}
	for id in 3:check(combat.set_pose(id,Transform3D(Basis.IDENTITY,Vector3(0,0,-1000*id))),combat.error)
	var flags:=[];flags.resize(bindings.opening_dialogue.events.size());flags.fill(false);flags[7]=true
	check(combat.update(combat.snapshot(),3,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":flags}),combat.error)
	var seed:={"state":25214903917}
	var first:=source.evaluate(combat,weapons,150,player,seed)
	var second: Dictionary=branch.evaluate(combat,weapons,150,player,seed)
	if first.is_empty() or second.is_empty():check(false,source.error+branch.error);return
	check(operation(first)==operation(second),"Fork evaluation changed ordered events, RNG or float32 movement")
	check(source.snapshot()==branched and branch.snapshot()==branched and nested.snapshot()==branched,"Evaluation mutated retained parent/fork observations")
	var retained: RefCounted=first.controller.fork_for_frame()
	var before: Dictionary=retained.snapshot();var bodies: Dictionary=first.combat.snapshot();var guns: Dictionary=first.weapons.snapshot()
	var broken: RefCounted=first.combat.fork_for_frame();broken._actors[-1]._state.pose.origin.x=INF
	check(retained.evaluate(broken,first.weapons,150,player,first.random_state).is_empty(),"Invalid final actor was accepted")
	check(retained.snapshot()==before and first.controller.snapshot()==before and first.combat.snapshot()==bodies and first.weapons.snapshot()==guns,"Late failure retained earlier staged clocks or movement")
	var living: Dictionary=retained.evaluate(first.combat,first.weapons,150,player,first.random_state)
	check(not living.is_empty() and retained.snapshot()==before and first.controller.snapshot()==before,"Successful retry changed a retained fork")
	var lethal: RefCounted=first.combat.fork_for_frame()
	for id in 3:check(lethal.normal_hit(id,150,id==1).destroyed_now,"Synthetic lethal fixture did not exhaust the original hull")
	var died: Dictionary=retained.evaluate(lethal,first.weapons,150,player,first.random_state)
	if died.is_empty():check(false,retained.error);return
	check(retained.snapshot()==before and first.controller.snapshot()==before,"Fork death/accounting changed retained living state")
	check(died.controller.snapshot().death_accounting.events.size()==3 and died.actors.size()==3,"Ordered death accounting was lost")
	var dead: Dictionary=died.controller.snapshot();var child: RefCounted=died.controller.fork_for_frame()
	died.controller.clear()
	check(child.snapshot()==dead and died.controller.snapshot().is_empty(),"Parent clear modified a retained child")
	check(died.controller.configure(bindings,cat,.5) and child.snapshot()==dead,"Parent reconfiguration modified a retained child")
	child.clear()
	check(not died.controller.snapshot().is_empty() and child.snapshot().is_empty(),"Child clear modified its parent")

func verify_full_hold(library: RefCounted,bindings: RefCounted,cat: RefCounted) -> void:
	var fixture:=FullHoldFixture.new();var construction:=Construction.new();var resources:=Resources.new()
	if not construction.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100000) or not resources.configure_full_hold(library,bindings):check(false,construction.error+resources.error);fixture.free();return
	var control:=NpcControl.new();var combat:=Combat.new();var weapons:=Weapons.new()
	if not control.configure_full_hold(bindings,cat,construction,.5) or not combat.configure_full_hold(bindings,cat,construction,.5) or not weapons.configure_full_hold(bindings,cat,construction):check(false,control.error+combat.error+weapons.error);fixture.free();return
	var branch: RefCounted=control.fork_for_frame();var before: Dictionary=control.snapshot()
	check(branch.set_full_hold_destruction(resources) and control.snapshot()==before,"Fork full-hold preparation changed its parent")
	var prepared: Dictionary=branch.snapshot()
	check(control.set_full_hold_destruction(resources) and branch.snapshot()==prepared,"Parent full-hold preparation changed its fork")
	var player: Dictionary=fixture.target(bindings,Vector3(123.25,-88.5,910))
	var placed: Dictionary=branch.apply_full_hold_appearance(combat,5,player)
	if placed.is_empty():check(false,branch.error);fixture.free();return
	check(control.snapshot()==prepared and branch.snapshot()==prepared,"Appearance moved a retained parent or fork")
	var changed: Dictionary=placed.controller.snapshot()
	player.pose.origin.x+=1000
	var other:=control.apply_full_hold_appearance(combat,5,player)
	check(not other.is_empty() and placed.controller.snapshot()==changed and control.snapshot()==prepared,"Parent appearance moved the earlier returned fork")
	var nested: RefCounted=placed.controller.fork_for_frame()
	check(nested.evaluate(placed.combat,weapons,150,player,{"state":-1}).is_empty() and nested.snapshot()==changed and placed.controller.snapshot()==changed,"Failed appearance update consumed pending state")
	var stepped: Dictionary=nested.evaluate(placed.combat,weapons,0,player,construction.snapshot().random_state)
	check(not stepped.is_empty() and not stepped.controller.snapshot().appearance.pending and nested.snapshot()==changed and placed.controller.snapshot()==changed,"Appearance update changed retained pending state")
	fixture.free()

func operation(value: Dictionary) -> Dictionary:
	return {"controller":value.controller.snapshot(),"combat":value.combat.snapshot(),"weapons":value.weapons.snapshot(),"random_state":value.random_state,"actors":value.actors}

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
