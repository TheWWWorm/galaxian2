extends "res://tests/gate_environment.gd"
## Explicit catalogue loadouts exercise native resolution and original effect
## assets. These diagnostics create no inventory, wallet or campaign progress.
const Fitting=preload("res://src/simulation/equipment_fitting.gd")
const FittingRules=preload("res://src/content/ordinary_fitting_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Stats=preload("res://src/simulation/equipment_stats.gd")
const Primary=preload("res://src/simulation/primary_weapons.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const Visuals=preload("res://src/simulation/projectile_visual_state.gd")
const Impacts=preload("res://src/simulation/ordinary_impact_state.gd")
const Textures=preload("res://src/content/visual_library.gd")
const Geometry=preload("res://src/presentation/projectile_geometry.gd")
const ImpactGeometry=preload("res://src/presentation/ordinary_impact_geometry.gd")
const EquipmentCheckpoint=preload("res://tests/fixtures/equipment_scenario.gd")

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify_fitting(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Equipment fitting rules: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_fitting(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var mounts:=Mounts.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not mounts.open(library,cat):check(false,library.error+bindings.error+cat.error+mounts.error);return
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"ship_id":int(bindings.station_departure.ship_id),"station_id":98,"system_id":19,"campaign_cursor":18,"equipment_ids":[],"slots":[]}
	seed.system_id=int(cat.tables.stations[98].system_id)
	var counts:=[]
	for property in Loadout.SLOT_PROPERTIES:counts.append(int(cat.tables.ships[seed.ship_id].stats[property]))
	var extent:=0
	for count in counts:extent+=count
	seed.slots.resize(extent)
	var fitting:=Fitting.new();var assets:=fitting.prepare_assets(bindings,cat,library)
	var empty:=fitting.inspect(bindings,cat,seed,assets)
	if not FittingRules.available(bindings):
		check(empty.is_empty(),"Earlier bindings inferred general equipment fitting")
		return
	if empty.is_empty():check(false,fitting.error);return
	var textures: RefCounted
	if OS.get_environment("GOF2_FITTING_GEOMETRY")=="1":
		textures=Textures.new()
		if not textures.open(args[2],library.manifest):check(false,textures.error);return
	check(empty.stats.armor==0 and empty.stats.shield==0 and empty.stats.cargo_capacity==25 and empty.stats.passenger_capacity==0,"Empty equipment changed base capacities")
	var primary:=Primary.new()
	check(primary.configure(bindings,cat,mounts,seed) and primary.snapshot().guns.is_empty(),"An unarmed ship failed primary construction: "+primary.error)
	verify_empty_effects(bindings,library,primary,textures)
	var supported:=[];var guns:=[]
	for id in empty.support:
		if not empty.support[id].is_empty():continue
		var candidate:=seed.duplicate(true);var category: int=cat.tables.items[id].arrays[2][3]
		if category>=counts.size() or counts[category]==0:continue
		var offset:=0
		for i in category:offset+=counts[i]
		candidate.slots[offset]={"item_id":id,"category":category,"slot":0,"quantity":1};candidate.equipment_ids=[id]
		var resolved:=fitting.inspect(bindings,cat,candidate,assets)
		check(not resolved.is_empty(),"An offered item failed its installed resolution: %d %s"%[id,fitting.error])
		supported.append(id)
		if category!=0:continue
		if not primary.configure(bindings,cat,mounts,candidate):check(false,"Primary %d: %s"%[id,primary.error]);continue
		var world:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"elapsed_ms":0,"campaign_cursor":18,"primaries":primary.snapshot(),"weapons":{"actors":[]}}
		var visual:=Visuals.new();var impacts:=Impacts.new()
		check(visual.configure(bindings,library,world),"Projectile %d: %s"%[id,visual.error])
		check(impacts.configure(bindings,library,world),"Impact %d: %s"%[id,impacts.error])
		check(not primary.advance(1).is_empty(),primary.error)
		var fired:=primary.fire(Transform3D.IDENTITY,true,{"state":1234})
		check(not fired.is_empty(),"Firing %d: %s"%[id,primary.error])
		if textures!=null:
			var geometry:=Geometry.new();root.add_child(geometry)
			if geometry.build(visual,library,textures,bindings):
				check(visual.advance(1),visual.error)
				world.elapsed_ms=1;world.primaries=primary.snapshot();world.projectile_visuals=visual.snapshot()
				var frame:=geometry.prepare_world(visual,world,Transform3D.IDENTITY)
				check(not frame.is_empty(),"Rendered primary %d: %s"%[id,geometry.error])
				if not frame.is_empty():geometry.commit_world(frame)
			else:check(false,"Geometry %d: %s"%[id,geometry.error])
			geometry.free()
			verify_impact_geometry(id,bindings,library,textures,primary,impacts)
		guns.append(id)
	print("Supported original item IDs: ",supported,"; resolved primary IDs: ",guns)
	check(guns.has(1) and guns.has(12) and guns.has(23) and not guns.has(16) and not guns.has(9),"Primary support omitted ordinary families or accepted unfinished alternate/EMP behavior")
	var combined:=seed.duplicate(true);combined.equipment_ids=[50,55,63,64,91,92,76,75]
	var resolved:=fitting.inspect(bindings,cat,combined,assets)
	check(not resolved.is_empty(),fitting.error)
	if not resolved.is_empty():
		check(resolved.stats.cargo_capacity==65 and resolved.stats.passenger_capacity==8 and resolved.stats.armor==40 and resolved.stats.shield==50 and resolved.stats.repair_mode==0,"Stacked cargo/passenger and independent pool capacities changed")
		check(resolved.stats.response_factor>empty.stats.response_factor,"Handling equipment did not reach the shared vehicle resolver")
	var capacities:=Stats.resolve_capacities(cat.tables.items,[50,51,55,56],bindings.opening_actors.player_initialization)
	check(capacities.shield==80 and capacities.armor==80,"The final equipped shield/armor did not win in source order")
	if not OS.get_environment("GOF2_SCENARIO_INPUT").is_empty():verify_exchange(bindings,cat)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in FittingRules.SPANS:
		var bad:=bindings.mido_travel.duplicate(true);bad.provenance.erase(key)
		check(not Travel.validate(bad,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing fitting proof was accepted: "+key)

func verify_impact_geometry(id: int,bindings: RefCounted,library: RefCounted,textures: RefCounted,primary: RefCounted,impacts: RefCounted) -> void:
	# A contact-event diagnostic on an actually fired projectile. It verifies
	# original impact assets without granting a hit or kill to any career.
	var world:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"elapsed_ms":0,"campaign_cursor":18,"primaries":primary.snapshot(),"weapons":{"actors":[]}}
	var gun: Dictionary=world.primaries.guns[0];var selected:=-1
	for i in gun.projectiles.slots.size():
		if gun.projectiles.slots[i]!=null:selected=i;break
	if selected<0:check(false,"Primary %d supplied no actual projectile for its impact"%id);return
	var events:=[{"mount_id":gun.mount_id,"contacts":[{"slot":selected,"projectile_id":gun.projectiles.slots[selected].id,"geometry":{"hit":true}}]}]
	check(impacts.advance(1) and impacts.apply_contacts(world,events,[]),"Impact contact %d: %s"%[id,impacts.error])
	world.elapsed_ms=1;events[0].contacts=[]
	check(impacts.advance(1) and impacts.apply_contacts(world,events,[]),"Impact sampling %d: %s"%[id,impacts.error])
	world.elapsed_ms=2;world.impact_visuals=impacts.snapshot()
	var geometry:=ImpactGeometry.new();root.add_child(geometry)
	if geometry.build(impacts,library,textures,bindings):
		var frame:=geometry.prepare_world(impacts,world,Transform3D.IDENTITY)
		check(not frame.is_empty(),"Rendered impact %d: %s"%[id,geometry.error])
		if not frame.is_empty():
			check(frame.guns[0][selected].visible,"The original impact was absent after its actual shot contact")
			geometry.commit_world(frame)
	else:check(false,"Impact geometry %d: %s"%[id,geometry.error])
	geometry.free()

func verify_empty_effects(bindings: RefCounted,library: RefCounted,primary: RefCounted,textures: RefCounted) -> void:
	var world:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"elapsed_ms":0,"campaign_cursor":18,"primaries":primary.snapshot(),"weapons":{"actors":[]}}
	var visual:=Visuals.new();var impacts:=Impacts.new()
	check(visual.configure(bindings,library,world) and impacts.configure(bindings,library,world),"An entirely unarmed world could not prepare effects: "+visual.error+impacts.error)
	check(visual.advance(1) and impacts.advance(1) and impacts.apply_contacts(world,[],[]),"An empty effect population could not advance: "+visual.error+impacts.error)
	if textures!=null:
		var geometry:=Geometry.new();root.add_child(geometry)
		check(geometry.build(visual,library,textures,bindings),geometry.error)
		world.elapsed_ms=1;world.projectile_visuals=visual.snapshot()
		var frame:=geometry.prepare_world(visual,world,Transform3D.IDENTITY)
		check(not frame.is_empty(),"Empty projectile geometry failed: "+geometry.error)
		if not frame.is_empty():geometry.commit_world(frame)
		geometry.free()
	world.elapsed_ms=0
	for broken in ["identity","missing","actor","primary"]:
		var bad:=world.duplicate(true)
		match broken:
			"identity":bad.primaries.loadout.binding_id="0".repeat(64)
			"missing":bad.erase("weapons")
			"actor":bad.weapons.actors=[{"actor_id":1,"projectiles":{}}]
			"primary":bad.primaries.guns=[{}]
		check(not visual.configure(bindings,library,bad) and not impacts.configure(bindings,library,bad),"Malformed weapons were accepted as an empty population: "+broken)

func verify_exchange(bindings: RefCounted,cat: RefCounted) -> void:
	var checkpoint:=EquipmentCheckpoint.new()
	var equipment: RefCounted=checkpoint.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,checkpoint.error);return
	if not equipment.prepare_training_completion(bindings,cat) or not equipment.complete_training(equipment.snapshot().cargo):check(false,equipment.error);return
	# Duplicate-slot diagnostic on a detached equipment owner. It makes no
	# career transition and is never used as the earned application fixture.
	var slots: Array=equipment._state.loadout.slots
	var first:=-1;var second:=-1
	for i in slots.size():
		if slots[i]!=null and equipment._items[slots[i].item_id].subtype==int(bindings.mido_travel.exchange.find_subtype):first=i;break
	if first<0:check(false,"The earned equipment has no exchange drill");return
	var category: int=slots[first].category;var offset:=0
	for i in category:offset+=equipment._counts[i]
	for i in equipment._counts[category]:
		if slots[offset+i]==null:second=offset+i;break
	# The earned starter fills its equipment slots. Replace another item only
	# in this isolated diagnostic, preserving the catalogue's physical layout.
	if second<0:
		for i in equipment._counts[category]:
			if offset+i!=first:second=offset+i;break
	if second<0:check(false,"The ship lacks two equipment slots for this diagnostic");return
	slots[second]=slots[first].duplicate(true);slots[second].slot=second-offset
	equipment._state.prices.installed[second]=equipment._state.prices.installed[first].duplicate(true)
	var low:=mini(first,second);second=maxi(first,second);first=low
	equipment._state.loadout.equipment_ids=[]
	for slot in slots:
		if slot!=null:equipment._state.loadout.equipment_ids.append(slot.item_id)
	var previous: Dictionary=equipment.snapshot()
	check(equipment.apply_station_exchange(bindings,cat,9),equipment.error)
	var result: Dictionary=equipment.snapshot()
	check(result.loadout.slots[first].item_id==int(bindings.mido_travel.exchange.replacement_item_id) and result.loadout.slots[second]==previous.loadout.slots[second],"The story exchange removed every matching drill")
	check(result.cargo==previous.cargo and result.prices.installed[second]==previous.prices.installed[second],"The story exchange changed cargo or the remaining duplicate's price")
