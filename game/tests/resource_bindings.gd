extends SceneTree
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0
var directory := ""
const MESH := "resources/data/assets/main/3d/meshes/fixture.aem"
const TEXTURE := "resources/data/assets/main/3d/textures/fixture.aei"

func _initialize() -> void:
	directory = "user://tests/bindings-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	var base := {"content_id": "a".repeat(64), "profile": {"edition": "ios-hd"},
		"ship_table": {"records": 64, "record_bytes": 36}, "languages": {"gb": {"records": 3402}},
		"files": {MESH: {"kind": "mesh"}, TEXTURE: {"kind": "texture"}, "resources/data/bin/ships.bin": {"bytes": 64 * 36}}}
	write_fixture(base)
	var bindings := Bindings.new()
	check(bindings.open(directory, base), bindings.error)
	check(bindings.resolve(17, "mesh") == MESH, "Unique ID did not resolve")
	check(bindings.resolve(17, "texture").is_empty(), "Wrong requested kind accepted")
	check(bindings.resolve(18).is_empty() and "multiple" in bindings.error, "Ambiguous ID resolved")
	check(bindings.resolve(19).is_empty() and "unverified" in bindings.error, "Unknown registration type resolved")
	check(bindings.resolve(20).is_empty() and "absent" in bindings.error, "Absent content resolved")
	check(bindings.resolve(999).is_empty(), "Unknown ID resolved")
	check(bindings.resolve_material(99).get("texture_paths", []) == [TEXTURE, TEXTURE, "", "", "", "", "", ""], "Material texture slots did not resolve")
	check(bindings.material_for_mesh(MESH).get("id") == 99, "Mesh material link did not resolve")
	bindings.records[99] = bindings.records[21]
	check(bindings.resolve_material(99).is_empty() and bindings.resolve(99).is_empty(), "Global ID collision accepted")
	bindings.records.erase(99)
	for identifier in [100, 101, 102, 103]:
		check(bindings.resolve_material(identifier).is_empty(), "Conflicting, ambiguous, missing or wrong-kind texture accepted")
	bindings.records[17][0].material_id = 100
	check(bindings.material_for_mesh(MESH).is_empty(), "Conflicting mesh materials accepted")
	bindings.records[17][0].material_id = 99
	bindings.records[17][0].mesh_flags = 1
	check(bindings.material_for_mesh(MESH).is_empty(), "Unverified mesh flags accepted")
	check(bindings.open(directory, base), bindings.error)
	var wrong_base: Dictionary = base.duplicate(true)
	wrong_base.content_id = "b".repeat(64)
	check(not bindings.open(directory, wrong_base), "Cross-base declarations accepted")
	check(bindings.records.is_empty() and bindings.materials.is_empty() and bindings.binding_id.is_empty(), "Failed open retained declarations")
	check(bindings.open(directory, base), bindings.error)
	var file := FileAccess.open(directory.path_join("registrations.json"), FileAccess.READ_WRITE)
	var byte := file.get_8()
	file.seek(0)
	file.store_8(byte ^ 1)
	file.close()
	check(not bindings.open(directory, base) and "checksum" in bindings.error, "Changed declarations accepted")
	check(bindings.records.is_empty(), "Checksum failure retained content")
	write_fixture(base)
	var header_path := directory.path_join("bindings.json")
	var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(header_path))
	header.source_executable_sha256 = "f".repeat(64)
	file = FileAccess.open(header_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(header))
	file.close()
	check(not bindings.open(directory, base) and "identity" in bindings.error, "Changed executable identity accepted")
	for corruption in ["fractional_texture", "short_slots", "missing_flags"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Malformed material fields accepted: " + corruption)
		check(bindings.materials.is_empty() and bindings.records.is_empty(), "Invalid material retained previous declarations")
	for name in ["registrations.json", "bindings.json"]:
		DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Pass base/bindings argument pairs")
	for index in range(0, args.size() - 1, 2):
		var library := Library.new()
		check(library.open(args[index]), library.error)
		check(bindings.open(args[index + 1], library.manifest), bindings.error)
		if bindings.records.is_empty():
			continue
		var imported: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[index+1].path_join("registrations.json")))
		check(bindings.fast_forward==imported.get("fast_forward",{}),"Optional Fast Forward declaration was lost or retained from another pack")
		check(bindings.resolve(17000, "mesh").ends_with("ship_000_midorian.aem"), "Real ship declaration failed")
		check(bindings.resolve(34000, "texture").ends_with("ship_000_midorian_diffuse.aei"), "Real texture declaration failed")
		var resolved := 0
		var unsupported := 0
		for id in bindings.records:
			if bindings.resolve(id).is_empty(): unsupported += 1
			else: resolved += 1
		print("Resource bindings ", library.manifest.profile.edition, ": ", resolved,
			" resolved; ", unsupported, " unsupported; identity ", bindings.binding_id)
		if not bindings.materials.is_empty():
			var material: Dictionary = bindings.material_for_mesh(bindings.resolve(17000, "mesh"))
			check(material.get("id") == 34200 and material.get("render_type") == 28, "Real ship material failed: " + bindings.error)
			check(material.get("texture_paths", [""])[0].ends_with("ship_000_midorian_diffuse.aei"), "Real source diffuse reference failed")
			var supported_materials := 0
			for id in bindings.materials:
				if not bindings.resolve_material(id).is_empty(): supported_materials += 1
			print("Material descriptors: ", supported_materials, " resolved; ", bindings.materials.size() - supported_materials, " unsupported")
		if not bindings.ship_model_resources.is_empty():
			var expected_count := int(Library.catalogue_layout(library.manifest).ships)
			check(bindings.ship_model_resources.size() == expected_count, "Wrong edition ship table count")
			check(bindings.resolve_ship_model(0).ends_with("ship_000_midorian.aem"), "First catalogue hull lookup failed")
			check(bindings.resolve_ship_model(37).ends_with("v_ship_037_deep_science.aem"), "Expansion catalogue hull lookup failed")
			check(bindings.resolve_ship_model(expected_count).is_empty(), "Cross-edition/out-of-range ship lookup accepted")
			var supported_ships := 0
			for id in bindings.ship_model_resources.size():
				if not bindings.resolve_ship_model(id).is_empty(): supported_ships += 1
			if library.manifest.profile.edition == "mac-full-hd" and expected_count == 64:
				for id in [61, 62, 63]:
					check(bindings.resolve_ship_model(id).get_file().begins_with("ship_%03d_" % id), "Newer Mac hull did not resolve from its own declarations")
			print("Ship table: ", supported_ships, " hull references resolved; ", expected_count - supported_ships, " unsupported")
		if not bindings.texture_variants.is_empty():
			check(bindings.resolve_texture(33136).contains("/high/"), "Mac high hangar texture failed")
			check(bindings.resolve_texture(33136, "low").contains("/low/"), "Mac low hangar texture failed")
			for id in bindings.texture_variants:
				check(not bindings.resolve_texture(id, "high").is_empty() and not bindings.resolve_texture(id, "low").is_empty(), "Verified quality pair failed")
			print("Verified texture quality pairs: ", bindings.texture_variants.size())
	print("Resource binding checks: %d failures" % failures)
	quit(1 if failures else 0)

