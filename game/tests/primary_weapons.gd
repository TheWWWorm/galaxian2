extends SceneTree
const Primary = preload("res://src/simulation/primary_weapons.gd")
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Mounts = preload("res://src/content/weapon_mounts.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
const Opening = preload("res://src/simulation/opening_loadout.gd")
var failures := 0

class FixtureLibrary extends RefCounted:
	var error := ""
	var data: PackedByteArray
	var manifest := {"content_id":"a".repeat(64),"files":{
		"resources/data/bin/weapons_hd.bin":{"sha256":"b".repeat(64)}}}
	func read_resource(_resource: String, _limit: int) -> PackedByteArray: return data

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3 == 0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("Primary weapon ownership checks: %d failures" % failures)
	quit(1 if failures else 0)

func equipment(item_id: int, category: int, slot: int, quantity := 1) -> Dictionary:
	return {"item_id":item_id,"category":category,"slot":slot,"quantity":quantity}

func item(category: int, kind: int, properties: Dictionary) -> Dictionary:
	return {"arrays":[[],[],[0,0,1,category,2,kind]],"properties":properties}

func setup() -> Dictionary:
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	bindings.weapon_parameters = {"damage_property":49,"interval_property":51,"lifetime_property":52,"speed_property":53,
		"interval_percent_property":79,"damage_percent_property":80,"low_damage_threshold":10,
		"item_type_value_index":5,"item_category_value_index":3,"primary_category":0,"modifier_type":26,
		"percent_divisor":100.0,"default_multiplier":1.0,"missing_multiplier":-979797952.0,"low_damage_interval_scale":0.7,
		"launch_modes":{"alternate_item_ids":[3,4],"provenance":{}},"projectile_capacity":{"slots":2,"provenance":{}}}
	var catalogues := Catalogues.new()
	catalogues.content_id = bindings.base_content_id
	catalogues.tables = {"ships":[{"stats":{"primary_slots":3,"secondary_slots":0,"turret_slots":0,"equipment_slots":2}}],
		"items":[item(0,0,{49:6,51:10,52:100,53:2}),item(0,0,{49:10,51:20,52:80,53:3}),item(3,26,{79:0,80:20}),
		item(0,0,{49:6,51:10,52:100,53:2}),item(0,0,{49:6,51:10,52:100,53:2})]}
	var library := FixtureLibrary.new()
	var data := PackedByteArray()
	for value in [0,3, 0,10,-30,20, 0,20,-30,20, 0,30,-30,20]:
		data.append(value&255)
		data.append((value>>8)&255)
	library.data = data
	var mounts := Mounts.new()
	check(mounts.open(library,catalogues),mounts.error)
	var seed := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,
		"slots":[equipment(0,0,0),null,equipment(1,0,2),equipment(2,3,0),null],"equipment_ids":[0,1,2]}
	return {"bindings":bindings,"catalogues":catalogues,"mounts":mounts,"seed":seed}

func configure(owner: RefCounted, fixture: Dictionary, seed: Dictionary = {}) -> bool:
	return owner.configure(fixture.bindings,fixture.catalogues,fixture.mounts,fixture.seed if seed.is_empty() else seed)

