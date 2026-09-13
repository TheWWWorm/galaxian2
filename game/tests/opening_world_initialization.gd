extends SceneTree
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const World = preload("res://src/simulation/opening_world_initialization.gd")
const Scenery = preload("res://src/simulation/opening_scenery.gd")
const Definitions = preload("res://src/content/opening_world_initialization_definitions.gd")
const NpcControl = preload("res://src/simulation/opening_npc_control.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): verify_source(args[i],args[i+1])
	print("Opening world initialization checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	check(library.open(content),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(catalogues.open(library),catalogues.error)
	if not bindings.error.is_empty(): return
	var world := World.new()
	var definition: Dictionary=bindings.opening_actors.npc_initialization.get("world_initialization",{})
	if definition.is_empty():
		check(not world.configure(bindings,catalogues) and world.snapshot().is_empty(),"Legacy pack fabricated world initialization")
		return
	check(Definitions.parameters(definition),"Valid world parameters rejected")
	var bad := definition.duplicate(true);bad.weapon_effect_capacity=5
	check(not Definitions.parameters(bad),"Unsupported weapon capacity accepted")
	bad=definition.duplicate(true);bad.initial_companions_empty=1
	check(not Definitions.parameters(bad),"Numeric companion flag accepted")
	bad=definition.duplicate(true);bad.provenance.effect_model_0=bad.provenance.effect_model_19.duplicate()
	check(not Definitions.validate(bad,2147483647,"armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64").is_empty(),"Overlapping world provenance accepted")
	check(world.configure(bindings,catalogues),world.error)
	check(world.generate({"state":-1}).is_empty() and world.snapshot().is_empty(),"Invalid RNG partially initialized the world")
	var result := world.generate({"state":25214903917})
	check(not result.is_empty(),world.error)
	if result.is_empty(): return
	verify_effects(result,FIXTURES[0])
	var saved := world.snapshot()
	check(world.generate({"state":0}).is_empty() and world.snapshot()==saved,"World initialization ran twice")
	result.weapon_effects[0].primary.flipped.clear();result.npc_construction.actors.clear();result.random_state.state=0
	check(world.snapshot()==saved,"Initialization snapshot aliases owned state")
	check(world.route(-1)==null and world.route(3)==null,"Invalid initialization route accepted")
	var scene := Scenery.new()
	check(scene.configure(bindings,catalogues,1789100000),scene.error)
	var field := scene.snapshot()
	var identity: String=bindings.binding_id;bindings.binding_id="0".repeat(64)
	check(not scene.complete_world_initialization(bindings,catalogues) and scene.snapshot()==field,"Mismatched bindings advanced the field RNG")
	bindings.binding_id=identity
	var items: Array=catalogues.tables.items.duplicate(true)
	catalogues.tables.items[54].arrays[2][5]=33
	check(not scene.complete_world_initialization(bindings,catalogues) and scene.snapshot()==field,"Optional population was incorrectly skipped")
	catalogues.tables.items=items
	var independent: RefCounted=scene.fork_for_frame()
	check(independent.complete_world_initialization(bindings,catalogues),independent.error)
	check(scene.snapshot()==field,"Staged initialization mutated the prior world")
	check(scene.complete_world_initialization(bindings,catalogues),scene.error)
	var initialized := scene.snapshot()
	var expected: Dictionary=FIXTURES[1 if library.manifest.profile.edition=="ios-hd" else 2]
	verify_effects(initialized.world_initialization,expected)
	check(initialized.world_initialization.input_random_state==field.random_state,"World did not continue the scenery RNG")
	check(initialized.random_state==initialized.world_initialization.random_state,"Scenery retained the isolated field RNG")
	check(initialized.objects==field.objects and initialized.detail==field.detail,"NPC initialization changed the authored scenery")
	check(independent.snapshot()==initialized,"Deterministic staged initialization disagrees")
	check(not scene.complete_world_initialization(bindings,catalogues) and scene.snapshot()==initialized,"Repeated initialization reset the world RNG")
	var control := NpcControl.new()
	check(control.configure(bindings,catalogues,0.5),control.error)
	for id in 3:
		var route: RefCounted=scene.initial_npc_route(id)
		check(route!=null,scene.error)
		if route==null: continue
		check(route.snapshot()==initialized.world_initialization.npc_construction.actors[id].route,"World route handoff differs")
		check(control.set_initial_route(id,route),control.error)
		check(not route.advance(route.snapshot().waypoints[0]).is_empty(),route.error)
	check(scene.snapshot()==initialized,"Route handoff mutated initialization state")
	var staged: RefCounted=scene.fork_for_frame()
	check(staged.update(100,Vector3.ZERO),staged.error)
	check(staged.snapshot().random_state==initialized.random_state and staged.snapshot().world_initialization==initialized.world_initialization,"Scenery spin changed initialization RNG or records")
	check(not staged.complete_world_initialization(bindings,catalogues),"Running scenery allowed initialization")
	check(scene.configure(bindings,catalogues,1789100000),scene.error)
	check(not scene.update(-1,Vector3.ZERO),"Negative frame duration accepted")
	check(scene.complete_world_initialization(bindings,catalogues),"Failed frame closed the initialization boundary")
	check(scene.configure(bindings,catalogues,1789100000),scene.error)
	check(scene.update(0,Vector3.ZERO),scene.error)
	check(not scene.complete_world_initialization(bindings,catalogues),"Even a successful zero-time frame must close initialization")
	scene.clear();world.clear()
	check(scene.snapshot().is_empty() and world.snapshot().is_empty(),"Clear retained initialization")
	check(scene.initial_npc_route(0)==null and not world.configure(null,catalogues),"Unavailable initialization remained usable")
	print(library.manifest.profile.edition,": ordered world stream, effect orientation, route ownership and initialization boundary verified")

func verify_effects(state: Dictionary, expected: Dictionary) -> void:
	check(state.npc_construction.random_state.state==expected.npc_state,"NPC construction boundary changed")
	check(state.random_state.state==expected.final_state,"Post-weapon world RNG differs")
	check(state.weapon_effects.size()==3,"Missing opening NPC weapon effects")
	for id in 3:
		var effect: Dictionary=state.weapon_effects[id]
		check(effect.actor_id==id,"Weapon effects reordered actors")
		check(effect.discarded_default.item_id==0 and effect.discarded_default.resource_id==14600,"Missing discarded default effect assignment")
		check(effect.primary.item_id==19 and effect.primary.resource_id==14605,"Wrong active weapon effect assignment")
		check(effect.discarded_default.flipped==expected.flipped[id][0] and effect.primary.flipped==expected.flipped[id][1],"Weapon effect slot order or zero polarity changed")
		check(state.npc_construction.actors[id].cargo.is_empty(),"Opening granted discarded cargo")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)

const FIXTURES = [{"name":"zero_seed","npc_state":5646331179885,"final_state":64073765226277,"flipped":[[[false,true,true,false],[false,false,false,true]],[[false,false,false,true],[false,true,true,false]],[[false,true,true,true],[true,false,false,true]]]},{"name":"ios_field_seed","npc_state":140974702666229,"final_state":203124760899757,"flipped":[[[false,false,true,true],[false,true,false,true]],[[false,true,false,false],[false,false,true,true]],[[false,false,true,true],[false,false,true,false]]]},{"name":"mac_field_seed","npc_state":56108864767610,"final_state":184786094478354,"flipped":[[[true,false,false,false],[false,false,true,true]],[[false,true,false,false],[true,false,true,false]],[[false,true,false,true],[false,true,true,false]]]}]
