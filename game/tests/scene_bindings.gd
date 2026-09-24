extends SceneTree
const RefreshFixture = preload("res://tests/lod_refresh_fixture.gd")
const LodFixture = preload("res://tests/ship_lod_fixture.gd")
const ProjectionFixture = preload("res://tests/flight_projection_fixture.gd")
const OpeningClockFixture = preload("res://tests/opening_clock_fixture.gd")
const DriftFixture = preload("res://tests/opening_drift_fixture.gd")
const FollowFixture = preload("res://tests/camera_follow_fixture.gd")
const CameraFixture = preload("res://tests/opening_camera_fixture.gd")
const StagingFixture = preload("res://tests/opening_staging_fixture.gd")
const ActorFixture = preload("res://tests/opening_actor_fixture.gd")
const LayerFixture = preload("res://tests/portrait_layer_fixture.gd")
const ImageFixture = preload("res://tests/image_region_fixture.gd")
const SpeakerFixture = preload("res://tests/speaker_fixture.gd")
const PortraitFixture = preload("res://tests/portrait_fixture.gd")
const FontFixture = preload("res://tests/font_fixture.gd")
const Vehicle = preload("res://src/content/vehicle_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const HIGH := "resources/data/assets/main/3d/textures/high/dx5/hangars/example.aei"
const LOW := "resources/data/assets/main/3d/textures/low/dx5/hangars/example.aei"
const MESH := "resources/data/assets/main/3d/meshes/ships/example.aem"
var failures := 0
var directory := ""

func _initialize() -> void:
	directory = "user://tests/scene-bindings-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	var base := {"content_id": "a".repeat(64), "profile": {"edition": "mac-full-hd"},
		"ship_table": {"records": 61, "record_bytes": 36}, "languages": {"gb": {"records": 3371}}, "files": {
		HIGH: {"kind": "texture", "sha256": "b".repeat(64)}, LOW: {"kind": "texture", "sha256": "c".repeat(64)}, MESH: {"kind": "mesh"},
		"resources/data/bin/ships.bin": {"bytes": 61 * 36}}}
	var bindings := Bindings.new()
	write_fixture(base)
	check(bindings.open(directory, base), bindings.error)
	check(bindings.resolve(17).is_empty(), "Generic ambiguous ID resolved without a quality preference")
	check(bindings.resolve_texture(17) == HIGH and bindings.resolve_texture(17, "low") == LOW, "Texture quality selection failed")
	check(bindings.resolve_texture(17, "unknown").is_empty(), "Invalid quality accepted")
	check(bindings.resolve_material(99, "low").get("texture_paths", [""])[0] == LOW, "Material did not honor texture quality")
	check(bindings.resolve_ship_model(0) == MESH and bindings.resolve_ship_model(59) == MESH, "Catalogue-indexed hull lookup failed")
	check(bindings.resolve_ship_model(60).is_empty(), "Missing hull resource was invented")
	check(bindings.resolve_ship_model(61).is_empty() and bindings.resolve_ship_model(-1).is_empty(), "Invalid edition ship ID accepted")
	for corruption in ["hash", "different_asset", "parameter", "third_path", "scale", "short_table", "table_extent", "sentinel", "missing_reader"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Malformed scene data accepted: " + corruption)
		check(bindings.records.is_empty() and bindings.texture_variants.is_empty() and bindings.ship_model_resources.is_empty(), "Failed open retained scene data")
	write_fixture(base, "hangar_valid")
	check(bindings.open(directory, base) and not bindings.hangars.is_empty(), "Valid v4 hangars rejected: " + bindings.error)
	for corruption in ["hangar_absent", "hangar_extent", "hangar_selector", "hangar_row", "hangar_duplicate"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v4 hangars accepted: " + corruption)
		check(bindings.hangars.is_empty() and bindings.records.is_empty(), "Failed v4 open retained content")
	write_fixture(base, "placement_valid")
	check(bindings.open(directory, base), "Valid v5 placement rejected: " + bindings.error)
	check(bindings.resolve_hangar_ship(0).get("position") == Vector3(0, -35, 0), "Signed source placement lost")
	check(bindings.resolve_hangar_ship(60).is_empty() and bindings.resolve_hangar_ship(61).is_empty(), "Missing or out-of-range placed hull invented")
	for corruption in ["placement_absent", "placement_count", "placement_fraction", "placement_extent", "placement_reader"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v5 placement accepted: " + corruption)
		check(bindings.ship_placement.is_empty() and bindings.hangars.is_empty(), "Failed v5 open retained placement")
	write_fixture(base, "lights_valid")
	check(bindings.open(directory, base), "Valid v6 lights rejected: " + bindings.error)
	check(bindings.resolve_hangar_ship(0).get("lights", []).size() == 2, "Distinct source slots using one resource were collapsed")
	for corruption in ["lights_absent", "lights_count", "lights_slot", "lights_id", "lights_extent"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v6 light data accepted: " + corruption)
		check(bindings.ship_lights.is_empty() and bindings.ship_placement.is_empty(), "Failed v6 open retained ship data")
	write_fixture(base, "cruise_valid")
	check(bindings.open(directory, base) and not bindings.cruise.is_empty(), "Valid v7 cruise rejected: " + bindings.error)
	for corruption in ["cruise_absent", "cruise_rate", "cruise_axis", "cruise_extent", "cruise_duplicate", "cruise_reader"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v7 cruise accepted: " + corruption)
		check(bindings.cruise.is_empty() and bindings.records.is_empty() and bindings.ship_lights.is_empty(), "Failed v7 open retained content")
	write_fixture(base, "cruise_empty")
	check(bindings.open(directory, base) and bindings.cruise.is_empty(), "Unknown cruise must preserve asset-only support")
	write_fixture(base, "lights_valid")
	check(bindings.open(directory, base) and bindings.cruise.is_empty(), "Older packs must not invent cruise definitions")
	write_fixture(base, "rotation_valid")
	check(bindings.open(directory, base) and not bindings.manual_rotation.is_empty(), "Valid v8 rotation rejected: " + bindings.error)
	for corruption in ["rotation_absent", "rotation_rate", "rotation_order", "rotation_extent", "rotation_reader"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v8 rotation accepted: " + corruption)
		check(bindings.manual_rotation.is_empty() and bindings.cruise.is_empty() and bindings.records.is_empty(), "Failed v8 open retained motion state")
	write_fixture(base, "rotation_empty")
	check(bindings.open(directory, base) and bindings.manual_rotation.is_empty(), "Unknown rotation must preserve earlier support")
	write_fixture(base, "cruise_valid")
	check(bindings.open(directory, base) and bindings.manual_rotation.is_empty(), "Older packs must not invent rotation")
	write_fixture(base, "response_valid")
	check(bindings.open(directory, base) and not bindings.pilot_response.is_empty(), "Valid v9 response rejected: " + bindings.error)
	for corruption in ["response_absent", "response_gain", "response_curve", "response_divisor", "response_extent", "response_reader", "response_provenance"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v9 response accepted: " + corruption)
		check(bindings.pilot_response.is_empty() and bindings.manual_rotation.is_empty() and bindings.cruise.is_empty() and bindings.records.is_empty(), "Failed v9 open retained pilot state")
	write_fixture(base, "response_empty")
	check(bindings.open(directory, base) and bindings.pilot_response.is_empty() and not bindings.manual_rotation.is_empty(), "Unknown response must preserve earlier support")
	write_fixture(base, "rotation_valid")
	check(bindings.open(directory, base) and bindings.pilot_response.is_empty(), "Older packs must not invent pilot response")
	write_fixture(base, "vehicle_valid")
	check(bindings.open(directory, base) and not bindings.vehicle_response.is_empty(), "Valid v10 vehicle data rejected: " + bindings.error)
	for corruption in ["vehicle_absent", "vehicle_type", "vehicle_divisor", "vehicle_rule", "vehicle_extent", "vehicle_reader", "vehicle_provenance"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v10 vehicle data accepted: " + corruption)
		check(bindings.vehicle_response.is_empty() and bindings.pilot_response.is_empty() and bindings.records.is_empty(), "Failed v10 open retained vehicle state")
	write_fixture(base, "vehicle_empty")
	check(bindings.open(directory, base) and bindings.vehicle_response.is_empty() and not bindings.pilot_response.is_empty(), "Unknown vehicle data must preserve earlier support")
	write_fixture(base, "response_valid")
	check(bindings.open(directory, base) and bindings.vehicle_response.is_empty(), "Older packs must not invent vehicle definitions")
	write_fixture(base, "clock_valid")
	check(bindings.open(directory, base) and not bindings.frame_clock.is_empty(), "Valid v11 clock rejected: " + bindings.error)
	for corruption in ["clock_absent", "clock_cap", "clock_unit", "clock_extent", "clock_reader", "clock_provenance"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v11 clock accepted: " + corruption)
		check(bindings.frame_clock.is_empty() and bindings.vehicle_response.is_empty() and bindings.records.is_empty(), "Failed v11 open retained flight state")
	write_fixture(base, "clock_empty")
	check(bindings.open(directory, base) and bindings.frame_clock.is_empty() and not bindings.vehicle_response.is_empty(), "Unknown clock must preserve earlier support")
	write_fixture(base, "vehicle_valid")
	check(bindings.open(directory, base) and bindings.frame_clock.is_empty(), "Older packs must not invent timing policy")
	write_fixture(base, "opening_valid")
	check(bindings.open(directory, base) and not bindings.opening_loadout.is_empty(), "Valid v12 opening rejected: " + bindings.error)
	for corruption in ["opening_absent", "opening_type", "opening_quantity", "opening_slot", "opening_category", "opening_extent", "opening_reader", "opening_provenance", "opening_vehicle"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v12 opening accepted: " + corruption)
		check(bindings.opening_loadout.is_empty() and bindings.frame_clock.is_empty() and bindings.records.is_empty(), "Failed v12 open retained state")
	write_fixture(base, "opening_empty")
	check(bindings.open(directory, base) and bindings.opening_loadout.is_empty() and not bindings.frame_clock.is_empty(), "Unknown opening must preserve flight support")
	write_fixture(base, "clock_valid")
	check(bindings.open(directory, base) and bindings.opening_loadout.is_empty(), "Older packs invented an opening loadout")
	write_fixture(base, "radio_valid")
	check(bindings.open(directory, base) and not bindings.opening_dialogue.is_empty(), "Valid v13 radio rejected: " + bindings.error)
	for corruption in ["radio_absent", "radio_count", "radio_condition", "radio_dependency", "radio_timing", "radio_extent", "radio_provenance"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v13 radio accepted: " + corruption)
		check(bindings.opening_dialogue.is_empty() and bindings.records.is_empty(), "Failed radio open retained state")
	write_fixture(base, "radio_empty")
	check(bindings.open(directory, base) and bindings.opening_dialogue.is_empty() and not bindings.opening_loadout.is_empty(), "Unknown radio lost prior support")
	write_fixture(base, "opening_valid")
	check(bindings.open(directory, base) and bindings.opening_dialogue.is_empty(), "Old pack invented radio")
	write_fixture(base, "aliases_valid")
	check(bindings.open(directory, base) and not bindings.text_aliases.is_empty(), "Valid v14 aliases rejected: " + bindings.error)
	for corruption in ["aliases_absent", "aliases_count", "aliases_duplicate", "aliases_control", "aliases_surrogate", "aliases_extent", "aliases_provenance"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v14 aliases accepted: " + corruption)
		check(bindings.text_aliases.is_empty() and bindings.opening_dialogue.is_empty() and bindings.records.is_empty(), "Failed alias open retained state")
	write_fixture(base, "aliases_empty")
	check(bindings.open(directory, base) and bindings.text_aliases.is_empty() and not bindings.opening_dialogue.is_empty(), "Unknown aliases lost prior support")
	write_fixture(base, "radio_valid")
	check(bindings.open(directory, base) and bindings.text_aliases.is_empty(), "Older packs invented aliases")
	write_fixture(base, "fonts_valid")
	check(bindings.open(directory, base) and not bindings.font_bindings.is_empty(), "Valid v15 fonts rejected: " + bindings.error)
	check(bindings.resolve_font("ak", 1).get("font_id") == 504, "Native font lookup failed")
	for corruption in ["fonts_absent", "fonts_duplicate", "fonts_language", "fonts_spacing", "fonts_atlas", "fonts_order", "fonts_extent", "fonts_provenance"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base), "Invalid v15 fonts accepted: " + corruption)
		check(bindings.font_bindings.is_empty() and bindings.text_aliases.is_empty() and bindings.records.is_empty(), "Failed font open retained state")
	write_fixture(base, "fonts_empty")
	check(bindings.open(directory, base) and bindings.font_bindings.is_empty() and not bindings.text_aliases.is_empty(), "Unknown fonts lost prior support")
	write_fixture(base, "aliases_valid")
	check(bindings.open(directory, base) and bindings.font_bindings.is_empty(), "Older pack invented fonts")
	write_fixture(base, "portraits_valid")
	check(bindings.open(directory, base) and bindings.portrait_textures.get("rows", []).size() == 152, "Valid v16 portrait declarations rejected: " + bindings.error)
	for corruption in ["portraits_absent", "portraits_duplicate", "portraits_variant", "portraits_extent"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.portrait_textures.is_empty() and bindings.records.is_empty(), "Invalid portrait pack retained state: " + corruption)
	write_fixture(base, "portraits_empty")
	check(bindings.open(directory, base) and bindings.portrait_textures.is_empty() and not bindings.text_aliases.is_empty(), "Unknown portrait scope lost prior content")
	write_fixture(base, "fonts_valid")
	check(bindings.open(directory, base) and bindings.portrait_textures.is_empty(), "Older pack invented portraits")
	write_fixture(base, "speakers_valid")
	check(bindings.open(directory, base) and bindings.speaker_bindings.get("portraits", []).size() == 5, "Valid v17 speaker declarations rejected: " + bindings.error)
	for corruption in ["speakers_absent", "speakers_duplicate", "speakers_extent", "speakers_invented"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.speaker_bindings.is_empty() and bindings.records.is_empty(), "Invalid speaker pack retained state: " + corruption)
	write_fixture(base, "speakers_empty")
	check(bindings.open(directory, base) and bindings.speaker_bindings.is_empty() and not bindings.text_aliases.is_empty(), "Unknown speaker scope lost earlier support")
	write_fixture(base, "portraits_valid")
	check(bindings.open(directory, base) and bindings.speaker_bindings.is_empty(), "Older pack invented speakers")
	write_fixture(base, "images_valid")
	check(bindings.open(directory, base) and bindings.image_regions.get("records", []).size() == 3, "Valid v18 image aliases rejected: " + bindings.error)
	for corruption in ["images_absent", "images_extent", "images_range"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.image_regions.is_empty() and bindings.records.is_empty(), "Invalid image pack retained state: " + corruption)
	write_fixture(base, "images_empty")
	check(bindings.open(directory, base) and bindings.image_regions.is_empty(), "Unknown image scope rejected")
	write_fixture(base, "speakers_valid")
	check(bindings.open(directory, base) and bindings.image_regions.is_empty(), "Older pack invented image aliases")
	write_fixture(base, "layers_valid")
	check(bindings.open(directory, base) and bindings.portrait_layers.get("part_bases", []).size() == 13, "Valid v19 portrait placements rejected: " + bindings.error)
	for corruption in ["layers_absent", "layers_extent", "layers_order", "layers_anchor"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.portrait_layers.is_empty() and bindings.records.is_empty(), "Invalid portrait layer pack retained state: " + corruption)
	write_fixture(base, "layers_empty")
	check(bindings.open(directory, base) and bindings.portrait_layers.is_empty(), "Unknown layer scope rejected")
	write_fixture(base, "images_valid")
	check(bindings.open(directory, base) and bindings.portrait_layers.is_empty(), "Older pack invented portrait placements")
	write_fixture(base,"refresh_valid")
	check(bindings.open(directory,base) and not bindings.lod_refresh.is_empty(),"Valid v28 refresh rejected: "+bindings.error)
	for corruption in ["refresh_absent","refresh_extent","refresh_overlap","refresh_seed","refresh_threshold","refresh_reset","refresh_forced"]:
		write_fixture(base,corruption)
		check(not bindings.open(directory,base) and bindings.lod_refresh.is_empty() and bindings.records.is_empty(),"Invalid v28 pack retained data: "+corruption)
	write_fixture(base,"refresh_empty")
	check(bindings.open(directory,base) and bindings.lod_refresh.is_empty(),"Empty refresh scope rejected")
	write_fixture(base,"lod_valid")
	check(bindings.open(directory,base) and bindings.lod_refresh.is_empty(),"Older pack invented refresh declarations")
	write_fixture(base, "lod_valid")
	check(bindings.open(directory,base) and not bindings.ship_lod.is_empty(),"Valid v27 LOD rejected: "+bindings.error)
	check(bindings.resolve_ship_detail(0).get("levels",[]).size()==3,"Resolved synthetic LOD assembly lost levels")
	for corruption in ["lod_absent","lod_count","lod_gap","lod_extent","lod_distance","lod_factor"]:
		write_fixture(base,corruption)
		check(not bindings.open(directory,base) and bindings.ship_lod.is_empty() and bindings.records.is_empty(),"Invalid v27 pack retained data: "+corruption)
	write_fixture(base,"lod_empty")
	check(bindings.open(directory,base) and bindings.ship_lod.is_empty(),"Empty LOD scope rejected")
	write_fixture(base,"openingtime_valid")
	check(bindings.open(directory,base) and bindings.ship_lod.is_empty(),"Older pack invented LOD declarations")
	write_fixture(base, "openingtime_valid")
	check(bindings.open(directory, base) and not bindings.opening_clock.is_empty(), "Valid v26 clock rejected: " + bindings.error)
	for corruption in ["openingtime_absent", "openingtime_extent", "openingtime_seed", "openingtime_order"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.opening_clock.is_empty() and bindings.records.is_empty(), "Invalid opening clock retained state: " + corruption)
	write_fixture(base, "openingtime_empty")
	check(bindings.open(directory, base) and bindings.opening_clock.is_empty(), "Unknown clock scope rejected")
	write_fixture(base, "projection_valid")
	check(bindings.open(directory, base) and bindings.opening_clock.is_empty(), "Older pack invented clock declarations")
	write_fixture(base, "projection_valid")
	check(bindings.open(directory, base) and not bindings.flight_projection.is_empty(), "Valid v25 projection rejected: " + bindings.error)
	for corruption in ["projection_absent", "projection_extent", "projection_fov", "projection_far"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.flight_projection.is_empty() and bindings.records.is_empty(), "Invalid projection retained state: " + corruption)
	write_fixture(base, "projection_empty")
	check(bindings.open(directory, base) and bindings.flight_projection.is_empty(), "Unknown projection scope rejected")
	write_fixture(base, "drift_valid")
	check(bindings.open(directory, base) and bindings.flight_projection.is_empty(), "Older pack invented projection declarations")
	write_fixture(base, "drift_valid")
	check(bindings.open(directory, base) and not bindings.opening_drift.is_empty(), "Valid v24 drift rejected: " + bindings.error)
	for corruption in ["drift_absent", "drift_extent", "drift_rate", "drift_ids"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.opening_drift.is_empty() and bindings.records.is_empty(), "Invalid drift retained state: " + corruption)
	write_fixture(base, "drift_empty")
	check(bindings.open(directory, base) and bindings.opening_drift.is_empty(), "Unknown drift scope rejected")
	write_fixture(base, "follow_valid")
	check(bindings.open(directory, base) and bindings.opening_drift.is_empty(), "Older pack invented drift declarations")
	write_fixture(base, "follow_valid")
	check(bindings.open(directory, base) and not bindings.camera_follow.is_empty(), "Valid v23 follow rejected: " + bindings.error)
	for corruption in ["follow_absent", "follow_extent", "follow_matrix", "follow_rate"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.camera_follow.is_empty() and bindings.records.is_empty(), "Invalid follow retained state: " + corruption)
	write_fixture(base, "follow_empty")
	check(bindings.open(directory, base) and bindings.camera_follow.is_empty(), "Unknown follow scope rejected")
	write_fixture(base, "camera_valid")
	check(bindings.open(directory, base) and bindings.camera_follow.is_empty(), "Older pack invented follow declarations")
	write_fixture(base, "camera_valid")
	check(bindings.open(directory, base) and not bindings.opening_camera.is_empty(), "Valid v22 camera rejected: " + bindings.error)
	for corruption in ["camera_absent", "camera_extent", "camera_order", "camera_type"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.opening_camera.is_empty() and bindings.records.is_empty(), "Invalid camera retained state: " + corruption)
	write_fixture(base, "camera_empty")
	check(bindings.open(directory, base) and bindings.opening_camera.is_empty(), "Unknown camera scope rejected")
	write_fixture(base, "staging_valid")
	check(bindings.open(directory, base) and bindings.opening_camera.is_empty(), "Older pack invented camera declarations")
	write_fixture(base, "staging_valid")
	check(bindings.open(directory, base) and not bindings.opening_staging.is_empty(), "Valid v21 staging rejected: " + bindings.error)
	for corruption in ["staging_absent", "staging_extent", "staging_axes", "staging_gate"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.opening_staging.is_empty() and bindings.records.is_empty(), "Invalid staging retained state: " + corruption)
	write_fixture(base, "staging_empty")
	check(bindings.open(directory, base) and bindings.opening_staging.is_empty(), "Unknown staging scope rejected")
	write_fixture(base, "actors_valid")
	check(bindings.open(directory, base) and bindings.opening_staging.is_empty(), "Older pack invented staging")
	write_fixture(base, "actors_valid")
	check(bindings.open(directory, base) and bindings.opening_actors.get("actors", []).size() == 2, "Valid v20 actor declarations rejected: " + bindings.error)
	for corruption in ["actors_absent", "actors_extent", "actors_id", "actors_hull"]:
		write_fixture(base, corruption)
		check(not bindings.open(directory, base) and bindings.opening_actors.is_empty() and bindings.records.is_empty(), "Invalid actor pack retained state: " + corruption)
	write_fixture(base, "actors_empty")
	check(bindings.open(directory, base) and bindings.opening_actors.is_empty(), "Unknown actor scope rejected")
	write_fixture(base, "layers_valid")
	check(bindings.open(directory, base) and bindings.opening_actors.is_empty(), "Older pack invented actors")
	for name in ["bindings.json", "registrations.json"]:
		DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("Scene binding checks: %d failures" % failures)
	quit(1 if failures else 0)

func write_fixture(base: Dictionary, corruption := "") -> void:
	var rows := [
		{"id": 17, "kind": "texture", "resource": HIGH, "registration_type": 2, "texture_parameter_bits": 0, "source_offset": 100},
		{"id": 17, "kind": "texture", "resource": LOW, "registration_type": 2, "texture_parameter_bits": 0, "source_offset": 200},
		{"id": 18, "kind": "mesh", "resource": MESH, "registration_type": 4, "source_offset": 300}]
	var variant := {"id": 17, "high": HIGH, "low": LOW, "high_sha256": "b".repeat(64), "low_sha256": "c".repeat(64), "high_size": [4, 4], "low_size": [2, 2]}
	var ship_ids := []
	ship_ids.resize(61)
	ship_ids.fill(18)
	ship_ids[60] = 999
	var models := {"resource_ids": ship_ids, "table_offsets": [500], "index_reader_offsets": [800]}
	match corruption:
		"hash": variant.high_sha256 = "f".repeat(64)
		"different_asset": variant.low = LOW.replace("example", "other")
		"parameter": rows[1].texture_parameter_bits = 1
		"third_path": rows.append(dict_copy(rows[1], "resource", LOW.replace("example", "other")))
		"scale": variant.high_size = [4, 2]
		"short_table": ship_ids.pop_back()
		"table_extent": models.table_offsets = [1000]
		"sentinel": ship_ids[0] = 65535
		"missing_reader": models.index_reader_offsets = []
	var reader := "resource-registration-v4" if corruption.begins_with("hangar_") else "resource-registration-v3"
	if corruption.begins_with("placement_"): reader = "resource-registration-v5"
	if corruption.begins_with("lights_"): reader = "resource-registration-v6"
	if corruption.begins_with("cruise_"): reader = "resource-registration-v7"
	if corruption.begins_with("rotation_"): reader = "resource-registration-v8"
	if corruption.begins_with("response_"): reader = "resource-registration-v9"
	if corruption.begins_with("vehicle_"): reader = "resource-registration-v10"
	if corruption.begins_with("clock_"): reader = "resource-registration-v11"
	if corruption.begins_with("opening_"): reader = "resource-registration-v12"
	if corruption.begins_with("radio_"): reader = "resource-registration-v13"
	if corruption.begins_with("aliases_"): reader = "resource-registration-v14"
	if corruption.begins_with("fonts_"): reader = "resource-registration-v15"
	if corruption.begins_with("portraits_"): reader = "resource-registration-v16"
	if corruption.begins_with("speakers_"): reader = "resource-registration-v17"
	if corruption.begins_with("images_"): reader = "resource-registration-v18"
	if corruption.begins_with("layers_"): reader = "resource-registration-v19"
	if corruption.begins_with("actors_"): reader = "resource-registration-v20"
	if corruption.begins_with("refresh_"): reader = "resource-registration-v28"
	if corruption.begins_with("lod_"): reader = "resource-registration-v27"
	if corruption.begins_with("openingtime_"): reader = "resource-registration-v26"
	if corruption.begins_with("projection_"): reader = "resource-registration-v25"
	if corruption.begins_with("drift_"): reader = "resource-registration-v24"
	if corruption.begins_with("follow_"): reader = "resource-registration-v23"
	if corruption.begins_with("camera_"): reader = "resource-registration-v22"
	if corruption.begins_with("staging_"): reader = "resource-registration-v21"
	var hangars := {"rows": [], "rotation_y": 1.25, "system_field": 2,
		"station_overrides": [{"station_id": 0, "row": 0}, {"station_id": 1, "row": 9}],
		"provenance": [{"offset": 0, "bytes": 160}, {"offset": 160, "bytes": 16}, {"offset": 176, "bytes": 16}, {"offset": 200, "bytes": 700}]}
	for i in 10:
		hangars.rows.append({"resource_ids": [18 if i == 0 else -1, -1, -1, -1], "extra_resource_ids": []})
	match corruption:
		"hangar_extent": hangars.provenance[0].offset = 1020
		"hangar_selector": hangars.system_field = 7
		"hangar_row": hangars.rows[0].resource_ids = [18]
		"hangar_duplicate": hangars.station_overrides[1] = hangars.station_overrides[0]
	var payload := {"schema": 1, "reader": reader, "registrations": rows,
		"materials": [{"id": 99, "texture_ids": [17, 65535, 65535, 65535, 65535, 65535, 65535, 65535],
			"render_type": 0, "parameter_bits": [0, 0, 0, 0], "source_offset": 400}],
		"texture_variants": [variant], "ship_models": models, "hangars": hangars, "diagnostics": {}}
	if corruption == "hangar_absent": payload.erase("hangars")
	var y_positions := []
	y_positions.resize(61)
	y_positions.fill(-35)
	var placement := {"y_positions": y_positions, "provenance": [{"offset": 0, "bytes": 244}, {"offset": 500, "bytes": 123}, {"offset": 800, "bytes": 8}]}
	match corruption:
		"placement_count": y_positions.pop_back()
		"placement_fraction": y_positions[0] = 0.5
		"placement_extent": placement.provenance[0].offset = 1020
		"placement_reader": placement.provenance[1].bytes = 200
	if corruption != "placement_absent": payload.ship_placement = placement
	var light_rows := []
	for i in 61: light_rows.append([18, 18])
	var lights := {"resource_ids": light_rows, "provenance": [{"offset": 0, "bytes": 35}, {"offset": 100, "bytes": 122}, {"offset": 300, "bytes": 119}, {"offset": 500, "bytes": 122}, {"offset": 700, "bytes": 91}]}
	match corruption:
		"lights_count": light_rows.pop_back()
		"lights_slot": light_rows[0] = [18]
		"lights_id": light_rows[0][0] = 18.5
		"lights_extent": lights.provenance[0].offset = 1020
	if corruption != "lights_absent": payload.ship_lights = lights
	var cruise := {"speed_units_per_millisecond": 3.5, "forward_axis": [0, 0, 1], "provenance": []}
	for i in 5: cruise.provenance.append({"offset": 100 * i, "bytes": [27, 23, 40, 42, 27][i]})
	match corruption:
		"cruise_rate": cruise.speed_units_per_millisecond = -1
		"cruise_axis": cruise.forward_axis = [0, 0, -1]
		"cruise_extent": cruise.provenance[4].offset = 1020
		"cruise_duplicate": cruise.provenance[4].offset = cruise.provenance[0].offset
		"cruise_reader": cruise.provenance[0].bytes = 20
		"cruise_empty": cruise = {}
	if corruption != "cruise_absent": payload.cruise = cruise
	var rotation := {"angle_unit_scale": 0.001, "radians_per_turn": 6.0, "time_scale": 0.03, "rotation_order": "local_x_y", "provenance": []}
	for i in 6: rotation.provenance.append({"offset": i * 100, "bytes": [24, 61, 4, 4, 4, 45][i]})
	match corruption:
		"rotation_rate": rotation.time_scale = 2.0
		"rotation_order": rotation.rotation_order = "world_y_x"
		"rotation_extent": rotation.provenance[0].offset = 1020
		"rotation_reader": rotation.provenance[1].bytes = 90
		"rotation_empty": rotation = {}
	if corruption != "rotation_absent": payload.manual_rotation = rotation
	var response := {"target_gain": 750.0, "target_divisor": 63, "ramp_bias": 3.3, "ramp_scale": 20.0,
		"neutral_divisor": 126.0, "mode": "elapsed", "command_curve": "signed_square", "provenance": []}
	var response_sizes := [54, 33, 33, 32, 32, 32, 32, 4, 4, 4, 4, 4, 4, 4, 4, 4]
	for i in response_sizes.size(): response.provenance.append({"offset": i * 60, "bytes": response_sizes[i]})
	match corruption:
		"response_gain": response.target_gain = -750
		"response_curve": response.command_curve = "linear"
		"response_divisor": response.target_divisor = 64
		"response_extent": response.provenance[0].offset = 1020
		"response_reader": response.provenance[1].bytes = 58
		"response_provenance": response.provenance.pop_back()
		"response_empty": response = {}
	if corruption != "response_absent": payload.pilot_response = response
	var vehicle := {"base_add": -0.45, "base_divisor": 1.1, "base_scale": 0.85, "base_offset": 0.7,
		"upgrade_tag": 3, "upgrade_bonus": 0.2, "equipment_type": 16, "item_type_value_index": 5,
		"equipment_percent_property": 28, "percent_divisor": 100.0, "response_scale": 20.0, "equipment_rule": "last_matching", "provenance": {}}
	var vehicle_sizes := Vehicle.provenance_sizes("x86_64")
	var vehicle_offset := 0
	for key in vehicle_sizes:
		vehicle.provenance[key] = {"offset": vehicle_offset, "bytes": vehicle_sizes[key]}
		vehicle_offset += vehicle_sizes[key]
	match corruption:
		"vehicle_type": vehicle.equipment_type = 30
		"vehicle_divisor": vehicle.percent_divisor = 0
		"vehicle_rule": vehicle.equipment_rule = "sum"
		"vehicle_extent": vehicle.provenance.handling_getter.offset = 1020
		"vehicle_reader": vehicle.provenance.handling_getter.bytes = 66
		"vehicle_provenance": vehicle.provenance.erase("upgrade_bonus")
		"vehicle_empty": vehicle = {}
	if corruption != "vehicle_absent": payload.vehicle_response = vehicle
	var clock := {"max_frame_milliseconds": 150, "time_unit": "milliseconds", "provenance": [{"offset": 0, "bytes": 72}, {"offset": 100, "bytes": 28}]}
	match corruption:
		"clock_cap": clock.max_frame_milliseconds = 0
		"clock_unit": clock.time_unit = "seconds"
		"clock_extent": clock.provenance[0].offset = 1020
		"clock_reader": clock.provenance[0].bytes = 62
		"clock_provenance": clock.provenance.pop_back()
		"clock_empty": clock = {}
	if corruption != "clock_absent": payload.frame_clock = clock
	var opening := {"ship_id": 7, "station_id": 9, "item_category_value_index": 3, "equipment": [], "provenance": {}}
	for i in 7: opening.equipment.append({"item_id": i, "slot": i % 4, "quantity": 1})
	var opening_sizes := {"declaration": 376, "item_clone": 31, "stack_clone": 30, "install_category": 57, "category_getter": 9, "ship_clone": 27}
	var opening_offset := 0
	for key in opening_sizes:
		opening.provenance[key] = {"offset": opening_offset, "bytes": opening_sizes[key]}
		opening_offset += opening_sizes[key]
	match corruption:
		"opening_type": opening.ship_id = "7"
		"opening_quantity": opening.equipment[0].quantity = 0
		"opening_slot": opening.equipment[0].slot = 256
		"opening_category": opening.item_category_value_index = 5
		"opening_extent": opening.provenance.declaration.offset = 1020
		"opening_reader": opening.provenance.declaration.bytes = 284
		"opening_provenance": opening.provenance.erase("item_clone")
		"opening_vehicle": payload.vehicle_response = {}
		"opening_empty": opening = {}
	if corruption != "opening_absent": payload.opening_loadout = opening
	var radio := {"campaign_cursor": 0, "events": [], "provenance": {}, "timing": {"display_delay_ms": 2000, "base_duration_ms": 1500, "per_line_ms": 2000}}
	for i in 23: radio.events.append({"text_id": i, "speaker_id": 0, "condition": 5, "values": [20]})
	var radio_sizes := {"declaration": 1364, "single_constructor": 91, "range_wrapper": 10, "range_constructor": 143, "dispatch": 44, "dispatch_table": 648, "duration": 32, "display_delay": 26}
	for key in radio_sizes: radio.provenance[key] = {"offset": 0, "bytes": radio_sizes[key]}
	match corruption:
		"radio_count": radio.events.pop_back()
		"radio_condition": radio.events[0].condition = 10
		"radio_dependency":
			radio.events[0].condition = 6
			radio.events[0].values = [23]
		"radio_timing": radio.timing.per_line_ms = 500
		"radio_extent": radio.provenance.declaration.offset = 4000
		"radio_provenance": radio.provenance.erase("range_constructor")
		"radio_empty": radio = {}
	if corruption != "radio_absent": payload.opening_dialogue = radio
	var aliases := {"aliases": [], "provenance": {"declaration": {"offset": 0, "bytes": 602}, "switch_table": {"offset": 700, "bytes": 88}}}
	for i in 20: aliases.aliases.append([512 + i, 65 + i])
	match corruption:
		"aliases_count": aliases.aliases.pop_back()
		"aliases_duplicate": aliases.aliases[1][0] = aliases.aliases[0][0]
		"aliases_control": aliases.aliases[0][1] = 10
		"aliases_surrogate": aliases.aliases[0][1] = 0xd800
		"aliases_extent": aliases.provenance.declaration.offset = 4000
		"aliases_provenance": aliases.provenance.erase("switch_table")
		"aliases_empty": aliases = {}
	if corruption != "aliases_absent": payload.text_aliases = aliases
	if corruption.begins_with("fonts_"):
		var path := LOW.replace("example", "font_extra")
		base.files[path] = base.files[LOW].duplicate(true)
		rows.append({"id": 17, "kind": "texture", "resource": path, "registration_type": 2, "texture_parameter_bits": 0, "source_offset": 350})
		payload.texture_variants = []
		var fonts := FontFixture.definition(path, HIGH, LOW)
		match corruption:
			"fonts_duplicate": fonts.records[1].id = fonts.records[0].id
			"fonts_language": fonts.languages.rows[1].language_id = 0
			"fonts_spacing": fonts.selection.spacing.default[0] = 0.5
			"fonts_atlas": fonts.textures.rows[0].variants.baseline = MESH
			"fonts_order":
				fonts.textures.rows[0].variants.baseline = LOW
				fonts.textures.rows[0].source_offsets.baseline = 200
				fonts.textures.rows[0].variants.large = path
				fonts.textures.rows[0].source_offsets.large = 350
			"fonts_extent": fonts.selection.source_offset = 4000
			"fonts_provenance": fonts.textures.provenance.erase("large")
			"fonts_empty": fonts = {}
		if corruption != "fonts_absent": payload.font_bindings = fonts
	if corruption.begins_with("portraits_"):
		payload.font_bindings = {}
		var portraits := PortraitFixture.definition()
		match corruption:
			"portraits_duplicate": portraits.rows[1].id = portraits.rows[0].id
			"portraits_variant": portraits.rows[0].variants.baseline = MESH
			"portraits_extent": portraits.rows[0].source_offset = 65535
			"portraits_empty": portraits = {}
		if corruption != "portraits_absent": payload.portrait_textures = portraits
	if corruption.begins_with("speakers_"):
		payload.font_bindings = {}
		payload.portrait_textures = {}
		var speakers := SpeakerFixture.definition()
		match corruption:
			"speakers_duplicate": speakers.portraits[2].speaker_id = 1
			"speakers_extent": speakers.provenance.name_selection.offset = 65535
			"speakers_invented": speakers.portraits[0].parts = [0, 0, 0, 0]
			"speakers_empty": speakers = {}
		if corruption != "speakers_absent": payload.speaker_bindings = speakers
	if corruption.begins_with("images_"):
		payload.font_bindings = {}
		payload.portrait_textures = {}
		payload.speaker_bindings = {}
		var images := ImageFixture.definition()
		match corruption:
			"images_extent": images.records[0].source_offset = 65535
			"images_range": images.ranges[0].first_id = 65534
			"images_empty": images = {}
		if corruption != "images_absent": payload.image_regions = images
	if corruption.begins_with("layers_"):
		payload.font_bindings = {}
		payload.portrait_textures = {}
		payload.speaker_bindings = {}
		payload.image_regions = {}
		var layers := LayerFixture.definition()
		match corruption:
			"layers_extent": layers.provenance.baseline.offset = 65535
			"layers_order": layers.draw_order = [0, 1, 2, 3]
			"layers_anchor": layers.variants.baseline[0][0].anchor = 64
			"layers_empty": layers = {}
		if corruption != "layers_absent": payload.portrait_layers = layers
	if corruption.begins_with("actors_"):
		payload.font_bindings = {}
		payload.portrait_textures = {}
		payload.speaker_bindings = {}
		payload.image_regions = {}
		payload.portrait_layers = {}
		var actors := ActorFixture.definition()
		match corruption:
			"actors_extent": actors.provenance.declaration.offset = 65535
			"actors_id": actors.actors[1].actor_id = 0
			"actors_hull": actors.actors[0].current_hull_override = -1
			"actors_empty": actors = {}
		if corruption != "actors_absent": payload.opening_actors = actors
	if corruption.begins_with("staging_"):
		payload.font_bindings = {}
		payload.portrait_textures = {}
		payload.speaker_bindings = {}
		payload.image_regions = {}
		payload.portrait_layers = {}
		payload.opening_actors = {}
		var staging := StagingFixture.definition()
		match corruption:
			"staging_extent": staging.provenance.formation.offset = 65535
			"staging_axes": staging.formation.actors[0].up = [1, 0, 0]
			"staging_gate": staging.formation.after_event_finished = 2.5
			"staging_empty": staging = {}
		if corruption != "staging_absent": payload.opening_staging = staging
	if corruption.begins_with("camera_"):
		for key in ["font_bindings", "portrait_textures", "speaker_bindings", "image_regions", "portrait_layers", "opening_actors", "opening_staging"]: payload[key] = {}
		var camera := CameraFixture.definition()
		match corruption:
			"camera_extent": camera.provenance.defaults.offset = 65535
			"camera_order": camera.pan.follow_player_after_event_finished = 4
			"camera_type": camera.inherit_target_up = 1
			"camera_empty": camera = {}
		if corruption != "camera_absent": payload.opening_camera = camera
	if corruption.begins_with("follow_"):
		for key in ["font_bindings", "portrait_textures", "speaker_bindings", "image_regions", "portrait_layers", "opening_actors", "opening_staging", "opening_camera"]: payload[key] = {}
		var follow := FollowFixture.definition()
		match corruption:
			"follow_extent": follow.provenance.curve.offset = 65535
			"follow_matrix": follow.response_matrix[0].pop_back()
			"follow_rate": follow.look_rate = 0
			"follow_empty": follow = {}
		if corruption != "follow_absent": payload.camera_follow = follow
	if corruption.begins_with("drift_"):
		for key in ["font_bindings", "portrait_textures", "speaker_bindings", "image_regions", "portrait_layers", "opening_actors", "opening_staging", "opening_camera", "camera_follow"]: payload[key] = {}
		var drift := DriftFixture.definition()
		match corruption:
			"drift_extent": drift.provenance.wave.offset = 65535
			"drift_rate": drift.frequency_per_millisecond = 0
			"drift_ids": drift.actor_ids = [0, 0]
			"drift_empty": drift = {}
		if corruption != "drift_absent": payload.opening_drift = drift
	if corruption.begins_with("projection_"):
		for key in ["font_bindings", "portrait_textures", "speaker_bindings", "image_regions", "portrait_layers", "opening_actors", "opening_staging", "opening_camera", "camera_follow", "opening_drift"]: payload[key] = {}
		var projection := ProjectionFixture.definition()
		match corruption:
			"projection_extent": projection.provenance.start.offset = 65535
			"projection_fov": projection.vertical_fov_radians = 0
			"projection_far": projection.far = projection.near
			"projection_empty": projection = {}
		if corruption != "projection_absent": payload.flight_projection = projection
	if corruption.begins_with("openingtime_"):
		for key in ["font_bindings", "portrait_textures", "speaker_bindings", "image_regions", "portrait_layers", "opening_actors", "opening_staging", "opening_camera", "camera_follow", "opening_drift", "flight_projection"]: payload[key] = {}
		var opening_time := OpeningClockFixture.definition()
		match corruption:
			"openingtime_extent": opening_time.provenance.frame.offset = 65535
			"openingtime_seed": opening_time.initial_elapsed_ms = -1
			"openingtime_order": opening_time.advance_before_controller = false
			"openingtime_empty": opening_time = {}
		if corruption != "openingtime_absent": payload.opening_clock = opening_time
	if corruption.begins_with("lod_") or corruption.begins_with("refresh_"):
		for key in ["font_bindings","portrait_textures","speaker_bindings","image_regions","portrait_layers","opening_actors","opening_staging","opening_camera","camera_follow","opening_drift","flight_projection","opening_clock"]: payload[key]={}
		var lod := LodFixture.definition()
		match corruption:
			"lod_count": lod.body_resource_ids.pop_back()
			"lod_gap": lod.body_resource_ids[0][0]=65535
			"lod_extent": lod.provenance.body.offset=65535
			"lod_distance": lod.distances=[30,20]
			"lod_factor": lod.squared_distance_factors=[1,0.5,0.25]
			"lod_empty": lod={}
		if corruption!="lod_absent": payload.ship_lod=lod
	if corruption.begins_with("refresh_"):
		var refresh := RefreshFixture.definition()
		match corruption:
			"refresh_extent": refresh.provenance.batch.offset=65535
			"refresh_overlap": refresh.provenance.tick.offset=refresh.provenance.batch.offset
			"refresh_seed": refresh.initial_milliseconds=-1
			"refresh_threshold": refresh.refresh_at_milliseconds=0
			"refresh_reset": refresh.reset_milliseconds=1
			"refresh_forced": refresh.forced_refresh_resets_clock=true
			"refresh_empty": refresh={}
		if corruption!="refresh_absent": payload.lod_refresh=refresh
	var body := JSON.stringify(payload)
	var digest := body.sha256_text()
	var identity := "gof2-bindings-v1\n%s\n%s\nx86_64\n%s\n" % [base.content_id, "e".repeat(64), digest]
	var header := {"schema": 1, "reader": reader, "architecture": "x86_64", "base_content_id": base.content_id,
		"source_executable_sha256": "e".repeat(64), "source_executable_bytes": 65536 if corruption.begins_with("refresh_") or corruption.begins_with("lod_") or corruption.begins_with("openingtime_") or corruption.begins_with("projection_") or corruption.begins_with("drift_") or corruption.begins_with("follow_") or corruption.begins_with("camera_") or corruption.begins_with("staging_") or corruption.begins_with("actors_") or corruption.begins_with("layers_") or corruption.begins_with("portraits_") or corruption.begins_with("speakers_") or corruption.begins_with("images_") else 4096 if corruption.begins_with("radio_") or corruption.begins_with("aliases_") or corruption.begins_with("fonts_") else 1024, "records_sha256": digest,
		"records_bytes": body.to_utf8_buffer().size(), "binding_id": identity.sha256_text()}
	for name in ["registrations.json", "bindings.json"]:
		var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
		file.store_string(body if name == "registrations.json" else JSON.stringify(header))
		file.close()

func dict_copy(source: Dictionary, key: String, value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	result[key] = value
	return result

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
