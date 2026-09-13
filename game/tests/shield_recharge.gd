extends SceneTree
const Recharge = preload("res://src/simulation/shield_recharge.gd")
const Definitions = preload("res://src/content/player_recharge_definitions.gd")
const Player = preload("res://src/simulation/opening_player_state.gd")
const PlayerDefinitions = preload("res://src/content/player_initialization_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	check_clock()
	check_invalid()
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3): check_profile(args[index],args[index+1])
	print("Shield recharge checks: %d failures" % failures)
	quit(1 if failures else 0)

func parameters() -> Dictionary:
	var result := Definitions.VALUES.duplicate();result.provenance={}
	return result

func check_clock() -> void:
	var owner := Recharge.new()
	check(owner.configure(parameters(),220,60000),owner.error)
	# Independently rounded IEEE-754 result for 220 / (60000 / 100).
	check(owner.snapshot().pulse==0.36666667461395264,"Starting pulse lost binary32 division")
	check(owner.advance(1,0.0,100)=={"pulsed":false,"before":0.0,"after":0.0,"elapsed_ms":100},"Equality produced a recharge pulse")
	check(not owner.advance(1,0.0,0).pulsed and owner.snapshot().elapsed_ms==100,"Zero-time update changed the threshold")
	var fork: RefCounted=owner.fork_for_frame()
	check(fork.advance(1,0.0,1).after==0.36666667461395264 and fork.snapshot().elapsed_ms==0,"Strict threshold did not emit its single pulse")
	check(owner.snapshot().elapsed_ms==100,"Recharge fork aliases its source")
	var detached: Dictionary=owner.snapshot();detached.elapsed_ms=0
	check(owner.snapshot().elapsed_ms==100,"Recharge snapshot aliases its timer")
	var large: Dictionary=fork.advance(1,0.0,1000)
	check(large.pulsed and large.after==0.36666667461395264 and large.elapsed_ms==0,"Large frame repeated pulses or retained overshoot")
	check(fork.advance(1,219.9,101).after==220.0,"Recharge exceeded equipment capacity")
	check(fork.advance(1,220.0,100).elapsed_ms==100 and fork.advance(1,220.0,1).pulsed,"Full shield stopped the source timer")
	check(fork.advance(1,0.0,70).elapsed_ms==70,"Recharge timer did not retain partial time")
	check(fork.advance(0,12.5,1000)=={"pulsed":false,"before":12.5,"after":12.5,"elapsed_ms":70},"Dead hull consumed recharge time")
	check(fork.advance(1,0.0,31).pulsed,"Living hull did not resume its retained timer")
	check(owner.configure(parameters(),220,0),owner.error)
	check(owner.advance(1,12.5,1000)=={"pulsed":false,"before":12.5,"after":12.5,"elapsed_ms":0},"Disabled recharge changed time or shield")
	check(owner.configure(parameters(),16777217,60000),owner.error)
	check(owner.snapshot().pulse==27962.02734375,"Integer capacity did not round before division")
	check(owner.configure(parameters(),0,60000) and owner.advance(1,0.0,101).after==0.0,"Zero-capacity shield gained charge")

func check_invalid() -> void:
	var owner := Recharge.new()
	for values in [[-1,60000],[220,-1],[220,60000.0],[true,60000],[2147483647,60000],[220,2147483648]]:
		check(not owner.configure(parameters(),values[0],values[1]) and owner.snapshot().is_empty(),"Invalid equipment value accepted")
	check(owner.configure(parameters(),220,60000),owner.error)
	check(not owner.advance(1,10.0,50).is_empty(),owner.error)
	var original := owner.snapshot()
	for values in [[-1,10.0,1],[1.0,10.0,1],[1,-1.0,1],[1,INF,1],[1,NAN,1],[1,true,1],[1,2147483647.0,1],[1,10.0,-1],[1,10.0,1.5],[1,10.0,2147483648]]:
		check(owner.advance(values[0],values[1],values[2]).is_empty() and owner.snapshot()==original,"Invalid update changed recharge state")
	var wrong := parameters();wrong.period_ms=101
	check(not owner.configure(wrong,220,60000) and owner.snapshot().is_empty(),"Unknown timing policy retained prior state")
	check(owner.advance(1,0.0,1).is_empty(),"Unconfigured recharge advanced")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var player := Player.new()
	check(player.configure(bindings,catalogues),player.error)
	var original: Dictionary=player.snapshot()
	var policy: Dictionary=bindings.opening_actors.player_initialization.get("recharge",{})
	if policy.is_empty():
		check(not original.has("recharge") and player.advance_recharge(101).is_empty() and player.snapshot()==original,"Legacy profile invented recharge")
		print(library.manifest.profile.edition,": legacy recharge absence verified")
		return
	check(original.recharge=={"capacity":220,"duration_ms":60000,"pulse":0.36666667461395264,"elapsed_ms":0},"Player did not bind its equipped recharge property")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	check(Definitions.validate(policy,header.source_executable_bytes,header.architecture,bindings.opening_actors.player_initialization).is_empty(),"Source recharge failed validation")
	for malformed in [null,"invalid",{}, {"shield_assignment":1,"reset":null}]:
		var broken: Dictionary=bindings.opening_actors.player_initialization.duplicate(true);broken.provenance=malformed
		check(not Definitions.validate(policy,header.source_executable_bytes,header.architecture,broken).is_empty(),"Recharge accepted malformed parent provenance")
		check(not PlayerDefinitions.validate(broken,header.source_executable_bytes,header.architecture).is_empty(),"Player validation accepted malformed recharge anchors")
	for corruption in ["period","equipment","overlap","extent","anchor","missing"]:
		var wrong := policy.duplicate(true)
		match corruption:
			"period":wrong.period_ms=101
			"equipment":wrong.equipment_property=18
			"overlap":wrong.provenance.getter.offset=wrong.provenance.pulse.offset
			"extent":wrong.provenance.pulse.offset=header.source_executable_bytes
			"anchor":wrong.provenance.assignment.offset+=1
			"missing":wrong.provenance.erase("world_pass")
		check(not Definitions.validate(wrong,header.source_executable_bytes,header.architecture,bindings.opening_actors.player_initialization).is_empty(),"Malformed recharge accepted: "+corruption)
	var fork: RefCounted=player.fork_for_frame()
	check(fork.advance_recharge(101).pulsed and player.snapshot()==original,"Player recharge fork mutated its source")
	var properties: Dictionary=catalogues.tables.items[54].properties
	var saved: Variant=properties[19]
	for invalid in [null,-1,1.5,true]:
		if invalid==null:properties.erase(19)
		else:properties[19]=invalid
		check(not player.configure(bindings,catalogues) and player.snapshot().is_empty(),"Missing or malformed equipped duration accepted")
	properties[19]=0
	check(player.configure(bindings,catalogues) and not player.advance_recharge(1000).pulsed,"Explicit zero duration was not disabled")
	properties[19]=saved
	check(player.configure(bindings,catalogues),player.error)
	check(player.snapshot()==original,"Restoring equipment did not restore fresh recharge state")
	print(library.manifest.profile.edition,": equipment recharge, strict clock, validation and fork isolation verified")

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