func check_synthetic() -> void:
	var fixture := setup()
	var owner := Primary.new()
	check(owner.fire(Transform3D.IDENTITY,true).is_empty() and owner.advance(1).is_empty(),"Unconfigured owner accepted work")
	check(configure(owner,fixture),owner.error)
	var state: Dictionary = owner.snapshot()
	check(state.guns.size()==2 and state.guns[0].equipment.slot==2 and state.guns[1].equipment.slot==0,"Source reverse installation order or sparse slot changed")
	check(state.guns[1].projectiles.weapon.damage==7 and state.guns[0].projectiles.weapon.damage==12,"Installed modifiers did not reach owned guns")
	var first_mount: int = state.guns[0].mount_id
	var second_mount: int = state.guns[1].mount_id
	state.guns[0].mount.position=Vector3.ZERO
	state.loadout.slots.clear()
	check(owner.snapshot().guns[0].mount.position==Vector3(30,20,30),"Snapshot changed owned mount state")
	var initial: Dictionary = owner.fire(Transform3D.IDENTITY,true)
	check(initial.weapons[0].result.reason=="interval" and initial.weapons[1].result.reason=="interval","New group fired at equal intervals")
	owner.advance(1)
	var before: Dictionary = owner.snapshot()
	var denied: Dictionary = owner.fire(Transform3D.IDENTITY,false)
	check(denied.weapons[0].result.reason=="permission" and denied.weapons[1].result.reason=="permission" and owner.snapshot()==before,"Permission denial changed group state")
	var pose := Transform3D(Basis(Vector3(0,0,-1),Vector3.UP,Vector3.RIGHT),Vector3(100,200,300))
	var volley: Dictionary = owner.fire(pose,true)
	check(volley.weapons[0].slot==2 and volley.weapons[1].slot==0,"Volley order changed")
	check(volley.weapons[0].result.projectile.position==Vector3(230,220,270) and volley.weapons[1].result.projectile.position==Vector3(230,220,290),"Sparse guns used wrong authored mounts")
	check(volley.weapons[0].result.projectile.velocity==Vector3(3,0,0) and volley.weapons[1].result.projectile.velocity==Vector3(2,0,0),"Forward aim or per-gun speed changed")
	check(owner.snapshot().loadout.slots[0].quantity==1 and owner.snapshot().loadout.slots[2].quantity==1,"Primary firing consumed inventory quantity")
	owner.advance(10)
	var equal: Dictionary = owner.fire(pose,true)
	check(not equal.weapons[0].result.fired and not equal.weapons[1].result.fired,"Strict interval lost in owner")
	owner.advance(1)
	var later: Dictionary = owner.fire(pose,true)
	check(not later.weapons[0].result.fired and later.weapons[1].result.fired,"Independent gun cadence collapsed")
	check(owner.retire(first_mount,volley.weapons[0].result.projectile.id),owner.error)
	check(owner.snapshot().guns[1].projectiles.slots[0]!=null,"Retiring one gun's ID affected another gun")
	check(not owner.retire(first_mount,volley.weapons[0].result.projectile.id),"Retired projectile handle remained valid")
	check(configure(owner,fixture),owner.error)
	check(owner.snapshot().guns[0].mount_id!=first_mount and not owner.retire(second_mount,1),"Reconfiguration reused old weapon handles")
	check_failures(owner,fixture)
	check_atomic(owner,fixture)
	var empty: Dictionary = fixture.seed.duplicate(true)
	empty.slots[0]=null; empty.slots[2]=null; empty.equipment_ids=[2]
	check(configure(owner,fixture,empty),owner.error)
	check(owner.snapshot().guns.is_empty() and owner.fire(pose,true).weapons.is_empty() and owner.advance(1).weapons.is_empty(),"Unarmed loadout invented weapons")
	var depleted: Dictionary = fixture.seed.duplicate(true)
	depleted.slots[2].quantity=0
	check(configure(owner,fixture,depleted),owner.error)
	owner.advance(1)
	var partial: Dictionary = owner.fire(pose,true)
	check(partial.weapons[0].result.reason=="quantity" and partial.weapons[1].result.fired,"Zero-quantity equipment fired or blocked another gun")
	var bare := Projectiles.new()
	check(bare.configure(owner.snapshot().guns[1].projectiles.weapon),bare.error)
	bare.advance(1)
	var checkpoint: RefCounted = bare.fork_state()
	checkpoint.fire(Vector3.ZERO,Vector3.BACK,true)
	check(bare.snapshot().available_slots==2 and checkpoint.snapshot().available_slots==1,"Staging aliases source projectiles")
	var skew := Transform3D(Basis(Vector3.RIGHT,Vector3.UP,Vector3(3,4,0)),Vector3.ZERO)
	var launch: Dictionary = bare.fire_forward_from_mount(owner.snapshot().guns[1].mount,skew,true)
	check(launch.get("fired",false) and launch.projectile.velocity.is_equal_approx(Vector3(1.2,1.6,0)),"Forward launch failed final normalization")

func check_failures(owner: RefCounted, fixture: Dictionary) -> void:
	for mutation in ["identity","binding","ship","extent","slot","category","item","quantity","order","alternate"]:
		var seed: Dictionary = fixture.seed.duplicate(true)
		match mutation:
			"identity": seed.base_content_id="c".repeat(64)
			"binding": seed.binding_id="c".repeat(64)
			"ship": seed.ship_id=99
			"extent": seed.slots.pop_back()
			"slot": seed.slots[2].slot=1
			"category": seed.slots[2].category=3
			"item": seed.slots[2].item_id=99
			"quantity": seed.slots[2].quantity=-1
			"order": seed.equipment_ids=[1,0,2]
			"alternate": seed.slots[2].item_id=3; seed.equipment_ids=[0,3,2]
		check(not configure(owner,fixture,seed) and owner.snapshot().is_empty(),"Malformed or unsupported loadout accepted: "+mutation)
	check(configure(owner,fixture),owner.error)
	var before: Dictionary = owner.snapshot()
	for delta in [-1,1.5,true,null,2147483648]:
		check(owner.advance(delta).is_empty() and owner.snapshot()==before,"Invalid time changed weapon group")
	check(owner.fire(Transform3D.IDENTITY,1).is_empty() and owner.snapshot()==before,"Implicit actor permission accepted")
	check(owner.fire(null,true).is_empty() and owner.snapshot()==before,"Invalid firing transform accepted")

