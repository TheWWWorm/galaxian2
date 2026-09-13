extends RefCounted
const DesktopText=preload("res://src/content/desktop_text_definitions.gd")
const NpcHull=preload("res://src/content/npc_hull_definitions.gd")
const ArrivalWorldInitialization=preload("res://src/content/arrival_world_initialization_definitions.gd")
const StationPresentation=preload("res://src/content/station_presentation_definitions.gd")
const MiningDrill=preload("res://src/content/mining_drill_definitions.gd")
const GameOver=preload("res://src/content/game_over_definitions.gd")
const FullHoldParticles=preload("res://src/content/full_hold_particle_definitions.gd")
const PlayerDestruction=preload("res://src/content/player_destruction_definitions.gd")
const CombatTrainingVisuals=preload("res://src/content/combat_training_visual_definitions.gd")
const CombatTrainingStory=preload("res://src/content/combat_training_story_definitions.gd")
const MAX_READER_VERSION:=122
const CombatTrainingDestruction=preload("res://src/content/combat_training_destruction_definitions.gd")
const CombatTrainingWeapons=preload("res://src/content/combat_training_weapon_definitions.gd")
const CombatTrainingControl=preload("res://src/content/combat_training_control_definitions.gd")
const CombatTraining=preload("res://src/content/combat_training_definitions.gd")
const StationEquipment=preload("res://src/content/station_equipment_definitions.gd")
const FullHoldReturn=preload("res://src/content/full_hold_return_definitions.gd")
const FullHoldAppearance=preload("res://src/content/full_hold_appearance_definitions.gd")
const FullHoldStory=preload("res://src/content/full_hold_story_definitions.gd")
const FullHoldDestruction=preload("res://src/content/full_hold_destruction_definitions.gd")
const FullHoldControl=preload("res://src/content/full_hold_control_definitions.gd")
const FullHoldPirate=preload("res://src/content/full_hold_pirate_definitions.gd")
const FullHoldFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const FullHoldDeparture=preload("res://src/content/full_hold_departure_definitions.gd")
const StationReturn=preload("res://src/content/station_return_definitions.gd")
const StationFlight=preload("res://src/content/station_flight_definitions.gd")
const StationAutopilot=preload("res://src/content/station_autopilot_definitions.gd")
const StationExterior=preload("res://src/content/station_exterior_definitions.gd")
const MiningObjective=preload("res://src/content/mining_objective_definitions.gd")
const MiningSession=preload("res://src/content/mining_session_definitions.gd")
const FlightNotices=preload("res://src/content/flight_notice_definitions.gd")
const MiningApproach=preload("res://src/content/mining_approach_definitions.gd")
const MiningTargeting=preload("res://src/content/mining_targeting_definitions.gd")
const MiningBriefing=preload("res://src/content/mining_briefing_definitions.gd")
const FirstFlight=preload("res://src/content/first_flight_definitions.gd")
const StationDeparture=preload("res://src/content/station_departure_definitions.gd")
const StationEntry=preload("res://src/content/station_entry_definitions.gd")
const ArrivalSession=preload("res://src/content/arrival_session_definitions.gd")
const OpeningHandoff=preload("res://src/content/opening_handoff_definitions.gd")
const ArrivalActorConstruction=preload("res://src/content/arrival_actor_construction_definitions.gd")
const ArrivalActorMotion=preload("res://src/content/arrival_actor_motion_definitions.gd")
const ArrivalEnvironment=preload("res://src/content/arrival_environment_definitions.gd")
const FlightCache=preload("res://src/content/flight_player_cache_definitions.gd")
const ArrivalStaging=preload("res://src/content/arrival_staging_definitions.gd")
const AudioDefinitions=preload("res://src/content/audio_definitions.gd")
const DamageParticles=preload("res://src/content/damage_particle_definitions.gd")
const EngineAudio=preload("res://src/content/engine_audio_definitions.gd")
const RadioAudio=preload("res://src/content/radio_audio_definitions.gd")
const WeaponAudio=preload("res://src/content/weapon_audio_definitions.gd")
const Weapons = preload("res://src/content/weapon_definitions.gd")
const SurfaceMaterial = preload("res://src/content/surface_material_definitions.gd")
const ReflectionSelection = preload("res://src/content/reflection_definitions.gd")
## Reads declarations only. Original executable bytes never enter the runtime.
const Library = preload("res://src/content/library.gd")
const FlightProjection = preload("res://src/content/flight_projection_definitions.gd")
const EnvironmentColors = preload("res://src/content/environment_color_definitions.gd")
const SceneryEffects = preload("res://src/content/scenery_effect_definitions.gd")
const SceneryResources = preload("res://src/content/scenery_resource_definitions.gd")
const SceneryPopulation = preload("res://src/content/scenery_population_definitions.gd")
const OpeningSky = preload("res://src/content/opening_sky_definitions.gd")
const LodRefresh = preload("res://src/content/lod_refresh_definitions.gd")
const ShipLOD = preload("res://src/content/ship_lod_definitions.gd")
const OpeningClock = preload("res://src/content/opening_clock_definitions.gd")
const OpeningDrift = preload("res://src/content/opening_drift_definitions.gd")
const CameraFollow = preload("res://src/content/camera_follow_definitions.gd")
const OpeningCamera = preload("res://src/content/opening_camera_definitions.gd")
const Staging = preload("res://src/content/opening_staging_definitions.gd")
const OpeningActors = preload("res://src/content/opening_actor_definitions.gd")
const PortraitLayers = preload("res://src/content/portrait_layer_definitions.gd")
const ImageRegions = preload("res://src/content/image_region_definitions.gd")
const Speakers = preload("res://src/content/speaker_definitions.gd")
const PortraitTextures = preload("res://src/content/portrait_texture_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Text = preload("res://src/content/text_definitions.gd")
const Dialogue = preload("res://src/content/dialogue_definitions.gd")
const Opening = preload("res://src/content/opening_definitions.gd")
const Clock = preload("res://src/simulation/frame_clock.gd")
const Vehicle = preload("res://src/content/vehicle_definitions.gd")
const Motion = preload("res://src/content/motion_definitions.gd")
const Hangars = preload("res://src/content/hangar_definitions.gd")
const MAX_BYTES := 8 * 1024 * 1024
var error := ""
var binding_id := ""
var base_content_id := ""
var source_architecture := ""
var records := {}
var materials := {}
var texture_variants := {}
var ship_model_resources: Array = []
var ship_model_provenance := {}
var hangars := {}
var ship_placement := {}
var opening_dialogue := {}
var arrival_dialogue := {}
var arrival_staging := {}
var arrival_world_initialization := {}
var opening_handoff := {}
var arrival_session := {}
var station_entry := {}
var station_departure := {}
var mining_drill := {}
var mining_targeting := {}
var mining_approach := {}
var mining_session := {}
var game_over_presentation := {}
var full_hold_particles := {}
var player_destruction := {}
var station_equipment := {}
var combat_training_visuals := {}
var combat_training_story := {}
var combat_training_destruction := {}
var combat_training_weapons := {}
var combat_training_control := {}
var combat_training := {}
var full_hold_return := {}
var full_hold_appearance := {}
var full_hold_story := {}
var full_hold_destruction := {}
var full_hold_control := {}
var full_hold_pirate := {}
var full_hold_flight := {}
var full_hold_departure := {}
var station_return := {}
var station_flight := {}
var station_autopilot := {}
var station_exterior := {}
var mining_objective := {}
var flight_notices := {}
var mining_briefing := {}
var first_flight := {}
var station_presentation := {}
var desktop_text := {}
var arrival_actor_construction := {}
var arrival_actor_motion := {}
var arrival_environment := {}
var text_aliases := {}
var font_bindings := {}
var flight_projection := {}
var opening_clock := {}
var opening_drift := {}
var camera_follow := {}
var opening_camera := {}
var opening_staging := {}
var opening_actors := {}
var portrait_layers := {}
var image_regions := {}
var speaker_bindings := {}
var portrait_textures := {}
var opening_loadout := {}
var frame_clock := {}
var vehicle_response := {}
var pilot_response := {}
var manual_rotation := {}
var cruise := {}
var weapon_parameters := {}
var surface_material := {}
var reflection_selection := {}
var environment_colors := {}
var damage_particles := {}
var audio := {}
var opening_sky := {}
var scenery_effects := {}
var scenery_resources := {}
var scenery_population := {}
var lod_refresh := {}
var ship_lod := {}
var ship_lights := {}
var diagnostics := {}
var base_files := {}


func open(directory: String, base: Dictionary) -> bool:
	error = ""
	binding_id = ""
	base_content_id = ""
	source_architecture = ""
	records = {}
	materials = {}
	texture_variants = {}
	ship_model_resources = []
	ship_model_provenance = {}
	hangars = {}
	ship_placement = {}
	opening_dialogue = {}
	arrival_dialogue = {}
	arrival_staging = {}
	arrival_world_initialization = {}
	opening_handoff = {}
	arrival_session = {}
	station_entry = {}
	station_departure = {}
	mining_drill = {}
	mining_targeting = {}
	mining_approach = {}
	mining_session = {}
	game_over_presentation = {}
	full_hold_particles = {}
	player_destruction = {}
	station_equipment = {}
	combat_training_visuals = {}
	combat_training_story = {}
	combat_training_destruction = {}
	combat_training_weapons = {}
	combat_training_control = {}
	combat_training = {}
	full_hold_return = {}
	full_hold_appearance = {}
	full_hold_story = {}
	full_hold_destruction = {}
	full_hold_control = {}
	full_hold_pirate = {}
	full_hold_flight = {}
	full_hold_departure = {}
	station_return = {}
	station_flight = {}
	station_autopilot = {}
	station_exterior = {}
	mining_objective = {}
	flight_notices = {}
	mining_briefing = {}
	first_flight = {}
	station_presentation = {}
	desktop_text = {}
	arrival_actor_construction = {}
	arrival_actor_motion = {}
	arrival_environment = {}
	text_aliases = {}
	font_bindings = {}
	flight_projection = {}
	opening_clock = {}
	opening_drift = {}
	camera_follow = {}
	opening_camera = {}
	opening_staging = {}
	opening_actors = {}
	portrait_layers = {}
	image_regions = {}
	speaker_bindings = {}
	portrait_textures = {}
	opening_loadout = {}
	frame_clock = {}
	vehicle_response = {}
	pilot_response = {}
	manual_rotation = {}
	cruise = {}
	weapon_parameters = {}
	surface_material = {}
	reflection_selection = {}
	environment_colors = {}
	damage_particles = {}
	audio = {}
	opening_sky = {}
	scenery_effects = {}
	scenery_resources = {}
	scenery_population = {}
	lod_refresh = {}
	ship_lod = {}
	ship_lights = {}
	diagnostics = {}
	base_files = {}
	var header_file := FileAccess.open(directory.path_join("bindings.json"), FileAccess.READ)
	if header_file == null or header_file.get_length() > 16384:
		return fail("Missing or oversized resource binding manifest")
	var header: Variant = JSON.parse_string(header_file.get_as_text())
	var version:=reader_version(header.get("reader") if header is Dictionary else null)
	if not header is Dictionary or header.get("schema") != 1 or version==0:
		return fail("Unsupported resource binding schema")
	if not Library.valid_hash(base.get("content_id")) or not base.get("files") is Dictionary \
			or header.get("base_content_id") != base.content_id:
		return fail("These resource bindings belong to a different base content identity")
	var architecture := "armv7" if base.get("profile", {}).get("edition") == "ios-hd" else "x86_64"
	if header.get("architecture") != architecture:
		return fail("Resource binding architecture does not match the base edition")
	for key in ["source_executable_sha256", "records_sha256", "binding_id"]:
		if not Library.valid_hash(header.get(key)):
			return fail("Invalid resource binding provenance hash")
	if not bounded_integer(header.get("records_bytes"), 1, MAX_BYTES) \
			or not bounded_integer(header.get("source_executable_bytes"), 28, 64 * 1024 * 1024):
		return fail("Invalid resource binding size")
	var identity := "gof2-bindings-v1\n%s\n%s\n%s\n%s\n" % [base.content_id,
		header.source_executable_sha256, architecture, header.records_sha256]
	if identity.sha256_text() != header.binding_id:
		return fail("Resource binding identity mismatch")
	var file := FileAccess.open(directory.path_join("registrations.json"), FileAccess.READ)
	if file == null or file.get_length() != int(header.records_bytes):
		return fail("Resource binding data is missing or changed")
	var bytes := file.get_buffer(int(header.records_bytes))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish().hex_encode() != header.records_sha256:
		return fail("Resource binding checksum mismatch")
	var body: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not body is Dictionary or body.get("schema") != 1 or body.get("reader") != header.reader \
			or not body.get("registrations") is Array or not body.get("diagnostics") is Dictionary:
		return fail("Malformed resource binding data")
	if body.registrations.is_empty() or body.registrations.size() > 20000:
		return fail("Invalid resource registration count")
	var staged := {}
	for row in body.registrations:
		if not row is Dictionary or not bounded_integer(row.get("id"), 0, 65535) \
				or not bounded_integer(row.get("registration_type"), 0, 255) \
				or not bounded_integer(row.get("source_offset"), 0, int(header.source_executable_bytes) - 1):
			return fail("Invalid resource registration record")
		if row.get("kind") not in ["mesh", "texture"] or not row.get("resource") is String:
			return fail("Invalid resource registration kind/path")
		var name: String = row.resource
		if not name.begins_with("resources/data/") or name.length() > 1024 \
				or "\\" in name or ":" in name:
			return fail("Unsafe resource registration path")
		for part in name.split("/"):
			if part in ["", ".", ".."]:
				return fail("Unsafe resource registration path")
		for character in name:
			if character.unicode_at(0) < 32:
				return fail("Unsafe resource registration path")
		if not name.ends_with(".aem" if row.kind == "mesh" else ".aei"):
			return fail("Resource registration extension mismatch")
		if row.has("material_id") or row.has("mesh_flags"):
			if row.kind != "mesh" or row.registration_type != 4 \
					or not bounded_integer(row.get("material_id"), 0, 65535) \
					or not bounded_integer(row.get("mesh_flags"), 0, 255):
				return fail("Invalid mesh material reference")
		if row.has("texture_parameter_bits") and (row.kind != "texture" or row.registration_type != 2 \
				or not bounded_integer(row.texture_parameter_bits, 0, 4294967295)):
			return fail("Invalid texture registration parameter")
		if not staged.has(int(row.id)):
			staged[int(row.id)] = []
		staged[int(row.id)].append(row)
	var staged_materials := {}
	if header.reader != "resource-registration-v1":
		if not body.get("materials") is Array or body.materials.size() > 20000:
			return fail("Invalid material declaration count")
		for row in body.materials:
			if not row is Dictionary or not bounded_integer(row.get("id"), 0, 65535) \
					or not bounded_integer(row.get("render_type"), 0, 4294967295) \
					or not bounded_integer(row.get("source_offset"), 0, int(header.source_executable_bytes) - 1):
				return fail("Invalid material declaration")
			if not row.get("texture_ids") is Array or row.texture_ids.size() != 8 \
					or not row.get("parameter_bits") is Array or row.parameter_bits.size() != 4:
				return fail("Invalid material field layout")
			for value in row.texture_ids:
				if not bounded_integer(value, 0, 65535):
					return fail("Invalid material texture reference")
			for value in row.parameter_bits:
				if not bounded_integer(value, 0, 4294967295):
					return fail("Invalid material parameter bits")
			if not staged_materials.has(int(row.id)):
				staged_materials[int(row.id)] = []
			staged_materials[int(row.id)].append(row)
	var staged_variants := {}
	var staged_ship_models := {}
	if version>=3:
		if not body.get("ship_models") is Dictionary:
			return fail("Invalid ship model table")
		staged_ship_models = body.ship_models
		if not staged_ship_models.is_empty():
			var count := 64 if architecture == "armv7" else 61
			if not staged_ship_models.get("resource_ids") is Array or staged_ship_models.resource_ids.size() != count:
				return fail("Ship model table does not match this edition's catalogue")
			for id in staged_ship_models.resource_ids:
				if not bounded_integer(id, 0, 65534):
					return fail("Invalid ship model resource ID")
			for key in ["table_offsets", "index_reader_offsets"]:
				var offsets: Variant = staged_ship_models.get(key)
				if not offsets is Array or offsets.is_empty() or offsets.size() > 256:
					return fail("Missing or invalid ship model provenance")
				var seen := {}
				for offset in offsets:
					var extent := count * 2 if key == "table_offsets" else 1
					if not bounded_integer(offset, 0, int(header.source_executable_bytes) - extent) or seen.has(offset):
						return fail("Invalid ship model source extent")
					seen[offset] = true
		if not body.get("texture_variants") is Array or body.texture_variants.size() > 20000:
			return fail("Invalid texture quality mapping count")
		for row in body.texture_variants:
			if architecture != "x86_64" or not row is Dictionary or not bounded_integer(row.get("id"), 0, 65535):
				return fail("Invalid texture quality profile/ID")
			var id := int(row.id)
			if staged_variants.has(id) or staged_materials.has(id) or not staged.has(id):
				return fail("Duplicate or conflicting texture quality mapping")
			if not row.get("high") is String or not row.get("low") is String:
				return fail("Invalid texture quality paths")
			var high: String = row.high
			var low: String = row.low
			if not high.begins_with("resources/data/assets/" + high.get_slice("/", 3) + "/3d/textures/high/dx5/") \
					or high.replace("/3d/textures/high/dx5/", "/3d/textures/low/dx5/") != low:
				return fail("Texture quality paths refer to different assets")
			var declared_paths := {}
			var parameter: Variant = staged[id][0].get("texture_parameter_bits")
			for declaration in staged[id]:
				if declaration.kind != "texture" or declaration.registration_type != 2 \
						or not declaration.has("texture_parameter_bits") or declaration.texture_parameter_bits != parameter:
					return fail("Texture quality registration mismatch")
				declared_paths[declaration.resource] = true
			if declared_paths.size() != 2 or not declared_paths.has(high) or not declared_paths.has(low):
				return fail("Texture quality mapping does not cover the declaration set")
			for quality in ["high", "low"]:
				var path: String = row[quality]
				if not base.files.has(path) or base.files[path].get("kind") != "texture" \
						or not Library.valid_hash(row.get(quality + "_sha256")) \
						or row[quality + "_sha256"] != base.files[path].get("sha256"):
					return fail("Texture quality source provenance mismatch")
				var dimensions: Variant = row.get(quality + "_size")
				if not dimensions is Array or dimensions.size() != 2:
					return fail("Invalid texture quality dimensions")
				for value in dimensions:
					if not bounded_integer(value, 1, 8192):
						return fail("Invalid texture quality dimensions")
			var scale: float = row.high_size[0] / row.low_size[0]
			if scale not in [1.0, 2.0, 4.0, 8.0, 16.0] or row.high_size[1] / row.low_size[1] != scale:
				return fail("Texture quality dimensions are incompatible")
			staged_variants[id] = row
	var staged_hangars := {}
	if version>=4:
		var hangar_error := Hangars.validate(body.get("hangars"), int(header.source_executable_bytes))
		if not hangar_error.is_empty():
			return fail(hangar_error)
		staged_hangars = body.hangars
	var staged_placement := {}
	if version>=5:
		var placement_error := Hangars.validate_ship_placement(body.get("ship_placement"), int(header.source_executable_bytes), architecture)
		if not placement_error.is_empty():
			return fail(placement_error)
		staged_placement = body.ship_placement
	var staged_lights := {}
	if version>=6:
		var light_error := Hangars.validate_ship_lights(body.get("ship_lights"), int(header.source_executable_bytes), architecture)
		if not light_error.is_empty():
			return fail(light_error)
		staged_lights = body.ship_lights
	var staged_cruise := {}
	if version>=7:
		var cruise_error := Motion.validate_cruise(body.get("cruise"), int(header.source_executable_bytes), architecture)
		if not cruise_error.is_empty():
			return fail(cruise_error)
		staged_cruise = body.cruise
	var staged_rotation := {}
	if version>=8:
		var rotation_error := Motion.validate_manual_rotation(body.get("manual_rotation"), int(header.source_executable_bytes), architecture)
		if not rotation_error.is_empty(): return fail(rotation_error)
		staged_rotation = body.manual_rotation
	var staged_response := {}
	if version>=9:
		var response_error := Motion.validate_pilot_response(body.get("pilot_response"), int(header.source_executable_bytes), architecture)
		if not response_error.is_empty(): return fail(response_error)
		staged_response = body.pilot_response
	var staged_vehicle := {}
	if version>=10:
		var vehicle_error := Vehicle.validate(body.get("vehicle_response"), int(header.source_executable_bytes), architecture)
		if not vehicle_error.is_empty(): return fail(vehicle_error)
		staged_vehicle = body.vehicle_response
	var staged_clock := {}
	if version>=11:
		var clock_error := Clock.validate(body.get("frame_clock"), int(header.source_executable_bytes), architecture)
		if not clock_error.is_empty(): return fail(clock_error)
		staged_clock = body.frame_clock
	var staged_opening := {}
	if version>=12:
		var opening_error := Opening.validate(body.get("opening_loadout"), int(header.source_executable_bytes), architecture)
		if not opening_error.is_empty(): return fail(opening_error)
		staged_opening = body.opening_loadout
		if not staged_opening.is_empty() and staged_vehicle.is_empty(): return fail("Opening loadout lacks item category bindings")
	var staged_dialogue := {}
	if version>=13:
		var dialogue_error := Dialogue.validate(body.get("opening_dialogue"), int(header.source_executable_bytes), architecture)
		if not dialogue_error.is_empty(): return fail(dialogue_error)
		staged_dialogue = body.opening_dialogue
	var staged_aliases := {}
	if version>=14:
		var alias_error := Text.validate(body.get("text_aliases"), int(header.source_executable_bytes), architecture)
		if not alias_error.is_empty(): return fail(alias_error)
		staged_aliases = body.text_aliases
	var staged_fonts := {}
	if version>=15:
		var font_error := Fonts.validate(body.get("font_bindings"), int(header.source_executable_bytes), architecture, staged)
		if not font_error.is_empty(): return fail(font_error)
		staged_fonts = body.font_bindings
	var staged_portraits := {}
	if version>=16:
		var portrait_error := PortraitTextures.validate(body.get("portrait_textures"), int(header.source_executable_bytes), architecture)
		if not portrait_error.is_empty(): return fail(portrait_error)
		staged_portraits = body.portrait_textures
	var staged_speakers := {}
	if version>=17:
		var speaker_error := Speakers.validate(body.get("speaker_bindings"), int(header.source_executable_bytes), architecture)
		if not speaker_error.is_empty(): return fail(speaker_error)
		staged_speakers = body.speaker_bindings
	var staged_images := {}
	if version>=18:
		var image_error := ImageRegions.validate(body.get("image_regions"), int(header.source_executable_bytes), architecture)
		if not image_error.is_empty(): return fail(image_error)
		staged_images = body.image_regions
	var staged_layers := {}
	if version>=19:
		var layer_error := PortraitLayers.validate(body.get("portrait_layers"), int(header.source_executable_bytes), architecture)
		if not layer_error.is_empty(): return fail(layer_error)
		staged_layers = body.portrait_layers
	var staged_actors := {}
	if version>=20:
		var actor_error := OpeningActors.validate(body.get("opening_actors"), int(header.source_executable_bytes), architecture)
		if not actor_error.is_empty(): return fail(actor_error)
		if version>=56 and not body.get("opening_actors",{}).get("npc_initialization",{}).is_empty() and not body.opening_actors.npc_initialization.has("destruction"):
			return fail("Missing NPC destruction capability")
		if version>=57 and not body.get("opening_actors",{}).get("npc_initialization",{}).is_empty() and not body.opening_actors.npc_initialization.has("death_accounting"):
			return fail("Missing NPC death accounting capability")
		if version>=37 and not body.opening_actors.is_empty() and not body.opening_actors.has("npc_initialization"):
			return fail("Missing NPC initialization support declaration")
		if version>=44 and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("primary_weapon"):
			return fail("Missing opening NPC weapon scope")
		if version>=38 and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("activation"):
			return fail("Missing NPC activation support declaration")
		if version>=45 and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("flight"):
			return fail("Missing NPC flight scope")
		if version>=46 and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("guidance"):
			return fail("Missing opening NPC guidance scope")
		if version>=47 and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("holding"):
			return fail("Missing opening NPC holding scope")
		if version>=48 and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("routes"):
			return fail("Missing opening NPC route scope")
		if version>=49 and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("construction"):
			return fail("Missing opening NPC construction scope")
		if header.reader=="resource-registration-v50" and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("world_initialization"):
			return fail("Missing opening world initialization scope")
		if version>=51 and not body.opening_actors.is_empty() and not body.opening_actors.has("player_initialization"):
			return fail("Missing player initialization support declaration")
		if version>=53 and not body.opening_actors.is_empty() and not body.opening_actors.npc_initialization.is_empty() and not body.opening_actors.npc_initialization.has("hostility"):
			return fail("Missing opening NPC hostility scope")
		if version>=54 and not body.opening_actors.is_empty() and not body.opening_actors.player_initialization.is_empty() and not body.opening_actors.player_initialization.has("recharge"):
			return fail("Missing player shield recharge scope")
		if version>=55 and not body.opening_actors.is_empty() and not body.opening_actors.player_initialization.is_empty() and not body.opening_actors.player_initialization.has("repair"):
			return fail("Missing player equipment repair scope")
		staged_actors = body.opening_actors
	var staged_staging := {}
	if version>=21:
		var staging_error := Staging.validate(body.get("opening_staging"), int(header.source_executable_bytes), architecture)
		if not staging_error.is_empty(): return fail(staging_error)
		if version>=58 and not body.opening_staging.is_empty() and not body.opening_staging.has("player_motion"):
			return fail("Missing scripted player motion capability")
		staged_staging = body.opening_staging
	var staged_camera := {}
	if version>=22:
		var camera_error := OpeningCamera.validate(body.get("opening_camera"), int(header.source_executable_bytes), architecture)
		if not camera_error.is_empty(): return fail(camera_error)
		staged_camera = body.opening_camera
	var staged_follow := {}
	if version>=23:
		var follow_error := CameraFollow.validate(body.get("camera_follow"), int(header.source_executable_bytes), architecture)
		if not follow_error.is_empty(): return fail(follow_error)
		staged_follow = body.camera_follow
	var staged_drift := {}
	if version>=24:
		var drift_error := OpeningDrift.validate(body.get("opening_drift"), int(header.source_executable_bytes), architecture)
		if not drift_error.is_empty(): return fail(drift_error)
		staged_drift = body.opening_drift
	var staged_projection := {}
	if version>=25:
		var projection_error := FlightProjection.validate(body.get("flight_projection"), int(header.source_executable_bytes), architecture)
		if not projection_error.is_empty(): return fail(projection_error)
		staged_projection = body.flight_projection
	var staged_opening_clock := {}
	if version>=26:
		var opening_clock_error := OpeningClock.validate(body.get("opening_clock"), int(header.source_executable_bytes), architecture)
		if not opening_clock_error.is_empty(): return fail(opening_clock_error)
		staged_opening_clock = body.opening_clock
	var staged_lod := {}
	if version>=27:
		var lod_error := ShipLOD.validate(body.get("ship_lod"), int(header.source_executable_bytes), architecture)
		if not lod_error.is_empty(): return fail(lod_error)
		staged_lod = body.ship_lod
	var staged_refresh := {}
	if version>=28:
		var refresh_error := LodRefresh.validate(body.get("lod_refresh"), int(header.source_executable_bytes), architecture)
		if not refresh_error.is_empty(): return fail(refresh_error)
		staged_refresh = body.lod_refresh
	var staged_particles := {}
	if version>=69:
		var particle_error:=DamageParticles.validate(body.get("damage_particles"),int(header.source_executable_bytes),architecture)
		if not particle_error.is_empty():return fail(particle_error)
		staged_particles=body.damage_particles
		if version>=70 and not staged_particles.is_empty() and not DamageParticles.emitter_parameters(staged_particles):
			return fail("Missing or unsupported damage particle emitter defaults")
		if version>=71 and not staged_particles.is_empty() and not staged_particles.get("owners") is Dictionary:
			return fail("Missing damage particle owner capability")
	var staged_sky := {}
	if version>=29:
		var sky_error := OpeningSky.validate(body.get("opening_sky"), int(header.source_executable_bytes), architecture)
		if not sky_error.is_empty(): return fail(sky_error)
		staged_sky = body.opening_sky
		if version>=67 and not staged_sky.is_empty() and not staged_sky.has("planet_resources"):
			return fail("Missing planet resource capability in current declarations")
		if version>=68 and not staged_sky.is_empty() and not staged_sky.has("sun_flares"):
			return fail("Missing sun flare capability in current declarations")
	var staged_colors := {}
	if version>=30:
		var color_data: Variant = body.get("environment_colors")
		if header.reader == "resource-registration-v30": color_data = EnvironmentColors.normalize_v30(color_data)
		var color_error := EnvironmentColors.validate(color_data, int(header.source_executable_bytes), architecture)
		if not color_error.is_empty(): return fail(color_error)
		staged_colors = color_data
	var staged_reflection := {}
	if version>=32:
		var reflection_error := ReflectionSelection.validate(body.get("reflection_selection"), int(header.source_executable_bytes), architecture, staged_projection, staged_sky)
		if not reflection_error.is_empty(): return fail(reflection_error)
		staged_reflection = body.reflection_selection
	var staged_surface := {}
	if version>=33:
		var surface_error := SurfaceMaterial.validate(body.get("surface_material"), int(header.source_executable_bytes), architecture, staged_colors)
		if not surface_error.is_empty(): return fail(surface_error)
		staged_surface = body.surface_material
	var staged_weapons := {}
	if version>=34:
		var weapon_error := Weapons.validate(body.get("weapon_parameters"), int(header.source_executable_bytes), architecture, staged_vehicle, staged_opening)
		if not weapon_error.is_empty(): return fail(weapon_error)
		if version>=35 and not body.weapon_parameters.is_empty() and not body.weapon_parameters.has("launch_modes"):
			return fail("Missing weapon launch mode scope")
		if version>=36 and not body.weapon_parameters.is_empty() and not body.weapon_parameters.has("projectile_capacity"):
			return fail("Missing weapon projectile capacity scope")
		if version>=39 and not body.weapon_parameters.is_empty() and not body.weapon_parameters.has("ordinary_hit_policy"):
			return fail("Missing ordinary weapon hit policy support declaration")
		if version>=40 and not body.weapon_parameters.is_empty() and not body.weapon_parameters.has("collision_bounds"):
			return fail("Missing weapon collision bounds support declaration")
		if version>=52 and not body.weapon_parameters.is_empty() and not body.weapon_parameters.has("player_hit_policy"):
			return fail("Missing player hit policy support declaration")
		staged_weapons = body.weapon_parameters
		if version>=75 and not staged_weapons.is_empty() and not staged_weapons.has("audio"):return fail("Missing weapon audio capability")
		var weapon_audio_error := WeaponAudio.validate(staged_weapons.get("audio",{}),int(header.source_executable_bytes),architecture,staged_weapons,staged_actors,staged_staging)
		if not weapon_audio_error.is_empty():return fail(weapon_audio_error)
	var staged_npc: Dictionary=staged_actors.get("npc_initialization",{})
	if version>=63 and not staged_npc.is_empty() and not staged_npc.has("hull"):
		return fail("Missing fresh NPC hull capability")
	var npc_hull: Dictionary=staged_npc.get("hull",{})
	if version>=83 and not npc_hull.is_empty() and not NpcHull.parameters(npc_hull):return fail("Missing corrected flight-entry NPC hull declaration")
	if not npc_hull.is_empty():
		for key in ["hull_setter","cursor_getter"]:
			if staged_actors.provenance.get(key)!=npc_hull.provenance.get(key): return fail("NPC hull is disconnected from its opening declarations")
		if staged_actors.actors.size()!=npc_hull.hull_catalogue_ids.size(): return fail("NPC hull population differs from its opening")
		for i in staged_actors.actors.size():
			if staged_actors.actors[i].hull_catalogue_id!=npc_hull.hull_catalogue_ids[i]: return fail("NPC hull formula belongs to another opening population")
	var accounting: Dictionary=staged_actors.get("npc_initialization",{}).get("death_accounting",{})
	if not accounting.is_empty():
		var normal_hit: Variant=staged_weapons.get("ordinary_hit_policy",{}).get("provenance",{}).get("normal_hit")
		if not normal_hit is Dictionary or normal_hit.get("offset")!=accounting.provenance.hit_argument.offset:
			return fail("NPC attribution belongs to another weapon damage owner")
	if version>=59 and not staged_staging.is_empty() and not staged_staging.has("player_flight"):
		return fail("Missing ordinary player flight scope")
	var player_motion: Dictionary=staged_staging.get("player_motion",{})
	if not player_motion.is_empty():
		if staged_actors.get("player_initialization",{}).is_empty() or staged_camera.get("pan",{}).get("follow_player_after_event_finished")!=player_motion.release_after_event_finished:
			return fail("Scripted player motion lacks its player or camera handoff")
		var cruise_proof: Variant=staged_cruise.get("provenance")
		if staged_cruise.get("speed_units_per_millisecond")!=2.0 or not cruise_proof is Array or cruise_proof.size()!=5:
			return fail("Scripted player motion lacks its supported cruise speed")
		if cruise_proof[0].offset!=player_motion.provenance.speed.offset or cruise_proof[3].offset!=player_motion.provenance.forward_helper.offset:
			return fail("Scripted player motion belongs to another cruise owner")
	if version>=60 and not staged_staging.is_empty() and not staged_staging.has("projectile_visuals"):
		return fail("Missing ordinary projectile visuals capability")
	if version>=61 and not staged_staging.is_empty() and not staged_staging.has("projectile_impacts"):
		return fail("Missing ordinary impact capability")
	if not staged_staging.get("projectile_impacts",{}).is_empty() and (staged_staging.get("projectile_visuals",{}).is_empty() or staged_weapons.get("ordinary_hit_policy",{}).is_empty() or staged_weapons.get("player_hit_policy",{}).is_empty()):
		return fail("Ordinary impacts lack verified weapon visuals and contact policies")
	if version>=62 and not staged_staging.is_empty() and not staged_staging.has("player_aim"):
		return fail("Missing player aim capability")
	if not staged_staging.get("player_aim",{}).is_empty() and (staged_staging.get("player_flight",{}).is_empty() or staged_staging.get("player_motion",{}).is_empty() or staged_staging.get("projectile_impacts",{}).is_empty() or staged_projection.is_empty()):
		return fail("Player aim lacks its flight, contact or projection declarations")
	if version>=64 and not staged_staging.is_empty() and not staged_staging.has("npc_scanner"):
		return fail("Missing NPC scanner capability")
	if not staged_staging.get("npc_scanner",{}).is_empty():
		var npc: Dictionary=staged_actors.get("npc_initialization",{})
		if staged_staging.get("player_aim",{}).is_empty() or npc.get("hull",{}).is_empty() or npc.get("hostility",{}).is_empty() or npc.get("construction",{}).is_empty():return fail("NPC scanner lacks its fresh actor and aim scope")
	if version>=65 and not staged_staging.is_empty() and not staged_staging.has("escape"):
		return fail("Missing opening escape capability")
	if not staged_staging.get("escape",{}).is_empty():
		if staged_staging.get("player_flight",{}).is_empty() or staged_staging.get("player_motion",{}).is_empty():return fail("Opening escape lacks its player movement scope")
		if staged_staging.player_flight.postcombat_after_event_finished!=staged_staging.escape.entry_after_event_finished:return fail("Opening escape does not join its encounter boundary")
	if version>=66 and not staged_staging.is_empty() and not staged_staging.has("escape_camera"):
		return fail("Missing opening escape camera capability")
	if not staged_staging.get("escape_camera",{}).is_empty():
		if staged_staging.get("escape",{}).is_empty() or not staged_camera.get("inherit_target_up",false):return fail("Opening escape camera lacks its choreography and target up")
	var player_flight: Dictionary=staged_staging.get("player_flight",{})
	if not staged_staging.get("projectile_visuals",{}).is_empty() and (player_flight.is_empty() or staged_actors.get("npc_initialization",{}).get("primary_weapon",{}).get("item_id")!=19):
		return fail("Projectile visuals lack their fresh player and NPC scope")
	if not player_flight.is_empty():
		if player_motion.is_empty() or player_motion.release_phase!=player_flight.ordinary_phase or staged_actors.get("player_initialization",{}).is_empty() or not staged_actors.get("npc_initialization",{}).get("initial_firing_allowed",false):
			return fail("Ordinary player flight lacks its fresh player and release")
		if staged_rotation.get("provenance",[]).is_empty() or staged_response.get("provenance",[]).is_empty():
			return fail("Ordinary player flight lacks native motion declarations")
		if staged_rotation.provenance[0].offset!=player_flight.provenance.rotation_anchor.offset or staged_response.provenance[0].offset!=player_flight.provenance.response_anchor.offset:
			return fail("Ordinary player flight belongs to another motion owner")
	var staged_scenery_resources := {}
	var staged_scenery := {}
	if version>=41:
		var scenery_error := SceneryPopulation.validate(body.get("scenery_population"),int(header.source_executable_bytes),architecture)
		if not scenery_error.is_empty(): return fail(scenery_error)
		staged_scenery=body.scenery_population
	if version>=42:
		var resource_error := SceneryResources.validate(body.get("scenery_resources"),int(header.source_executable_bytes),architecture,staged_scenery)
		if not resource_error.is_empty(): return fail(resource_error)
		staged_scenery_resources=body.scenery_resources
	var staged_scenery_effects := {}
	if version>=43:
		var effect_error := SceneryEffects.validate(body.get("scenery_effects"),int(header.source_executable_bytes),architecture,staged_scenery_resources)
		if not effect_error.is_empty(): return fail(effect_error)
		staged_scenery_effects=body.scenery_effects
	if version>=74 and not staged_npc.is_empty() and not staged_npc.has("destruction_audio"):
		return fail("Missing NPC destruction audio capability")
	var staged_audio: Dictionary = {}
	if version>=72:
		var audio_error := AudioDefinitions.validate(body.get("audio"), base.files)
		if not audio_error.is_empty():return fail(audio_error)
		staged_audio=body.audio
	if not staged_weapons.get("audio",{}).is_empty() and not staged_audio.is_empty():
		for id in staged_weapons.audio.player_event_ids+staged_weapons.audio.npc_event_ids:
			if id>=staged_audio.events.size():return fail("Weapon sound is absent from this edition's event catalogue")
	if version>=76 and not staged_dialogue.is_empty() and not staged_dialogue.has("voice"):
		return fail("Missing opening radio voice capability")
	if version>=77 and not staged_vehicle.is_empty() and not staged_vehicle.has("audio"):return fail("Missing player engine selection capability")
	var engine_audio_error:=EngineAudio.validate(staged_vehicle.get("audio",{}),int(header.source_executable_bytes),architecture,staged_vehicle,staged_rotation,staged_audio)
	if not engine_audio_error.is_empty():return fail(engine_audio_error)
	var voice_error:=RadioAudio.validate(staged_dialogue.get("voice",{}), int(header.source_executable_bytes), architecture, staged_dialogue, staged_fonts, staged_audio)
	if not voice_error.is_empty():return fail(voice_error)
	var staged_arrival := {}
	if version>=78:
		var arrival_error := Dialogue.validate(body.get("arrival_dialogue"), int(header.source_executable_bytes), architecture, 1, staged_dialogue)
		if not arrival_error.is_empty(): return fail(arrival_error)
		staged_arrival = body.arrival_dialogue
		if not staged_arrival.is_empty() and not staged_arrival.has("voice"): return fail("Missing rescue radio voice capability")
		arrival_error = RadioAudio.validate(staged_arrival.get("voice", {}), int(header.source_executable_bytes), architecture, staged_arrival, staged_fonts, staged_audio)
		if not arrival_error.is_empty(): return fail(arrival_error)
	var staged_arrival_staging := {}
	if version>=79:
		var arrival_error := ArrivalStaging.validate(body.get("arrival_staging"),int(header.source_executable_bytes),architecture,staged_staging,staged_arrival,staged_actors,version>=85)
		if not arrival_error.is_empty():return fail(arrival_error)
		staged_arrival_staging=body.arrival_staging
	var staged_player: Dictionary=staged_actors.get("player_initialization",{})
	if version>=80 and not staged_player.is_empty() and not staged_player.has("flight_cache"):
		return fail("Missing flight player cache capability")
	var cache_error:=FlightCache.validate(staged_player.get("flight_cache",{}),int(header.source_executable_bytes),architecture,staged_opening,staged_actors,staged_arrival_staging)
	if not cache_error.is_empty():return fail(cache_error)
	var staged_arrival_environment := {}
	if version>=81:
		var environment_error:=ArrivalEnvironment.validate(body.get("arrival_environment"),int(header.source_executable_bytes),architecture,staged_sky,staged_actors,staged_arrival_staging)
		if not environment_error.is_empty():return fail(environment_error)
		staged_arrival_environment=body.arrival_environment
	var staged_arrival_actor_motion := {}
	if version>=82:
		var actor_error:=ArrivalActorMotion.validate(body.get("arrival_actor_motion"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_actors,staged_arrival_environment)
		if not actor_error.is_empty():return fail(actor_error)
		staged_arrival_actor_motion=body.arrival_actor_motion
	var staged_arrival_actor_construction := {}
	if version>=84:
		var construction_error:=ArrivalActorConstruction.validate(body.get("arrival_actor_construction"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_actors,staged_arrival_environment)
		if not construction_error.is_empty():return fail(construction_error)
		staged_arrival_actor_construction=body.arrival_actor_construction
	var staged_arrival_world_initialization := {}
	if version>=86:
		var world_error:=ArrivalWorldInitialization.validate(body.get("arrival_world_initialization"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_actors,staged_arrival_actor_construction,staged_arrival_environment)
		if not world_error.is_empty():return fail(world_error)
		staged_arrival_world_initialization=body.arrival_world_initialization
	var staged_opening_handoff := {}
	if version>=87:
		var handoff_error:=OpeningHandoff.validate(body.get("opening_handoff"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_actors,staged_arrival_world_initialization)
		if not handoff_error.is_empty():return fail(handoff_error)
		staged_opening_handoff=body.opening_handoff
	var staged_arrival_session := {}
	if version>=88:
		var session_error:=ArrivalSession.validate(body.get("arrival_session"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_arrival_actor_motion,staged_arrival_world_initialization,staged_opening_handoff)
		if not session_error.is_empty():return fail(session_error)
		staged_arrival_session=body.arrival_session

	var staged_station_entry := {}
	if version>=89:
		var station_error:=StationEntry.validate(body.get("station_entry"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_arrival_session)
		if not station_error.is_empty():return fail(station_error)
		staged_station_entry=body.station_entry

	var staged_station_presentation := {}
	if version>=90:
		var view_error:=StationPresentation.validate(body.get("station_presentation"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_station_entry)
		if not view_error.is_empty():return fail(view_error)
		staged_station_presentation=body.station_presentation

	var staged_station_departure := {}
	if version>=92:
		var departure_error:=StationDeparture.validate(body.get("station_departure"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_station_entry,staged_player)
		if not departure_error.is_empty():return fail(departure_error)
		staged_station_departure=body.station_departure

	var staged_first_flight := {}
	if version>=93:
		var flight_error:=FirstFlight.validate(body.get("first_flight"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_station_departure,staged_arrival_environment,staged_arrival_world_initialization)
		if not flight_error.is_empty():return fail(flight_error)
		staged_first_flight=body.first_flight

	var staged_desktop_text := {}
	if version>=91:
		var text_error:=DesktopText.validate(body.get("desktop_text"),int(header.source_executable_bytes),architecture,staged_arrival_staging)
		if not text_error.is_empty():return fail(text_error)
		staged_desktop_text=body.desktop_text

	var staged_mining_briefing := {}
	if version>=94:
		var briefing_error:=MiningBriefing.validate(body.get("mining_briefing"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight,staged_station_presentation,staged_desktop_text)
		if not briefing_error.is_empty():return fail(briefing_error)
		staged_mining_briefing=body.mining_briefing

	var staged_mining_drill := {}
	if version>=95:
		var drill_error:=MiningDrill.validate(body.get("mining_drill"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight)
		if not drill_error.is_empty():return fail(drill_error)
		staged_mining_drill=body.mining_drill
	var staged_mining_targeting := {}
	if version>=96:
		var targeting_error:=MiningTargeting.validate(body.get("mining_targeting"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight)
		if not targeting_error.is_empty():return fail(targeting_error)
		staged_mining_targeting=body.mining_targeting
	var staged_mining_approach := {}
	if version>=97:
		var approach_error:=MiningApproach.validate(body.get("mining_approach"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_mining_targeting)
		if not approach_error.is_empty():return fail(approach_error)
		staged_mining_approach=body.mining_approach
	var staged_mining_session := {}
	if version>=98:
		var session_error:=MiningSession.validate(body.get("mining_session"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_mining_approach,staged_mining_drill)
		if not session_error.is_empty():return fail(session_error)
		staged_mining_session=body.mining_session
	var staged_station_autopilot := {}
	if version>=102:
		var guidance_error:=StationAutopilot.validate(body.get("station_autopilot"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight)
		if not guidance_error.is_empty():return fail(guidance_error)
		staged_station_autopilot=body.station_autopilot
	var staged_station_exterior := {}
	if version>=101:
		var exterior_error:=StationExterior.validate(body.get("station_exterior"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight)
		if not exterior_error.is_empty():return fail(exterior_error)
		staged_station_exterior=body.station_exterior
		if not staged_station_exterior.is_empty() and staged_first_flight.is_empty():return fail("Station exterior requires its first flight construction")
	if not staged_station_autopilot.is_empty() and (staged_first_flight.is_empty() or staged_station_exterior.is_empty()):return fail("Station autopilot requires its first flight and station exterior")
	var staged_mining_objective := {}
	if version>=100:
		var objective_error:=MiningObjective.validate(body.get("mining_objective"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight)
		if not objective_error.is_empty():return fail(objective_error)
		staged_mining_objective=body.mining_objective
		if not staged_mining_objective.is_empty() and (staged_mining_briefing.is_empty() or staged_station_presentation.is_empty() or staged_desktop_text.is_empty()):return fail("Mining objective requires its briefing, portraits, voices and desktop text")
	var staged_flight_notices := {}
	if version>=99:
		var notice_error:=FlightNotices.validate(body.get("flight_notices"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight)
		if not notice_error.is_empty():return fail(notice_error)
		staged_flight_notices=body.flight_notices


	var staged_station_flight := {}
	if version>=103:
		var station_flight_error:=StationFlight.validate(body.get("station_flight"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight)
		if not station_flight_error.is_empty():return fail(station_flight_error)
		staged_station_flight=body.station_flight
		if not staged_station_flight.is_empty() and (staged_station_autopilot.is_empty() or staged_station_exterior.is_empty() or staged_flight_notices.is_empty()):return fail("Station flight requires its guidance, exterior and notice queue")

	var staged_station_return := {}
	if version>=104:
		var station_return_error:=StationReturn.validate(body.get("station_return"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_first_flight)
		if not station_return_error.is_empty():return fail(station_return_error)
		staged_station_return=body.station_return
		if not staged_station_return.is_empty() and (staged_station_flight.is_empty() or staged_mining_objective.is_empty() or staged_station_presentation.is_empty()):return fail("Station return requires its live flight, cargo objective and station scene")

	var staged_full_hold_departure := {}
	if version>=105:
		var full_hold_error:=FullHoldDeparture.validate(body.get("full_hold_departure"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_station_departure,staged_station_return)
		if not full_hold_error.is_empty():return fail(full_hold_error)
		staged_full_hold_departure=body.full_hold_departure

	var staged_full_hold_flight := {}
	if version>=106:
		var flight_error:=FullHoldFlight.validate(body.get("full_hold_flight"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_departure,staged_first_flight,staged_actors)
		if not flight_error.is_empty():return fail(flight_error)
		staged_full_hold_flight=body.full_hold_flight

	var staged_full_hold_pirate := {}
	if version>=107:
		var pirate_error:=FullHoldPirate.validate(body.get("full_hold_pirate"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_flight,staged_actors,staged_opening_handoff)
		if not pirate_error.is_empty():return fail(pirate_error)
		staged_full_hold_pirate=body.full_hold_pirate

	var staged_full_hold_control := {}
	if version>=108:
		var control_error:=FullHoldControl.validate(body.get("full_hold_control"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_pirate,staged_actors)
		if not control_error.is_empty():return fail(control_error)
		staged_full_hold_control=body.full_hold_control
	var staged_full_hold_destruction := {}
	if version>=109:
		var destruction_error:=FullHoldDestruction.validate(body.get("full_hold_destruction"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_control,staged_actors)
		if not destruction_error.is_empty():return fail(destruction_error)
		staged_full_hold_destruction=body.full_hold_destruction
	var staged_full_hold_story := {}
	if version>=110:
		var story_error:=FullHoldStory.validate(body.get("full_hold_story"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_flight,staged_mining_briefing,staged_mining_objective)
		if not story_error.is_empty():return fail(story_error)
		staged_full_hold_story=body.full_hold_story
	var staged_full_hold_appearance := {}
	if version>=111:
		var appearance_error:=FullHoldAppearance.validate(body.get("full_hold_appearance"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_story,staged_full_hold_destruction)
		if not appearance_error.is_empty():return fail(appearance_error)
		staged_full_hold_appearance=body.full_hold_appearance
	var staged_full_hold_return := {}
	if version>=112:
		var return_error:=FullHoldReturn.validate(body.get("full_hold_return"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_station_return,staged_full_hold_story)
		if not return_error.is_empty():return fail(return_error)
		staged_full_hold_return=body.full_hold_return
	var staged_player_destruction := {}
	if version>=113:
		var death_error:=PlayerDestruction.validate(body.get("player_destruction"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_flight,staged_actors)
		if not death_error.is_empty():return fail(death_error)
		staged_player_destruction=body.player_destruction
	var staged_game_over := {}
	if version>=114:
		var game_over_error:=GameOver.validate(body.get("game_over_presentation"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_player_destruction)
		if not game_over_error.is_empty():return fail(game_over_error)
		staged_game_over=body.game_over_presentation
	var staged_full_hold_particles := {}
	if version>=115:
		var particles_error:=FullHoldParticles.validate(body.get("full_hold_particles"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_flight,staged_player_destruction,staged_particles)
		if not particles_error.is_empty():return fail(particles_error)
		staged_full_hold_particles=body.full_hold_particles
	var staged_station_equipment := {}
	if version>=116:
		var equipment_error:=StationEquipment.validate(body.get("station_equipment"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_full_hold_return)
		if not equipment_error.is_empty():return fail(equipment_error)
		staged_station_equipment=body.station_equipment
	var staged_combat_training := {}
	if version>=117:
		var training_error:=CombatTraining.validate(body.get("combat_training"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_station_equipment,staged_actors)
		if not training_error.is_empty():return fail(training_error)
		staged_combat_training=body.combat_training
	var staged_combat_training_control := {}
	if version>=118:
		var control_error:=CombatTrainingControl.validate(body.get("combat_training_control"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_combat_training,staged_actors)
		if not control_error.is_empty():return fail(control_error)
		staged_combat_training_control=body.combat_training_control
	var staged_combat_training_weapons := {}
	if version>=119:
		var training_weapon_error:=CombatTrainingWeapons.validate(body.get("combat_training_weapons"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_combat_training,staged_combat_training_control,staged_station_equipment,staged_actors,staged_weapons)
		if not training_weapon_error.is_empty():return fail(training_weapon_error)
		staged_combat_training_weapons=body.combat_training_weapons
	var staged_combat_training_destruction := {}
	if version>=120:
		var training_death_error:=CombatTrainingDestruction.validate(body.get("combat_training_destruction"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_combat_training,staged_combat_training_control,staged_combat_training_weapons,staged_actors)
		if not training_death_error.is_empty():return fail(training_death_error)
		staged_combat_training_destruction=body.combat_training_destruction
	var staged_combat_training_visuals := {}
	if version>=121:
		var training_visual_error:=CombatTrainingVisuals.validate(body.get("combat_training_visuals"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_combat_training_weapons,staged_staging)
		if not training_visual_error.is_empty():return fail(training_visual_error)
		staged_combat_training_visuals=body.combat_training_visuals
	var staged_combat_training_story := {}
	if version>=122:
		var training_story_error:=CombatTrainingStory.validate(body.get("combat_training_story"),int(header.source_executable_bytes),architecture,staged_arrival_staging,staged_combat_training,staged_combat_training_destruction,staged_mining_briefing,staged_mining_objective,staged_dialogue,staged_full_hold_story)
		if not training_story_error.is_empty():return fail(training_story_error)
		staged_combat_training_story=body.combat_training_story
	source_architecture=architecture
	audio=staged_audio
	scenery_effects=staged_scenery_effects
	scenery_resources=staged_scenery_resources
	scenery_population=staged_scenery
	weapon_parameters = staged_weapons
	surface_material = staged_surface
	reflection_selection = staged_reflection
	environment_colors = staged_colors
	damage_particles = staged_particles
	opening_sky = staged_sky
	lod_refresh = staged_refresh
	ship_lod = staged_lod
	opening_clock = staged_opening_clock
	flight_projection = staged_projection
	opening_drift = staged_drift
	camera_follow = staged_follow
	opening_camera = staged_camera
	opening_staging = staged_staging
	opening_actors = staged_actors
	portrait_layers = staged_layers
	image_regions = staged_images
	speaker_bindings = staged_speakers
	portrait_textures = staged_portraits
	font_bindings = staged_fonts
	text_aliases = staged_aliases
	opening_dialogue = staged_dialogue
	arrival_dialogue = staged_arrival
	arrival_staging = staged_arrival_staging
	arrival_environment = staged_arrival_environment
	arrival_actor_motion = staged_arrival_actor_motion
	arrival_actor_construction = staged_arrival_actor_construction
	arrival_world_initialization = staged_arrival_world_initialization
	opening_handoff = staged_opening_handoff
	arrival_session = staged_arrival_session
	station_entry = staged_station_entry
	station_departure = staged_station_departure
	mining_drill = staged_mining_drill
	mining_targeting = staged_mining_targeting
	mining_approach = staged_mining_approach
	mining_session = staged_mining_session
	game_over_presentation = staged_game_over
	full_hold_particles = staged_full_hold_particles
	player_destruction = staged_player_destruction
	station_equipment = staged_station_equipment
	combat_training_visuals = staged_combat_training_visuals
	combat_training_story = staged_combat_training_story
	combat_training_destruction = staged_combat_training_destruction
	combat_training_weapons = staged_combat_training_weapons
	combat_training_control = staged_combat_training_control
	combat_training = staged_combat_training
	full_hold_return = staged_full_hold_return
	full_hold_appearance = staged_full_hold_appearance
	full_hold_story = staged_full_hold_story
	full_hold_destruction = staged_full_hold_destruction
	full_hold_control = staged_full_hold_control
	full_hold_pirate = staged_full_hold_pirate
	full_hold_flight = staged_full_hold_flight
	full_hold_departure = staged_full_hold_departure
	station_return = staged_station_return
	station_flight = staged_station_flight
	station_autopilot = staged_station_autopilot
	station_exterior = staged_station_exterior
	mining_objective = staged_mining_objective
	flight_notices = staged_flight_notices
	mining_briefing = staged_mining_briefing
	first_flight = staged_first_flight
	station_presentation = staged_station_presentation
	desktop_text = staged_desktop_text
	opening_loadout = staged_opening
	frame_clock = staged_clock
	vehicle_response = staged_vehicle
	pilot_response = staged_response
	manual_rotation = staged_rotation
	cruise = staged_cruise
	records = staged
	ship_lights = staged_lights
	hangars = staged_hangars
	ship_placement = staged_placement
	materials = staged_materials
	texture_variants = staged_variants
	ship_model_provenance = staged_ship_models
	ship_model_resources = staged_ship_models.get("resource_ids", [])
	base_files = base.files
	diagnostics = body.diagnostics
	binding_id = header.binding_id
	base_content_id = base.content_id
	return true


func resolve(identifier: int, kind := "") -> String:
	# Uniqueness is within recovered declarations. This does not establish that
	# this registration is active in any scene or campaign state.
	error = ""
	if materials.has(identifier) and records.has(identifier):
		fail("ID %d has conflicting resource and material declarations" % identifier)
		return ""
	if not records.has(identifier):
		fail("Resource ID %d has no recovered declaration" % identifier)
		return ""
	var alternatives := {}
	for row in records[identifier]:
		alternatives[row.resource + "|" + str(int(row.registration_type))] = row
	if alternatives.size() != 1:
		fail("Resource ID %d has multiple source declarations; active selection is unverified" % identifier)
		return ""
	var row: Dictionary = alternatives.values()[0]
	if row.registration_type != (4 if row.kind == "mesh" else 2):
		fail("Resource ID %d uses an unverified registration type" % identifier)
		return ""
	if not kind.is_empty() and kind != row.kind:
		fail("Resource ID %d does not declare the requested resource kind" % identifier)
		return ""
	if not base_files.has(row.resource) or base_files[row.resource].get("kind") != row.kind:
		fail("Resource ID %d references content absent from this base" % identifier)
		return ""
	return row.resource


func resolve_texture(identifier: int, quality := "high") -> String:
	error = ""
	if quality not in ["high", "low"]:
		fail("Unsupported texture quality preference")
		return ""
	if texture_variants.has(identifier):
		return texture_variants[identifier][quality]
	return resolve(identifier, "texture")


func resolve_font(language: String, source_mode := 0, role := "main") -> Dictionary:
	error = ""
	var choice := Fonts.choice(font_bindings, language, source_mode, role)
	if choice.is_empty():
		fail("Source font selection is unavailable for this language or mode")
		return {}
	if not base_files.has(choice.resource) or base_files[choice.resource].get("kind") != "texture":
		fail("Selected font atlas is absent from this content base")
		return {}
	return choice


func resolve_ship_model(ship_id: int) -> String:
	# Raw catalogue hull-table lookup only. Special construction paths, lights,
	# attachments and complete ship assembly are not represented by this table.
	error = ""
	if ship_id < 0 or ship_id >= ship_model_resources.size():
		fail("Ship ID %d has no recovered hull table entry in this edition" % ship_id)
		return ""
	return resolve(int(ship_model_resources[ship_id]), "mesh")


func resolve_hangar_ship(ship_id: int) -> Dictionary:
	error = ""
	if ship_placement.is_empty() or ship_id < 0 or ship_id >= ship_placement.y_positions.size():
		fail("Ship ID %d has no recovered hangar placement in this edition" % ship_id)
		return {}
	var ship := resolve_ship_layers(ship_id)
	if not ship.is_empty():
		ship.position = Vector3(0.0, float(ship_placement.y_positions[ship_id]), 0.0)
	return ship


func resolve_ship_layers(ship_id: int) -> Dictionary:
	# Body and light layers only: engine geometry, attachments, special hull
	# construction and detail selection remain separate, unsupported components.
	error = ""
	var path := resolve_ship_model(ship_id)
	if path.is_empty():
		return {}
	var lights := []
	if not ship_lights.is_empty():
		for slot in 2:
			var id := int(ship_lights.resource_ids[ship_id][slot])
			if id == 65535: continue
			var light_path := resolve(id, "mesh")
			if light_path.is_empty():
				error = "Ship %d light layer %d: " % [ship_id, slot] + error
				return {}
			lights.append({"resource_id": id, "path": light_path, "slot": slot})
	return {"ship_id": ship_id, "resource_id": int(ship_model_resources[ship_id]), "path": path,
		"lights": lights, "light_bindings_available": not ship_lights.is_empty()}


func resolve_ship_detail(ship_id: int) -> Dictionary:
	error = ""
	if ship_lod.is_empty() or ship_id < 0 or ship_id >= ship_lod.body_resource_ids.size():
		fail("Ship LOD declarations are unavailable")
		return {}
	if ship_id in [13,14,15]:
		fail("Special ship LOD construction is not implemented")
		return {}
	var full := resolve_ship_layers(ship_id)
	if full.is_empty(): return {}
	if not full.light_bindings_available:
		fail("Ship light declarations are unavailable")
		return {}
	var levels := [{"resource_id":full.resource_id,"path":full.path,"lights":full.lights}]
	for i in 2:
		var id := int(ship_lod.body_resource_ids[ship_id][i])
		if id==65535: break
		var path := resolve(id,"mesh")
		if path.is_empty():
			error = "Ship %d LOD %d: " % [ship_id,i+1] + error
			return {}
		var children := []
		var child_id := int(ship_lod.child_resource_ids[ship_id][i])
		if child_id!=65535:
			var child_path := resolve(child_id,"mesh")
			if child_path.is_empty():
				error = "Ship %d LOD %d child: " % [ship_id,i+1] + error
				return {}
			children.append({"resource_id":child_id,"path":child_path})
		levels.append({"resource_id":id,"path":path,"lights":children})
	return {"ship_id":ship_id,"levels":levels}


func resolve_hangar(station_id: int, catalogues: RefCounted) -> Dictionary:
	error = ""
	if hangars.is_empty():
		fail("This binding pack has no recovered hangar geometry declarations")
		return {}
	if catalogues.content_id != base_content_id or catalogues.tables.is_empty():
		fail("Hangar catalogues belong to a different content identity")
		return {}
	if station_id < 0 or station_id >= catalogues.tables.stations.size():
		fail("Station ID is outside this edition's catalogue")
		return {}
	var station: Dictionary = catalogues.tables.stations[station_id]
	var system: Dictionary = catalogues.tables.systems[station.system_id]
	var index := Hangars.select_row(hangars, station, system)
	if index < 0 or index >= hangars.rows.size():
		fail("Station %d has no supported hangar row" % station_id)
		return {}
	var row: Dictionary = hangars.rows[index]
	var layers := []
	for id in row.resource_ids:
		if id == -1:
			continue
		var path := resolve(int(id), "mesh")
		if path.is_empty():
			return {}
		var children := []
		for child_id in row.extra_resource_ids:
			var child_path := resolve(int(child_id), "mesh")
			if child_path.is_empty():
				return {}
			children.append({"resource_id": int(child_id), "path": child_path})
		layers.append({"resource_id": int(id), "path": path, "children": children})
	if layers.is_empty():
		fail("Station %d selects an empty source hangar row (%d); its environment is unsupported" % [station_id, index])
		return {}
	return {"station_id": station_id, "system_id": int(system.id), "row": index,
		"rotation_y": float(hangars.rotation_y), "layers": layers}


func resolve_material(identifier: int, quality := "high") -> Dictionary:
	error = ""
	if records.has(identifier):
		fail("ID %d has a conflicting resource declaration" % identifier)
		return {}
	if not materials.has(identifier):
		fail("Material ID %d has no recovered descriptor" % identifier)
		return {}
	var chosen: Dictionary = materials[identifier][0]
	for row in materials[identifier]:
		for key in ["texture_ids", "render_type", "parameter_bits"]:
			if row[key] != chosen[key]:
				fail("Material ID %d has multiple source descriptors" % identifier)
				return {}
	var paths := []
	for texture_id in chosen.texture_ids:
		var path := "" if texture_id == 65535 else resolve_texture(int(texture_id), quality)
		if texture_id != 65535 and path.is_empty():
			return {}
		paths.append(path)
	var result := chosen.duplicate(true)
	result["texture_paths"] = paths
	return result


func material_for_mesh(path: String, quality := "high") -> Dictionary:
	error = ""
	var candidates := []
	for rows in records.values():
		for row in rows:
			if row.resource == path and row.kind == "mesh" and row.registration_type == 4:
				candidates.append(row)
	if candidates.is_empty():
		fail("This mesh has no recovered material reference")
		return {}
	var material_id := int(candidates[0].get("material_id", -1))
	var flags := int(candidates[0].get("mesh_flags", -1))
	for row in candidates:
		if material_id < 0 or flags < 0 or row.get("material_id", -1) != material_id or row.get("mesh_flags", -1) != flags:
			fail("This mesh has missing or conflicting material references")
			return {}
	if flags != 0:
		fail("This mesh uses unverified material flags (%d)" % flags)
		return {}
	return resolve_material(material_id, quality)


static func bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and value >= minimum and value <= maximum and value == floor(value)


func fail(message: String) -> bool:
	error = message
	return false


func resolve_portrait_texture(identifier: int, variant := "baseline") -> String:
	error = ""
	if variant not in PortraitTextures.VARIANTS:
		fail("Unknown source portrait texture variant")
		return ""
	for row in portrait_textures.get("rows", []):
		if int(row.id) != identifier: continue
		var resource: String = row.variants[variant]
		if not base_files.has(resource) or base_files[resource].get("kind") != "texture":
			fail("Selected portrait texture is absent from this content base: " + resource)
			return ""
		return resource
	fail("Portrait texture ID has no verified source declaration")
	return ""


func resolve_speaker_name(identifier: int, library: RefCounted) -> String:
	error = ""
	if library == null or base_content_id != library.manifest.get("content_id", "") or library.active_language.is_empty() or not Library.valid_hash(binding_id):
		fail("Speaker names require the active content and language")
		return ""
	if speaker_bindings.is_empty() or identifier < 0 or identifier >= int(speaker_bindings.agent_speaker_start):
		fail("Speaker name has no supported localization binding")
		return ""
	var text_id := int(speaker_bindings.first_name_id) + identifier
	if text_id >= library.strings.size():
		fail("Speaker name is absent from the selected language")
		return ""
	return library.strings[text_id]


func resolve_speaker_portrait(identifier: int) -> Dictionary:
	error = ""
	if speaker_bindings.is_empty() or identifier < 0 or identifier >= int(speaker_bindings.fixed_speaker_count):
		fail("Speaker portrait requires an unsupported procedural or agent definition")
		return {}
	var row: Dictionary = speaker_bindings.portraits[identifier]
	if row.status != "fixed":
		fail("Speaker portrait definition is " + row.status)
		return {}
	return row.duplicate(true)


func resolve_image_region(identifier: int, texture_id := -1) -> Dictionary:
	error = ""
	var candidates := ImageRegions.candidates(image_regions, identifier, texture_id)
	if candidates.size() != 1:
		fail("Image region has conflicting source alternatives" if candidates.size() > 1 else "Image region has no supported declaration")
		return {}
	return candidates[0]

func desktop_text_id(source_id: int) -> int:
	return DesktopText.select_id(desktop_text,source_id)

static func reader_version(value: Variant) -> int:
	if not value is String or not value.begins_with("resource-registration-v"):return 0
	var suffix: String=value.trim_prefix("resource-registration-v")
	if not suffix.is_valid_int():return 0
	var version:=suffix.to_int()
	if version<1 or version>MAX_READER_VERSION or value!="resource-registration-v%d"%version:return 0
	return version
