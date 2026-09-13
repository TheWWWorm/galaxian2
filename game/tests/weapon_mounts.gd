extends SceneTree
const Mounts = preload("res://src/content/weapon_mounts.gd")
const Library = preload("res://src/content/library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Weapons = preload("res://src/simulation/weapon_loadout.gd")
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Opening = preload("res://src/simulation/opening_loadout.gd")
var failures := 0

class FixtureLibrary extends RefCounted:
	var error := ""
	var data: PackedByteArray
	var manifest := {"content_id": "a".repeat(64), "files": {
		"resources/data/bin/weapons_hd.bin": {"sha256": "b".repeat(64)}}}
	func read_resource(_path: String, _limit: int) -> PackedByteArray: return data

func _initialize() -> void:
	check_decoder()
	check_mount_firing()
	var args := OS.get_cmdline_user_args()
	check(args.size() % 3 == 0, "Pass content/bindings/visuals triples")
	for i in range(0, args.size() - 2, 3): check_profile(args[i], args[i + 1])
	print("Weapon mount checks: %d failures" % failures)
	quit(1 if failures else 0)

func fixture() -> PackedByteArray:
	var bytes := PackedByteArray()
	for value in [0, 4, 0, -142, 84, -98, 0, 142, 84, -98,
		1, 0, -455, -138, 3, -32768, -32768, 32767]:
		bytes.append(value & 255)
		bytes.append((value >> 8) & 255)
	bytes.append_array(PackedFloat32Array([0.25, 0.5, 0.75]).to_byte_array())
	return bytes

func check_decoder() -> void:
	var mounts := Mounts.new()
	var bytes := fixture()
	var decoded: Dictionary = mounts.decode(bytes, 1)
	check(decoded.size() == 1, mounts.error)
	if decoded.is_empty(): return
	var groups: Array = decoded[0].groups
	check(groups[0][0].position == Vector3(-142,-98,-84) and groups[0][1].position == Vector3(142,-98,-84), "Mount order or signed axes changed")
	check(groups[1][0].position == Vector3(0,-138,455) and groups[2].is_empty(), "Category separation changed")
	check(groups[3][0].position == Vector3(-32768,32767,32768) and groups[3][0].additional_vector == Vector3(0.25,0.75,0.5), "Auxiliary vector axes or signed-short edge changed")
	check(decoded[0].source_bytes == bytes.size() and groups[3][0].source_offset == 28 and groups[3][0].source_bytes == 20, "Attachment provenance changed")
	for length in bytes.size():
		check(mounts.decode(bytes.slice(0,length),1).is_empty(), "Truncated record accepted at %d" % length)
	for mutation in ["duplicate", "trailing", "ship", "category", "negative_count", "large_count", "nan"]:
		var broken := bytes.duplicate()
		match mutation:
			"duplicate": broken.append_array(bytes)
			"trailing": broken.append(0)
			"ship": broken.encode_u16(0,1)
			"category": broken.encode_u16(4,4)
			"negative_count": broken.encode_u16(2,65535)
			"large_count": broken.encode_u16(2,1025)
			"nan": broken.encode_float(36,NAN)
		check(mounts.decode(broken,1).is_empty() and not mounts.error.is_empty(), "Malformed table accepted: " + mutation)
	var library := FixtureLibrary.new()
	library.data = bytes
	var catalogues := Catalogues.new()
	catalogues.content_id = library.manifest.content_id
	catalogues.tables = {"ships": [{}]}
	check(mounts.open(library,catalogues), mounts.error)
	var record: Dictionary = mounts.resolve(0,0,1)
	check(record.get("position") == Vector3(142,-98,-84), mounts.error)
	record.position = Vector3.ZERO
	var snap: Dictionary = mounts.snapshot()
	snap.ships[0].groups[0].clear()
	check(mounts.resolve(0,0,1).position == Vector3(142,-98,-84), "Detached mount results mutated source data")
	for request in [[1,0,0],[0,2,0],[0,3,0],[0,0,2],[0,0,-1]]:
		check(mounts.resolve(request[0],request[1],request[2]).is_empty(), "Missing mount was invented")
	catalogues.content_id = "c".repeat(64)
	check(not mounts.open(library,catalogues) and mounts.snapshot().is_empty(), "Cross-edition or failed open retained mounts")

func check_mount_firing() -> void:
	var simulation := Projectiles.new()
	var weapon := {"base_content_id":"a".repeat(64),"binding_id":"b".repeat(64),"item_id":2,
		"category":0,"kind":0,"damage":6,"interval_ms":380,"lifetime_ms":2000,
		"speed_units_per_millisecond":20.0,"launch_mode":"ordinary","projectile_capacity":20}
	check(simulation.configure(weapon), simulation.error)
	var mount := {"base_content_id": weapon.base_content_id, "category":0,
		"ship_id":10, "slot":0, "position":Vector3(-142,-98,-84)}
	var pose := Transform3D(Basis(Vector3(0,0,-1),Vector3.UP,Vector3.RIGHT), Vector3(1000,2000,3000))
	check(simulation.fire_from_mount(mount,pose,Vector3.RIGHT,true).get("reason") == "interval", "Mounted shot bypassed interval")
	simulation.advance(1)
	var before: Dictionary = simulation.snapshot()
	check(simulation.fire_from_mount(mount,pose,Vector3.RIGHT,false).get("reason") == "permission" and simulation.snapshot() == before, "Mounted shot bypassed permission")
	for field in ["base_content_id", "category", "slot", "position"]:
		var bad := mount.duplicate()
		bad[field] = {"base_content_id":"c".repeat(64),"category":1,"slot":-1,"position":Vector3(NAN,0,0)}[field]
		check(simulation.fire_from_mount(bad,pose,Vector3.RIGHT,true).is_empty() and simulation.snapshot() == before, "Invalid mount mutated projectile state: " + field)
	var overflow_pose := Transform3D(Basis(Vector3(3e38,0,0),Vector3.UP,Vector3.BACK),Vector3.ZERO)
	check(simulation.fire_from_mount(mount,overflow_pose,Vector3.RIGHT,true).is_empty() and simulation.snapshot() == before, "Overflowed mount changed state")
	var shot: Dictionary = simulation.fire_from_mount(mount,pose,Vector3.RIGHT,true)
	check(shot.get("fired",false), simulation.error)
	if shot.get("fired",false):
		check(shot.projectile.position == Vector3(1016,1902,3142), "Mount rotation, local Z shift or translation changed")
		check(shot.projectile.velocity == Vector3(20,0,0), "Mounted shot changed world aim")
	check(Projectiles.mount_dot(Vector3(16777216,1,-16777216),Vector3.ONE)==0.0, "Mount dot product lost ordered binary32 rounding")

func check_profile(content_path: String, binding_path: String) -> void:
	var library := Library.new()
	var catalogues := Catalogues.new()
	var mounts := Mounts.new()
	var bindings := Bindings.new()
	var weapons := Weapons.new()
	if not library.open(content_path): check(false,library.error); return
	if not catalogues.open(library): check(false,catalogues.error); return
	if not mounts.open(library,catalogues): check(false,mounts.error); return
	if not bindings.open(binding_path,library.manifest): check(false,bindings.error); return
	if not weapons.configure(bindings,catalogues,library.manifest.content_id): check(false,weapons.error); return
	var edition: String = library.manifest.profile.edition
	var snap: Dictionary = mounts.snapshot()
	check(snap.ships.size() == (59 if edition == "ios-hd" else 56), "Source attachment coverage changed")
	check(snap.ships.has(63) == (edition == "ios-hd"), "Edition-specific mounts changed")
	check(mounts.resolve(52,0,0).position == (Vector3(594,-27,-81) if edition == "ios-hd" else Vector3(-893,-27,-170)), "Edition-specific mount order was replaced")
	var opening := Opening.new()
	if not opening.configure(bindings,catalogues,library.manifest.content_id): check(false,opening.error); return
	var seed: Dictionary = opening.snapshot()
	var positions := []
	for equipment in seed.slots:
		if equipment == null or equipment.category != 0: continue
		var primary: Dictionary = weapons.resolve(equipment.item_id,seed.equipment_ids)
		var mount: Dictionary = mounts.resolve(seed.ship_id,equipment.category,equipment.slot)
		var simulation := Projectiles.new()
		check(simulation.configure(primary), simulation.error)
		simulation.advance(1)
		var shot: Dictionary = simulation.fire_from_mount(mount,Transform3D.IDENTITY,Vector3.BACK,true)
		check(shot.get("fired",false), simulation.error)
		if shot.get("fired",false): positions.append(shot.projectile.position)
	check(positions == [Vector3(-142,-98,16),Vector3(142,-98,16)], "Opening duplicate primaries did not use distinct authored slots")
	check(mounts.resolve(10,1,0).position == Vector3(0,-138,455), "Opening secondary mount changed")
	check(mounts.resolve(10,0,2).is_empty() and mounts.resolve(13,0,0).is_empty(), "Absent source mount was synthesized")
	print("Verified mounts for ",edition,": ",snap.ships.size()," ship records; opening muzzle positions ",positions)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