func check_atomic(owner: RefCounted, fixture: Dictionary) -> void:
	# First gun is safely at x=0, second would overflow its mount rotation. A
	# successful staged first shot must disappear when the second cannot launch.
	fixture.mounts._ships[0].groups[0][2].position=Vector3(0,0,-100)
	fixture.mounts._ships[0].groups[0][0].position=Vector3(10,0,-100)
	check(configure(owner,fixture),owner.error)
	owner.advance(1)
	var before: Dictionary = owner.snapshot()
	var huge := Transform3D(Basis(Vector3(3e38,0,0),Vector3.UP,Vector3.BACK),Vector3.ZERO)
	check(owner.fire(huge,true).is_empty() and owner.snapshot()==before,"Later mount overflow left an earlier gun fired")
	# Give only the second gun an extreme speed, then overflow its movement.
	fixture.catalogues.tables.items[0].properties[53]=2147483647
	check(configure(owner,fixture),owner.error)
	owner.advance(1)
	check(not owner.fire(Transform3D(Basis.IDENTITY,Vector3(3e38,0,0)),true).is_empty(),owner.error)
	# Source integer speed/time bounds cannot overflow f32 by themselves here;
	# use a valid large finite speed in a staged native owner to exercise the
	# all-gun arithmetic failure boundary without changing source catalogues.
	owner._guns[1].projectiles._slots[0].velocity=Vector3(3e38,0,0)
	before=owner.snapshot()
	check(owner.advance(2).is_empty() and owner.snapshot()==before,"Later motion overflow partially advanced a group")
	fixture.catalogues.tables.items[0].properties[53]=2

func check_profile(content: String, binding_path: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	var mounts := Mounts.new()
	var opening := Opening.new()
	var owner := Primary.new()
	if not library.open(content) or not bindings.open(binding_path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error); return
	if not mounts.open(library,catalogues) or not opening.configure(bindings,catalogues,catalogues.content_id):
		check(false,mounts.error+opening.error); return
	check(owner.configure(bindings,catalogues,mounts,opening.snapshot()),owner.error)
	if owner.snapshot().is_empty(): return
	owner.advance(1)
	var volley: Dictionary = owner.fire(Transform3D.IDENTITY,true)
	check(volley.weapons.size()==2 and volley.weapons[0].slot==1 and volley.weapons[1].slot==0,"Opening source volley order changed")
	check(volley.weapons[0].result.projectile.position==Vector3(142,-98,16) and volley.weapons[1].result.projectile.position==Vector3(-142,-98,16),"Opening source muzzle positions changed")
	for event in volley.weapons:
		check(event.result.projectile.velocity==Vector3(0,0,20),"Opening primary failed source forward aim")
	var advance: Dictionary = owner.advance(381)
	check(advance.weapons[0].result.moved[0].position==Vector3(142,-98,7636),"Owned projectile motion changed")
	var next: Dictionary = owner.fire(Transform3D.IDENTITY,true)
	check(next.weapons[0].result.fired and next.weapons[1].result.fired,"Source primary group did not fire again")
	var impact_mount: int = next.weapons[0].mount_id
	var impact_id: int = next.weapons[0].result.projectile.id
	var before: Dictionary = owner.snapshot()
	check(owner.mark_impact(impact_mount,impact_id),owner.error)
	var impacted: Dictionary = owner.snapshot()
	check(impacted.guns[0].projectiles.slots[1].remaining_ms==Projectiles.HIT_LIFETIME_SENTINEL,"Owned impact lost deferred cleanup")
	check(impacted.guns[0].projectiles.slots[1].position==before.guns[0].projectiles.slots[1].position,"Owned impact moved its projectile")
	check(impacted.guns[1]==before.guns[1],"Owned impact changed another gun with the same local projectile ID")
	check(owner.mark_impact(impact_mount,impact_id),"Retained owned impact cannot contact another target")
	var zero: Dictionary = owner.advance(0)
	check(zero.weapons[0].result.cleared==[impact_id],"Zero-time owner update did not clear the impact")
	var zero_state: Dictionary = owner.snapshot()
	check(zero_state.guns[0].projectiles.slots[1]==null,"Owned impact survived zero-time cleanup")
	for index in impacted.guns.size():
		check(zero_state.guns[index].projectiles.elapsed_ms==impacted.guns[index].projectiles.elapsed_ms,"Zero-time update advanced a gun clock")
		check(zero_state.guns[index].projectiles.slots[0].position==impacted.guns[index].projectiles.slots[0].position and zero_state.guns[index].projectiles.slots[0].remaining_ms==impacted.guns[index].projectiles.slots[0].remaining_ms,"Zero-time update moved or aged a live shot")
	check(not owner.mark_impact(impact_mount,impact_id),"Cleared owned impact retained its handle")
	var cleaned: Dictionary = owner.snapshot()
	check(not owner.mark_impact(-1,impact_id) and owner.snapshot()==cleaned,"Invalid mount changed an owned impact")
	print(library.manifest.profile.edition,": source opening loadout, reverse slot order, fixed mounts and forward volleys verified")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures+=1
		push_error(message)
