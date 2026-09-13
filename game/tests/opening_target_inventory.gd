extends SceneTree
const Inventory = preload("res://src/simulation/opening_target_inventory.gd")
const Field = preload("res://src/simulation/scenery_field.gd")
const Generator = preload("res://src/simulation/seeded_random.gd")
const SceneryFixture = preload("res://tests/scenery_fixture.gd")
const ActorFixture = preload("res://tests/opening_actor_fixture.gd")
const Actors = preload("res://src/simulation/opening_actor_state.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const OpeningScenery = preload("res://src/simulation/opening_scenery.gd")
const BodyResources = preload("res://src/content/scenery_body_resources.gd")
const Combat = preload("res://src/simulation/opening_combat_group.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%2==0,"Expected content/binding pairs")
	for index in range(0,args.size()-1,2):check_profile(args[index],args[index+1])
	print("Opening target inventory checks: %d failures" % failures)
	quit(1 if failures else 0)

func fixture() -> Dictionary:
	var pair := SceneryFixture.make();var bindings: RefCounted = pair[0];var catalogues: RefCounted = pair[1]
	bindings.opening_sky={"star_mesh_base":1,"star_texture_base":2,"sky_mesh_id":3,"sky_texture_id":4,
		"world_type":3,"campaign_cursor":0,"star_variants":3,"location_match":false}
	bindings.vehicle_response={"equipment_rule":"last_matching","item_type_value_index":5,"base_add":0.0,"base_divisor":1.0,
		"base_scale":1.0,"base_offset":0.0,"upgrade_bonus":1.0,"percent_divisor":100.0,"response_scale":1.0,
		"upgrade_tag":0,"equipment_type":0,"equipment_percent_property":0}
	catalogues.tables.ships=[{"stats":{"primary_slots":2,"secondary_slots":1,"turret_slots":1,"equipment_slots":4}},{}]
	for category in [0,1,3,3,3,3]:
		catalogues.tables.items.append({"arrays":[[],[],[0,0,1,category,0,category]]})
	bindings.opening_loadout={"ship_id":0,"station_id":0,"item_category_value_index":3,"equipment":[
		{"item_id":12,"slot":0,"quantity":1},{"item_id":12,"slot":1,"quantity":1},
		{"item_id":14,"slot":0,"quantity":1},{"item_id":15,"slot":1,"quantity":1},
		{"item_id":16,"slot":2,"quantity":1},{"item_id":17,"slot":3,"quantity":1},
		{"item_id":13,"slot":0,"quantity":9}]}
	bindings.opening_actors=ActorFixture.definition()
	bindings.ship_model_resources=[1000,1001]
	for id in [1000,1001]:
		var path := "resources/data/meshes/test_ship_%d.aem" % id
		bindings.records[id]=[{"resource":path,"kind":"mesh","registration_type":4}]
		bindings.base_files[path]={"kind":"mesh"}
	var builder := Field.new();var random := Generator.new();random.seed_from(3)
	check(builder.configure(bindings,catalogues,0,false,false,0),builder.error)
	var field := builder.generate(Vector3.ZERO,random.snapshot())
	check(not field.is_empty(),builder.error)
	return {"bindings":bindings,"catalogues":catalogues,"field":field}

func owners(data: Dictionary) -> Array:
	var initial := Actors.new()
	check(initial.configure(data.bindings,data.catalogues,data.bindings.base_content_id),initial.error)
	var actors: Dictionary = initial.snapshot()
	for actor in actors.actors:
		actor.base_content_id=data.bindings.base_content_id;actor.binding_id=data.bindings.binding_id
		actor.vitals={"hull":10,"armor":0,"shield":0.0};actor.active=true
	var bodies := {"base_content_id":data.bindings.base_content_id,"binding_id":data.bindings.binding_id,"objects":data.field.objects.duplicate(true)}
	for body in bodies.objects:body.vitals={"hull":10,"armor":0,"shield":0.0};body.active=true
	return [actors,bodies]

func check_synthetic() -> void:
	var inventory := Inventory.new();var data := fixture()
	check(inventory.snapshot().is_empty() and not inventory.validate_loadout({}) and not inventory.validate_owners({},{}),"Unconfigured inventory accepted owners")
	check(inventory.configure(data.bindings,data.catalogues,data.field),inventory.error)
	var state := inventory.snapshot()
	check(state.npc_ids==[0,1] and state.equipment_ids==[12,12,13,14,15,16,17],"Source actor/equipment order was lost")
	check(state.scenery_indices==range(data.field.objects.size()) and state.third_group_absence=="missing_equipment_type" and state.required_equipment_type==33,"Fresh target group membership was lost")
	check(state.loadout.slots[3]==null and state.loadout.slots[2].quantity==9,"Canonical loadout lost an empty slot or stack")
	var pair := owners(data)
	check(inventory.validate_owners(pair[0],pair[1]),inventory.error)
	pair[0].actors[0].position=Vector3.ONE;pair[0].actors[0].active=false;pair[0].actors[0].vitals.hull=0
	pair[1].objects[0].active=false;pair[1].objects[0].vitals.hull=0;pair[1].objects[0].damaged=true
	check(inventory.validate_owners(pair[0],pair[1]),"Live combat changes invalidated target membership")
	var loadout: Dictionary = state.loadout.duplicate(true);loadout.station_id=999
	check(inventory.validate_loadout(loadout),"Unrelated loadout metadata changed canonical membership")
	for mutation in ["identity","binding","ship","slot_count","item","quantity","slot_order","equipment_order","quantity_type","missing"]:
		var bad: Dictionary = state.loadout.duplicate(true)
		match mutation:
			"identity":bad.base_content_id="f".repeat(64)
			"binding":bad.binding_id="f".repeat(64)
			"ship":bad.ship_id=1
			"slot_count":bad.slots.pop_back()
			"item":bad.slots[0].item_id=13
			"quantity":bad.slots[0].quantity=2
			"slot_order":bad.slots.reverse()
			"equipment_order":bad.equipment_ids.reverse()
			"quantity_type":bad.slots[0].quantity=1.0
			"missing":bad.erase("slots")
		check(not inventory.validate_loadout(bad) and not inventory.error.is_empty() and inventory.snapshot()==state,"Changed primary loadout retained fresh exclusion: "+mutation)
	for mutation in ["identity","actor_count","actor_order","actor_hull","actor_binding","scenery_count","scenery_order","position","model","item","scale","large"]:
		pair=owners(data)
		match mutation:
			"identity":pair[1].binding_id="c".repeat(64)
			"actor_count":pair[0].actors.pop_back()
			"actor_order":pair[0].actors.reverse()
			"actor_hull":pair[0].actors[0].hull_catalogue_id=1
			"actor_binding":pair[0].actors[0].binding_id="c".repeat(64)
			"scenery_count":pair[1].objects.pop_back()
			"scenery_order":pair[1].objects.reverse()
			"position":pair[1].objects[0].position+=Vector3.ONE
			"model":pair[1].objects[0].model_id+=1
			"item":pair[1].objects[0].item_id+=1
			"scale":pair[1].objects[0].scale+=0.1
			"large":pair[1].objects[0].large=false
		check(not inventory.validate_owners(pair[0],pair[1]) and not inventory.error.is_empty() and inventory.snapshot()==state,"Changed owner retained source membership: "+mutation)
	check(inventory.validate_loadout(state.loadout) and inventory.error.is_empty(),"Successful validation retained a stale error")
	var detached := inventory.snapshot();detached.loadout.slots[0].quantity=123;detached.npc_ids.reverse();detached.scenery_indices.clear()
	data.bindings.opening_loadout.equipment[0].quantity=123;data.field.objects[0].position=Vector3.INF
	check(inventory.snapshot()==state and inventory.validate_loadout(state.loadout),"Inventory aliases inputs or snapshots")
	for mutation in ["identity","catalogue","world","cursor","location","type_schema","missing_type","type_33","bad_type","actor_order","actor_hull","field_station","field_system","field_identity","center","count","index","large_count","large_order","position","scale","model","variant","ore"]:
		data=fixture()
		match mutation:
			"identity":data.bindings.base_content_id="d".repeat(64)
			"catalogue":data.catalogues.content_id="d".repeat(64)
			"world":data.bindings.opening_sky.world_type=4
			"cursor":data.bindings.opening_sky.campaign_cursor=1
			"location":data.bindings.opening_sky.location_match=true
			"type_schema":data.bindings.vehicle_response.item_type_value_index=4
			"missing_type":data.catalogues.tables.items[12].arrays[2].resize(4)
			"type_33":data.catalogues.tables.items[12].arrays[2][5]=33
			"bad_type":data.catalogues.tables.items[12].arrays[2][5]=true
			"actor_order":data.bindings.opening_actors.actors.reverse()
			"actor_hull":data.bindings.opening_actors.actors[0].hull_catalogue_id=2
			"field_station":data.field.station_id=1
			"field_system":data.field.system_id=1
			"field_identity":data.field.binding_id="d".repeat(64)
			"center":data.field.center=Vector3.ONE
			"count":data.field.objects.pop_back()
			"index":data.field.objects[0].index=1
			"large_count":data.field.large_count=10
			"large_order":data.field.objects[0].large=false
			"position":data.field.objects[0].position=Vector3.INF
			"scale":data.field.objects[0].scale=0.5
			"model":data.field.objects[0].model_id+=1
			"variant":data.field.objects[0].model_variant=3
			"ore":data.field.objects[0].item_id=11
		check(not inventory.configure(data.bindings,data.catalogues,data.field) and inventory.snapshot().is_empty() and not inventory.error.is_empty(),"Invalid fresh target inventory retained state: "+mutation)
	check(not inventory.configure(null,null,{}) and inventory.snapshot().is_empty(),"Missing inventory inputs accepted")

func check_profile(content: String, pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var resources := BodyResources.new();var scenery := OpeningScenery.new();var combat := Combat.new();var inventory := Inventory.new()
	if not resources.configure(library,bindings) or not scenery.configure(bindings,catalogues,1789100000,true,resources) or not combat.configure(bindings,catalogues,0.5):
		check(false,resources.error+scenery.error+combat.error);return
	var field: Dictionary = scenery.snapshot()
	check(inventory.configure(bindings,catalogues,field),inventory.error)
	check(inventory.validate_owners(combat.snapshot(),field.bodies),inventory.error)
	check(inventory.validate_loadout(inventory.snapshot().loadout),inventory.error)
	check(inventory.snapshot().npc_ids==[0,1,2] and inventory.snapshot().scenery_indices.size()==field.objects.size(),"Actual complete target groups differ from source")
	var live := combat.snapshot();live.actors[0].active=true;live.actors[0].vitals.hull=0;live.actors[0].position=Vector3.ZERO
	check(inventory.validate_owners(live,field.bodies),"Actual changing combat state invalidated membership")
	var item: int = inventory.snapshot().equipment_ids[0]
	var type_index := int(bindings.vehicle_response.item_type_value_index)
	catalogues.tables.items[item].arrays[2][type_index]=33
	check(not inventory.configure(bindings,catalogues,field) and inventory.snapshot().is_empty(),"Actual equipped type33 retained third-group exclusion")
	print(library.manifest.profile.edition+": fresh target inventory, live owners and equipment gate checked")

func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
