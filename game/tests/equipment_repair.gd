extends SceneTree
const Repair = preload("res://src/simulation/equipment_repair.gd")
const Definitions = preload("res://src/content/player_repair_definitions.gd")
const Player = preload("res://src/simulation/opening_player_state.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	check_pulses()
	check_resolution()
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3):check_profile(args[index],args[index+1])
	print("Equipment repair checks: %d failures" % failures)
	quit(1 if failures else 0)

func parameters() -> Dictionary:
	var result := Definitions.VALUES.duplicate(true);result.provenance={}
	return result

func check_pulses() -> void:
	var owner := Repair.new()
	check(owner.configure(parameters(),200,250,0),owner.error)
	var equal: Dictionary=owner.advance(198,240,600)
	check(not equal.hull_pulsed and not equal.armor_pulsed and equal.hull_elapsed_ms==600,"Slow repair fired at equality")
	var pulse: Dictionary=owner.advance(198,240,401)
	check(pulse.hull_repaired==1 and pulse.armor_repaired==0 and pulse.armor_pulsed,"Armor repaired before full hull or did not reset its overdue clock")
	check(pulse.hull_elapsed_ms==0 and pulse.armor_elapsed_ms==0,"Repair retained overshoot")
	pulse=owner.advance(199,240,1001)
	check(pulse.after=={"hull":200,"armor":242} and pulse.hull_repaired==1 and pulse.armor_repaired==2,"Same-frame hull completion did not permit armor repair")
	check(owner.advance(200,249,1001).after.armor==250,"Armor repair exceeded capacity")
	check(owner.configure(parameters(),200,250,1),owner.error)
	check(not owner.advance(199,240,420).hull_pulsed,"Fast hull repair fired at equality")
	check(owner.advance(199,240,1).after.hull==200,"Fast hull repair missed its strict threshold")
	check(not owner.advance(200,240,279).armor_pulsed,"Fast armor repair fired at equality")
	check(owner.advance(200,240,1).after.armor==242,"Fast armor repair missed its strict threshold")
	var frozen := owner.snapshot()
	check(not owner.advance(200,250,0).hull_pulsed and owner.snapshot()==frozen,"Zero-time repair consumed its clocks")
	check(owner.advance(0,20,1000).after=={"hull":0,"armor":20} and owner.snapshot()==frozen,"Dead hull consumed repair time")
	var fork: RefCounted=owner.fork_for_frame()
	check(not fork.advance(200,250,1000).is_empty() and owner.snapshot()==frozen,"Repair fork mutated original clocks")
	var detached: Dictionary=owner.snapshot();detached.hull_elapsed_ms=999
	check(owner.snapshot()==frozen,"Repair snapshot aliases clocks")
	for invalid in [[-1,250,1],[200,1.5,1],[200,250,-1],[200,250,true],[200,250,2147483648]]:
		check(owner.advance(invalid[0],invalid[1],invalid[2]).is_empty() and owner.snapshot()==frozen,"Invalid repair update changed its clocks")
	check(owner.configure(parameters(),200,250,-1),owner.error)
	check(owner.advance(9999999,300,1001).after=={"hull":9999999,"armor":300} and owner.snapshot().hull_elapsed_ms==0,"Missing device healed or clamped source overrides")
	check(owner.configure(parameters(),200,250,0),owner.error)
	check(owner.advance(9999999,300,1001).after=={"hull":9999999,"armor":300},"Repair reduced pools already above capacity")
	check(owner.advance(9999999,200,1001).after=={"hull":9999999,"armor":202},"Scripted hull above maximum incorrectly blocked armor repair")
	check(owner.configure(parameters(),200,2147483647,0),owner.error)
	frozen=owner.snapshot()
	check(owner.advance(200,2147483646,1001).is_empty() and owner.snapshot()==frozen,"Overflowing armor repair partially committed")
	for invalid in [[-1,250,0],[200,250,2],[200,250,0.0],[200,true,0]]:
		check(not owner.configure(parameters(),invalid[0],invalid[1],invalid[2]) and owner.snapshot().is_empty(),"Invalid repair configuration retained state")
	check(owner.advance(1,1,1).is_empty(),"Unconfigured repair advanced")

