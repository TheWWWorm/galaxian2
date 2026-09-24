extends SceneTree
const Player = preload("res://src/simulation/opening_player_state.gd")
const Definitions = preload("res://src/content/player_initialization_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
var failures := 0

func _initialize() -> void:
	check_capacities()
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Expected content/bindings/visuals triples")
	for index in range(0,args.size()-2,3): check_profile(args[index],args[index+1])
	print("Opening player state checks: %d failures" % failures)
	quit(1 if failures else 0)

func item(type_id: int, properties: Dictionary) -> Dictionary:
	return {"arrays":[[],[],PackedInt32Array([0,0,1,3,0,type_id])],"properties":properties}

func check_capacities() -> void:
	var definition: Dictionary=Definitions.VALUES.duplicate()
	var items := [item(9,{18:50}),item(10,{20:75}),item(9,{18:120}),item(10,{20:90}),item(14,{})]
	check(Player.resolve_capacities(items,[],definition)=={"shield":0,"armor":0,"shield_item_id":-1,"armor_item_id":-1},"Missing equipment gained a capacity")
	check(Player.resolve_capacities(items,[0,1,2,3,4],definition)=={"shield":120,"armor":90,"shield_item_id":2,"armor_item_id":3},"Capacities were summed or unrelated equipment changed pools")
	check(Player.resolve_capacities(items,[2,3,0,1],definition)=={"shield":50,"armor":75,"shield_item_id":0,"armor_item_id":1},"Slot order did not select the last matching device")
	check(Player.resolve_capacities(items,[0,0],definition).shield==50,"Repeated shield was counted twice")
	for ids in [[5],[-1],[0.0],[true]]:
		check(Player.resolve_capacities(items,ids,definition).is_empty(),"Invalid equipment reference was accepted")
	for broken in [{}, {"arrays":[[],[],[]]}, item(9,{}),item(10,{20:-1}),item(9,{18:2147483647}),item(9,{18:1.5}),item(10,{20:true})]:
		check(Player.resolve_capacities([broken],[0],definition).is_empty(),"Invalid equipped capacity was accepted")
	var wrong := definition.duplicate();wrong.equipment_rule="sum"
	check(Player.resolve_capacities(items,[0],wrong).is_empty(),"Unknown equipment rule was accepted")
	check(not Player.new().configure(null,null),"Unconfigured player accepted missing content")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var owner := Player.new()
	if bindings.opening_actors.get("player_initialization",{}).is_empty():
		check(not owner.configure(bindings,catalogues) and owner.snapshot().is_empty(),"Older pack invented player initialization")
		return
	check(owner.configure(bindings,catalogues),owner.error)
	var original: Dictionary=owner.snapshot()
	check(original.vitals=={"hull":9999999,"armor":250,"shield":220.0},"Source player pools changed")
	check(original.capacities=={"shield":220,"armor":250,"shield_item_id":54,"armor_item_id":59},"Source capacity equipment was not retained")
	check(original.ship_id==10 and original.equipment_ids==[2,2,36,54,59,82,73],"Player loadout changed")
	check(original.half_extent==1200 and original.active and original.damage_allowed and original.is_player,"Source player flags or extent changed")
	if bindings.opening_actors.player_initialization.get("repair",{}).is_empty():
		check(not original.has("max_hull"),"Unverified maximum hull inferred")
	else:check(original.max_hull==9999999,"Player maximum hull lost its opening setter override")
	var fork: RefCounted=owner.fork_for_frame()
	var collision: RefCounted=owner.fork_for_frame()
	var hit: Dictionary=collision.normal_hit(20)
	check(not hit.is_empty() and hit.accepted and hit.after.shield==200.0 and owner.snapshot()==original,"Physical damage changed the retained player or bypassed its shield")
	var damaged: Dictionary=collision.snapshot()
	for amount in [-1,1.5,true,NAN]:
		check(collision.normal_hit(amount).is_empty() and collision.snapshot()==damaged,"Invalid physical damage changed player pools")
	check(collision.set_permissions(true,false),collision.error)
	check(not collision.normal_hit(20).accepted and collision.snapshot().vitals==damaged.vitals,"Physical contact ignored damage permission")
	check(collision.set_permissions(false,true),collision.error)
	check(not collision.normal_hit(20).accepted and collision.snapshot().vitals==damaged.vitals,"Inactive statistics accepted physical damage")
	check(collision.set_permissions(true,true),collision.error)
	check(collision.normal_hit(10000449).destroyed_now and collision.snapshot().vitals.hull==0,"Physical damage did not pass through all source pools")
	check(not collision.normal_hit(20).accepted,"Dead player received another physical hit")
	var detached: Dictionary=owner.snapshot();detached.vitals.shield=0;detached.equipment_ids.clear()
	check(owner.snapshot()==original and fork.snapshot()==original,"Player state aliases a snapshot or fork")
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	var definition: Dictionary=bindings.opening_actors.player_initialization
	check(Definitions.validate(definition,header.source_executable_bytes,header.architecture).is_empty(),"Source player declaration failed validation")
	for corruption in ["extent","missing_span","overlap","permission","property"]:
		var changed := definition.duplicate(true)
		match corruption:
			"extent": changed.provenance.factory.offset=header.source_executable_bytes
			"missing_span": changed.provenance.erase("armor_assignment")
			"overlap": changed.provenance.shield_getter.offset=changed.provenance.factory.offset
			"permission": changed.initial_damage_allowed=1
			"property": changed.shield_property=20
		check(not Definitions.validate(changed,header.source_executable_bytes,header.architecture).is_empty(),"Invalid declaration accepted: "+corruption)
	var identity: String=catalogues.content_id
	catalogues.content_id="0".repeat(64)
	check(not owner.configure(bindings,catalogues) and owner.snapshot().is_empty(),"Cross-content failure retained player state")
	catalogues.content_id=identity
	check(fork.snapshot()==original,"Reconfiguration changed a previous frame's player")
	var properties: Dictionary=catalogues.tables.items[54].properties
	var saved: Variant=properties[18]
	properties[18]=16777217
	check(owner.configure(bindings,catalogues),owner.error)
	check(owner.snapshot().vitals.shield==16777216.0 and owner.snapshot().capacities.shield==16777217,"Shield initialization lost binary32 conversion or integer capacity")
	properties.erase(18)
	check(not owner.configure(bindings,catalogues) and owner.snapshot().is_empty(),"Missing shield property retained player state")
	properties[18]=saved
	bindings.opening_actors.player_initialization={}
	check(not owner.configure(bindings,catalogues) and owner.snapshot().is_empty(),"Unsupported player definitions produced a fallback body")
	print(library.manifest.profile.edition,": verified fresh player pools and provenance")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)