func write_fixture(base: Dictionary, corruption := "") -> void:
	var rows := []
	for values in [[17, MESH, 4], [17, MESH, 4], [18, MESH, 4], [18, TEXTURE, 2],
		[19, MESH, 6], [20, "resources/data/assets/main/3d/meshes/missing.aem", 4], [21, TEXTURE, 2], [22, TEXTURE, 2]]:
		rows.append({"id": values[0], "resource": values[1], "registration_type": values[2],
			"kind": "mesh" if str(values[1]).ends_with(".aem") else "texture", "source_offset": 100 + rows.size()})
		if values[2] == 4:
			rows[-1]["material_id"] = 99
			rows[-1]["mesh_flags"] = 0
	var materials := []
	for values in [[99, 21], [100, 21], [100, 22], [101, 18], [102, 999], [103, 17]]:
		materials.append({"id": values[0], "render_type": 28, "texture_ids": [values[1], 22, 65535, 65535, 65535, 65535, 65535, 65535],
			"parameter_bits": [0, 3240099840, 0, 0], "source_offset": 300 + materials.size()})
	if corruption == "fractional_texture": materials[0].texture_ids[0] = 21.5
	if corruption == "short_slots": materials[0].texture_ids.pop_back()
	if corruption == "missing_flags": rows[0].erase("mesh_flags")
	var body := JSON.stringify({"schema": 1, "reader": "resource-registration-v2", "registrations": rows, "materials": materials, "diagnostics": {}})
	var digest := body.sha256_text()
	var identity := "gof2-bindings-v1\n%s\n%s\narmv7\n%s\n" % [base.content_id, "e".repeat(64), digest]
	var header := {"schema": 1, "reader": "resource-registration-v2", "architecture": "armv7",
		"base_content_id": base.content_id, "source_executable_sha256": "e".repeat(64), "source_executable_bytes": 1024,
		"records_sha256": digest, "records_bytes": body.to_utf8_buffer().size(), "binding_id": identity.sha256_text()}
	var file := FileAccess.open(directory.path_join("registrations.json"), FileAccess.WRITE)
	file.store_string(body)
	file.close()
	file = FileAccess.open(directory.path_join("bindings.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(header))
	file.close()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