func check_resolution() -> void:
	check(Player.resolve_ship_hull(200,[0,2,0],parameters())==280,"Hull upgrades lost repeated matching tags")
	check(Player.resolve_ship_hull(2147483640,[0],parameters())==-1,"Overflowing upgraded hull accepted")
	check(Player.resolve_ship_hull(200,[true],parameters())==-1,"Implicit upgrade tag accepted")
	var items := [{"arrays":[[],[],[0,75,1,3,2,15]]},{"arrays":[[],[],[0,188,1,3,2,15]]},{"arrays":[[],[],[0,73,1,3,2,14]]}]
	check(Player.resolve_repair_device(items,[],parameters())=={"mode":-1,"item_id":-1},"Missing repair device was invented")
	check(Player.resolve_repair_device(items,[0,1,2],parameters())=={"mode":1,"item_id":1},"Last matching repair device was not selected")
	check(Player.resolve_repair_device(items,[1,0],parameters())=={"mode":0,"item_id":0},"Device used record index instead of its source ID")
	check(Player.resolve_repair_device(items,[3],parameters()).is_empty(),"Missing device record accepted")
	items[0].arrays[2][1]=-1
	check(Player.resolve_repair_device(items,[0],parameters()).is_empty(),"Invalid source device ID accepted")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var player := Player.new();check(player.configure(bindings,catalogues),player.error)
	var original: Dictionary=player.snapshot()
	var policy: Dictionary=bindings.opening_actors.player_initialization.get("repair",{})
	if policy.is_empty():
		check(not original.has("repair") and not original.has("max_hull") and player.advance_repair(1001).is_empty() and player.snapshot()==original,"Older pack invented repair or maximum hull")
		print(library.manifest.profile.edition,": legacy repair absence verified");return
	check(original.max_hull==9999999 and original.repair=={"max_hull":9999999,"max_armor":250,"device_mode":-1,"hull_elapsed_ms":0,"armor_elapsed_ms":0},"Opening hull setter did not raise the maximum or absent repair device changed")
	check(not player.advance_repair(1001).armor_pulsed and player.snapshot()==original,"Fresh equipment unexpectedly repaired")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	check(Definitions.validate(policy,header.source_executable_bytes,header.architecture,bindings.opening_actors.player_initialization).is_empty(),"Source repair declaration failed validation")
	for key in ["update","timers_zero"]:
		var wrong := policy.duplicate(true);wrong.provenance[key].offset+=2
		check(not Definitions.validate(wrong,header.source_executable_bytes,header.architecture,bindings.opening_actors.player_initialization).is_empty(),"Disconnected repair anchor accepted")
	# Explicit synthetic equipment changes exercise the supplied source devices.
	for device_id in [75,188]:
		bindings.opening_loadout.equipment[5].item_id=device_id
		check(player.configure(bindings,catalogues),player.error)
		check(player.snapshot().repair.device_mode==(0 if device_id==75 else 1),"Supplied repair device selected the wrong timing")
		player._state.vitals.hull=9999997;player._state.vitals.armor=240
		check(player.advance_repair(1001).after=={"hull":9999998,"armor":240},"Armor repaired before hull reached its authored maximum")
		check(player.advance_repair(1001).after=={"hull":9999999,"armor":242},"Repair did not fill the raised maximum before armor")
		player._state.vitals.hull=500;player._state.vitals.armor=240
		check(player.advance_repair(1001).after=={"hull":501,"armor":240},"Ship base hull incorrectly unlocked armor repair")
	bindings.opening_loadout.equipment[5].item_id=73
	for override in [100,200]:
		bindings.opening_actors.player_current_hull_override=override
		check(player.configure(bindings,catalogues),player.error)
		check(player.snapshot().max_hull==200 and player.snapshot().repair.max_hull==200 and player.snapshot().vitals.hull==override,"Opening hull setter lowered factory maximum or changed current hull")
	bindings.opening_actors.player_current_hull_override=9999999
	check(player.configure(bindings,catalogues) and player.snapshot()==original,"Restoring loadout did not restore fresh player state")
	var recharge: Dictionary=bindings.opening_actors.player_initialization.recharge
	bindings.opening_actors.player_initialization.recharge={}
	check(not player.configure(bindings,catalogues) and player.snapshot().is_empty(),"Repair configured without its ordinary player ordering capability")
	bindings.opening_actors.player_initialization.recharge=recharge
	var fields: Variant=catalogues.tables.ships[10].fields
	catalogues.tables.ships[10].fields=[]
	check(not player.configure(bindings,catalogues) and player.snapshot().is_empty(),"Missing source hull retained player state")
	catalogues.tables.ships[10].fields=fields
	print(library.manifest.profile.edition,": maximum hull, absent/fitted devices and repair declarations verified")

func check(condition: bool, message: String) -> void:
	if not condition:failures+=1;push_error(message)
