extends "res://tests/secondary_retention.gd"
## Real detached launch/update/contact owners with the original imported burst.
## Camera sampling is tested with the retained wrappers and shared view owner.
## No earned career, full Kappa scene or fitted save is implied.
const BurstResources = preload("res://src/content/emp_detonation_resources.gd")
const BurstGeometry = preload("res://src/presentation/emp_detonation_geometry.gd")
const CombinedGeometry = preload("res://src/presentation/secondary_geometry.gd")
const BurstVisuals = preload("res://src/content/visual_library.gd")
const BurstAudio = preload("res://src/presentation/opening_audio.gd")
const BurstSounds = preload("res://src/content/audio_resources.gd")
var WHITE_BYTES := PackedByteArray([255, 255, 255, 255])
const WHITE_TINT := Vector4(1, 1, 1, 1)

func _initialize() -> void: call_deferred("run_detonations")

func run_detonations() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() in [3, 4]: await verify_detonations(args)
	else: check(false, "Expected content, bindings, visuals and optional capture directory")
	await process_frame
	print("Original EMP detonation: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

func verify_detonations(args: PackedStringArray) -> void:
	var lib := Library.new(); var bindings := Bindings.new(); var cat := Catalogues.new(); var visuals := BurstVisuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1], lib.manifest) or not cat.open(lib) or not visuals.open(args[2], lib.manifest):
		check(false, lib.error + bindings.error + cat.error + visuals.error); return
	var resources := BurstResources.new()
	if not OwnershipRules.available(bindings):
		check(not resources.configure(lib, bindings) and resources.snapshot().is_empty(), "Legacy pack enabled unsupported EMP bursts")
		return
	if not resources.configure(lib, bindings): check(false, resources.error); return
	var empty_owner := Ownership.new()
	check(empty_owner.configure(bindings, cat, equipped(bindings, cat, [])) and not empty_owner.configure_detonations(resources) and not empty_owner.has_detonations(), "An empty launcher set was reported as prepared EMP presentation")
	var data := resources.snapshot()
	check(data.effect_type == 7 and data.models.size() == 1 and data.models[0].model_id == 16805 and data.duration_ms == data.models[0].end_ms, "EMP burst lost its single original model or absolute duration")
	print("EMP burst resource metadata: ", data)
	var built := construction(bindings, cat, 0.5)
	if built == null: return
	var group := active_group(bindings, cat, built, 0)
	if group == null: return
	verify_burst_order(bindings, cat, resources, group, lib)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new(); viewport.add_child(camera); camera.current = true; camera.near = 0.1; camera.far = 1000000
	camera.position = Vector3(0, 0, 10000)
	for item_id in BurstResources.ITEM_IDS:
		await verify_item(item_id, lib, bindings, cat, visuals, resources, group, viewport, camera, args[3] if args.size() == 4 else "")
	viewport.free()

func verify_item(item_id: int, lib: RefCounted, bindings: RefCounted, cat: RefCounted, visuals: RefCounted, resources: RefCounted, initial_group: RefCounted, viewport: SubViewport, camera: Camera3D, captures: String) -> void:
	var initial := equipped(bindings, cat, [{"item_id": item_id, "slot": 0, "quantity": 1 if item_id == 41 else 2}])
	var owner := Ownership.new()
	if not owner.configure(bindings, cat, initial) or not owner.configure_detonations(resources): check(false, owner.error); return
	var group: RefCounted = initial_group.fork_for_frame()
	var slot: int = owner.snapshot().guns[0].slot_index
	check(owner.has_detonations() and owner.detonation_owner(slot) != null, "Original burst owner was not attached to the actual launcher")
	var original := owner.snapshot()
	var wrong_resources := BurstResources.new(); wrong_resources._state = resources.snapshot(); wrong_resources._state.binding_id = "0".repeat(64)
	var wrong_owner := Ownership.new()
	check(wrong_owner.configure(bindings, cat, initial) and not wrong_owner.configure_detonations(wrong_resources) and not wrong_owner.has_detonations(), "EMP presentation accepted another binding identity")
	check(not owner.configure_detonations(resources) and owner.snapshot() == original, "Repeated burst configuration changed the retained launcher")
	var geometry := BurstGeometry.new(); viewport.add_child(geometry)
	if not geometry.build(owner.detonation_owner(slot), lib, visuals, bindings): check(false, geometry.error); geometry.free(); return
	check(geometry.get_child_count() == 1 and geometry.model.get_meta("source_resource_id") == 16805 and not geometry.visible, "EMP geometry invented extra models or drew before detonation")
	var operation: Dictionary = owner.evaluate_advance(1, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	owner = operation.owner; group = operation.combat
	operation = owner.evaluate_trigger(Transform3D.IDENTITY, item_id, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	owner = operation.owner; group = operation.combat
	var launched: Dictionary = owner.snapshot()
	var origin: Vector3 = launched.guns[0].bomb.shot.position
	check(not launched.guns[0].detonation.effect.active and launched.detonation_audio.is_empty(), "Launch prematurely triggered the EMP burst")
	check(operation.events[0].audio.source_id == 6 + BurstResources.ITEM_IDS.find(item_id), "Detonation attachment changed original launch audio")
	operation = owner.evaluate_advance(10, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	owner = operation.owner; group = operation.combat
	var moved: Dictionary = owner.snapshot()
	check(moved.guns[0].bomb.shot.position != origin and moved.guns[0].detonation.cached_position == origin, "EMP wrapper did not cache the pre-movement origin")
	var invalid_pair: RefCounted = owner.detonation_owner(slot).fork()
	var pair_before: Dictionary = invalid_pair.snapshot()
	check(invalid_pair.advance(launched.guns[0].bomb, moved.guns[0].bomb, 9).is_empty() and invalid_pair.snapshot() == pair_before, "Mismatched before/after physics clocks partially advanced an EMP burst")
	var invalid_owner: RefCounted = owner.fork()
	invalid_owner._guns[0].detonation._state.projectile_id += 1
	var invalid_before: Dictionary = invalid_owner.snapshot(); var combat_before: Dictionary = group.snapshot()
	check(invalid_owner.evaluate_advance(1, group, [0, 1, 2, 3]).is_empty() and invalid_owner.snapshot() == invalid_before and owner.snapshot() == moved and group.snapshot() == combat_before, "Rejected EMP wrapper generation changed accepted physics, ammunition or combat")
	operation = owner.evaluate_trigger(Transform3D.IDENTITY, item_id, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	owner = operation.owner; group = operation.combat
	var manual: Dictionary = owner.snapshot()
	check(operation.events[0].action == "detonated" and operation.events[0].audio.is_empty() and manual.detonation_audio.is_empty() and not manual.guns[0].detonation.effect.active, "Late manual detonation started presentation in the input pass")
	verify_camera_burst(owner, group)
	operation = owner.evaluate_advance(16, group, [0, 1, 2, 3], Vector3.ZERO)
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	owner = operation.owner; group = operation.combat
	var observed: Dictionary = owner.snapshot()
	var effect: Dictionary = observed.guns[0].detonation.effect
	check(observed.guns[0].bomb.shot.is_empty() and effect.active and effect.elapsed_ms == 16, "EMP burst did not trigger and advance in its next wrapper update")
	check(effect.position == origin and effect.position != moved.guns[0].bomb.shot.position, "EMP visual origin was replaced with the newer damage pulse position")
	check(observed.detonation_audio.size() == 1 and observed.detonation_audio[0].source_id == 15 + BurstResources.ITEM_IDS.find(item_id) and observed.detonation_audio[0].position == origin and observed.detonation_audio[0].pitch_raw == 0.0, "EMP burst lost its original detonation sound or cached position")
	if item_id == 41: check(observed.guns[0].ammunition == 0 and observed.loadout.slots[slot] == null and effect.active, "A last-round EMP lost its retained burst after removing ammunition")
	verify_sound(lib, bindings, observed, item_id)
	var before_sample: Dictionary = owner.detonation_owner(slot).snapshot()
	var prepared := geometry.prepare_effect(owner.detonation_owner(slot), camera.transform, WHITE_BYTES, WHITE_TINT, 1.0)
	if prepared.is_empty(): check(false, geometry.error); geometry.free(); return
	check(not geometry.visible and owner.detonation_owner(slot).snapshot() == before_sample, "EMP preparation drew early or advanced simulation")
	var first_active_frame: Dictionary = prepared
	geometry.commit_effect(prepared)
	check(geometry.visible and geometry.model.instances.size() > 0, "Original EMP burst geometry is empty")
	var accepted_pose: Transform3D = geometry.model.instances[0].transform
	var accepted_sampler: Dictionary = geometry._sampler.snapshot()
	var invalid: RefCounted = owner.detonation_owner(slot).fork()
	invalid._state.effect.models[0].time_ms = effect.duration_ms + 1
	check(geometry.prepare_effect(invalid, camera.transform, WHITE_BYTES, WHITE_TINT, 1.0).is_empty() and geometry.model.instances[0].transform == accepted_pose and geometry._sampler.snapshot() == accepted_sampler, "Rejected EMP animation partially changed visible state")
	check(geometry.prepare_effect(owner.detonation_owner(slot), Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0)), WHITE_BYTES, WHITE_TINT, 1.0).is_empty() and geometry.visible, "Invalid EMP camera changed visibility")
	var foreign := Ownership.new()
	check(foreign.configure(bindings, cat, initial) and foreign.configure_detonations(resources) and geometry.prepare_effect(foreign.detonation_owner(slot), camera.transform, WHITE_BYTES, WHITE_TINT, 1.0).is_empty(), "EMP geometry accepted a different launcher generation")
	var target_time: int = maxi(16, int(effect.duration_ms / 3))
	operation = owner.evaluate_advance(target_time - 16, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	owner = operation.owner; group = operation.combat
	check(owner.snapshot().detonation_audio.is_empty(), "Lingering EMP effect replayed its detonation recording")
	prepared = geometry.prepare_effect(owner.detonation_owner(slot), Transform3D.IDENTITY, WHITE_BYTES, WHITE_TINT, 1.0)
	if prepared.is_empty(): check(false, geometry.error); geometry.free(); return
	geometry.commit_effect(prepared)
	var bounds := AABB(); var first := true
	for index in geometry.model.instances.size():
		var box: AABB = prepared.surfaces[index].pose * geometry.model.instances[index].get_aabb()
		bounds = box if first else bounds.merge(box); first = false
	var radius := maxf(bounds.size.length(), 10.0)
	var center := bounds.get_center()
	camera.look_at_from_position(center + Vector3(0, 0, radius), center)
	prepared = geometry.prepare_effect(owner.detonation_owner(slot), camera.transform, WHITE_BYTES, WHITE_TINT, 1.0)
	if prepared.is_empty(): check(false, geometry.error); geometry.free(); return
	geometry.commit_effect(prepared)
	var active_owner: RefCounted = owner
	var active_frame: Dictionary = prepared
	var frozen_owner: Dictionary = owner.snapshot()
	var frozen_sampler: Dictionary = geometry._sampler.snapshot()
	var frozen_pose: Transform3D = geometry.model.instances[0].transform
	var frozen_tint: Variant = geometry.model.materials[0].get_shader_parameter("effect_tint")
	var was_paused := paused
	paused = true
	for frame in 3: await process_frame
	paused = was_paused
	check(owner.snapshot() == frozen_owner and geometry.visible and geometry._sampler.snapshot() == frozen_sampler and geometry.model.instances[0].transform == frozen_pose and geometry.model.materials[0].get_shader_parameter("effect_tint") == frozen_tint, "Paused EMP burst advanced independently of its retained animation clock")
	prepared = geometry.prepare_effect(owner.detonation_owner(slot), camera.transform, WHITE_BYTES, WHITE_TINT, 1.0)
	if prepared.is_empty(): check(false, geometry.error); geometry.free(); return
	geometry.commit_effect(prepared)
	check(geometry.visible and geometry._sampler.snapshot() == frozen_sampler and geometry.model.instances[0].transform == frozen_pose and geometry.model.materials[0].get_shader_parameter("effect_tint") == frozen_tint, "Resuming an unchanged EMP frame restarted or moved its visible animation")
	# Render the production secondary assembly, not the isolated burst node.
	# The assembly stages body visibility and every retained effect together.
	geometry.hide()
	var combined := CombinedGeometry.new(); viewport.add_child(combined)
	if not combined.build(owner, lib, visuals, bindings): check(false, combined.error); combined.free(); geometry.free(); return
	var combined_frame := combined.prepare_world(owner, camera.transform)
	if combined_frame.is_empty(): check(false, combined.error); combined.free(); geometry.free(); return
	check(combined.detonations.size() == 1 and not combined.detonations[0].visible and not combined.bodies[0].visible, "Secondary assembly drew while preparing its burst")
	combined.commit_world(combined_frame)
	check(combined.detonations[0].visible and not combined.bodies[0].visible and combined.detonations[0].model.get_meta("source_resource_id") == 16805, "Secondary assembly lost the retained original burst or redrew the consumed bomb")
	var visible_pose: Transform3D = combined.detonations[0].model.instances[0].transform
	var visible_clock: Dictionary = combined.detonations[0]._sampler.snapshot()
	check(combined.prepare_world(owner).is_empty() and combined.prepare_world(owner, Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0))).is_empty() and combined.detonations[0].model.instances[0].transform == visible_pose, "Secondary assembly accepted a missing/invalid camera or changed accepted geometry")
	var missing_effect: RefCounted = owner.fork(); missing_effect._guns[0].erase("detonation")
	check(combined.prepare_world(missing_effect, camera.transform).is_empty() and combined.detonations[0].visible, "Secondary assembly silently dropped a retained burst")
	var bad_effect: RefCounted = owner.fork(); bad_effect._guns[0].detonation._state.effect.models[0].time_ms = effect.duration_ms + 1
	check(combined.prepare_world(bad_effect, camera.transform).is_empty() and combined.detonations[0]._sampler.snapshot() == visible_clock and combined.detonations[0].model.instances[0].transform == visible_pose, "Rejected secondary effect partially committed body/animation state")
	if DisplayServer.get_name() != "headless":
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image(); var background := image.get_pixel(0, 0); var foreground := 0
		for y in range(0, image.get_height(), 2):
			for x in range(0, image.get_width(), 2):
				var pixel := image.get_pixel(x, y)
				if absf(pixel.r - background.r) + absf(pixel.g - background.g) + absf(pixel.b - background.b) > 0.09: foreground += 1
		check(foreground > 100, "Original animated EMP burst did not render for item " + str(item_id))
		if not captures.is_empty():
			DirAccess.make_dir_recursive_absolute(captures)
			check(image.save_png(captures.path_join("emp-detonation-%d.png" % item_id)) == OK, "EMP capture could not be saved")
		# Use the native shared rig and actual retained wrapper commands, then
		# resample the production billboard assembly with that accepted view.
		# Bounds choose only this component-test framing, not a gameplay camera.
		var rig: RefCounted = load("res://src/simulation/camera_rig.gd").new()
		var random: RefCounted = load("res://src/simulation/seeded_random.gd").new(); random.seed_from(123)
		var sample: Dictionary = owner.evaluate_camera(random.snapshot())
		var shot := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id, "mode": "fixed_eye", "target": "player", "eye": camera.position, "inherit_target_up": true}
		var scene := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id, "player_pose": Transform3D(Basis.IDENTITY, center)}
		if sample.is_empty() or not rig.configure(bindings) or not rig.update(16, shot, scene, {}, null, sample.offset):
			check(false, owner.error + rig.error); combined.free(); geometry.free(); return
		var before_camera: Transform3D = camera.transform
		camera.transform = rig.snapshot().pose
		check(camera.position == before_camera.origin and camera.transform.basis != before_camera.basis, "Rendered EMP camera moved the eye or failed to change its aim")
		combined_frame = combined.prepare_world(owner, camera.transform)
		if combined_frame.is_empty(): check(false, combined.error); combined.free(); geometry.free(); return
		combined.commit_world(combined_frame)
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var jittered := viewport.get_texture().get_image()
		check(jittered.get_data() != image.get_data() and combined.detonations[0].visible, "Accepted EMP look jitter did not reach the rendered original burst")
		if not captures.is_empty(): check(jittered.save_png(captures.path_join("emp-camera-%d.png" % item_id)) == OK, "EMP camera capture could not be saved")
	combined.clear(); check(combined.get_child_count() == 0 and combined.bodies.is_empty() and combined.detonations.is_empty(), "Secondary assembly retained imported bodies or bursts after cleanup"); combined.free()
	geometry.show()
	var before_zero: Dictionary = owner.snapshot()
	operation = owner.evaluate_advance(0, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	check(operation.owner.snapshot() == before_zero, "Zero-duration update advanced an EMP effect or replayed audio")
	operation = owner.evaluate_advance(effect.duration_ms - target_time, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	owner = operation.owner; group = operation.combat
	var endpoint: Dictionary = owner.snapshot().guns[0].detonation.effect
	check(endpoint.active and endpoint.elapsed_ms == effect.duration_ms and endpoint.models[0].time_ms == endpoint.models[0].end_ms, "EMP burst retired at equality rather than strictly after its duration")
	prepared = geometry.prepare_effect(owner.detonation_owner(slot), camera.transform, WHITE_BYTES, WHITE_TINT, 1.0)
	if prepared.is_empty(): check(false, geometry.error); geometry.free(); return
	geometry.commit_effect(prepared)
	check(geometry.visible, "EMP geometry disappeared before the original strict animation endpoint")
	operation = owner.evaluate_advance(1, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); geometry.free(); return
	owner = operation.owner; group = operation.combat
	var retired: Dictionary = owner.snapshot()
	check(not retired.guns[0].detonation.effect.active and retired.guns[0].detonation.effect.elapsed_ms == 0 and retired.guns[0].detonation.effect.models[0].time_ms == retired.guns[0].detonation.effect.models[0].start_ms and retired.detonation_audio.is_empty(), "EMP retirement failed to reset its model clock without replaying sound")
	prepared = geometry.prepare_effect(owner.detonation_owner(slot), camera.transform, WHITE_BYTES, WHITE_TINT, 1.0)
	if prepared.is_empty(): check(false, geometry.error); geometry.free(); return
	geometry.commit_effect(prepared)
	check(not geometry.visible, "Retired EMP burst remained visible")
	geometry.commit_effect(active_frame)
	check(not geometry.visible, "A retained active frame revived the retired EMP burst")
	var preserved: Dictionary = owner.snapshot()
	check(owner.evaluate_advance(2147483647, group, [0, 1, 2, 3]).is_empty() and owner.snapshot() == preserved, "Rejected EMP update changed accepted ammunition or burst state")
	if item_id != 41:
		var wait: int = maxi(0, int(retired.guns[0].bomb.weapon.interval_ms) + 1 - int(retired.guns[0].bomb.elapsed_ms))
		operation = owner.evaluate_advance(wait, group, [0, 1, 2, 3])
		if operation.is_empty(): check(false, owner.error); geometry.free(); return
		owner = operation.owner; group = operation.combat
		operation = owner.evaluate_trigger(Transform3D.IDENTITY, item_id, group, [0, 1, 2, 3])
		if operation.is_empty(): check(false, owner.error); geometry.free(); return
		owner = operation.owner
		var next_shot: Dictionary = owner.snapshot().guns[0]
		check(next_shot.bomb.shot.id == 2 and next_shot.detonation.projectile_id == 2 and not next_shot.detonation.triggered and not next_shot.detonation.effect.active and next_shot.ammunition == 0, "Reused EMP wrapper did not reset for its new last-round generation")
	verify_burst_expiry(item_id, bindings, cat, resources, initial_group)
	if item_id == 41:
		verify_geometry_rebuild(geometry, active_owner.detonation_owner(slot), first_active_frame, lib, visuals, bindings, camera.transform)
	geometry.clear(); check(geometry.get_child_count() == 0 and geometry.model == null, "EMP geometry retained imported instances after cleanup")
	geometry.free()

func verify_geometry_rebuild(geometry: Node3D, active: RefCounted, previous_frame: Dictionary, lib: RefCounted, visuals: RefCounted, bindings: RefCounted, camera: Transform3D) -> void:
	var old_model: WeakRef = weakref(geometry.model)
	var old_surface: WeakRef = weakref(geometry.model.instances[0])
	var old_material: WeakRef = weakref(geometry.model.materials[0])
	var old_mesh: WeakRef = weakref(geometry.model.instances[0].mesh)
	if not geometry.build(active, lib, visuals, bindings): check(false, geometry.error); return
	check(old_model.get_ref() == null and old_surface.get_ref() == null and old_material.get_ref() == null and old_mesh.get_ref() == null and geometry.get_child_count() == 1, "Repeated EMP burst build retained replaced mesh resources")
	geometry.commit_effect(previous_frame)
	check(not geometry.visible, "A frame from the previous EMP build redrew its replaced burst")
	var current: Dictionary = geometry.prepare_effect(active, camera, WHITE_BYTES, WHITE_TINT, 1.0)
	if current.is_empty(): check(false, geometry.error); return
	geometry.commit_effect(current)
	check(geometry.visible, "Rebuilt EMP burst rejected its new accepted animation frame")
	old_model = weakref(geometry.model); old_surface = weakref(geometry.model.instances[0])
	old_material = weakref(geometry.model.materials[0]); old_mesh = weakref(geometry.model.instances[0].mesh)
	geometry.clear()
	geometry.commit_effect(current)
	check(not geometry.visible and geometry.model == null and geometry.get_child_count() == 0, "A pending EMP frame revived geometry after cleanup")
	check(old_model.get_ref() == null and old_surface.get_ref() == null and old_material.get_ref() == null and old_mesh.get_ref() == null, "EMP cleanup retained imported model or material resources")
	geometry.clear(); check(geometry.get_child_count() == 0 and not geometry.visible, "Repeated EMP cleanup recreated visible resources")

func verify_burst_expiry(item_id: int, bindings: RefCounted, cat: RefCounted, resources: RefCounted, initial_group: RefCounted) -> void:
	var owner := Ownership.new()
	var initial := equipped(bindings, cat, [{"item_id": item_id, "slot": 0, "quantity": 1}])
	if not owner.configure(bindings, cat, initial) or not owner.configure_detonations(resources): check(false, owner.error); return
	var group: RefCounted = initial_group.fork_for_frame()
	var operation: Dictionary = owner.evaluate_advance(1, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner; group = operation.combat
	operation = owner.evaluate_trigger(Transform3D.IDENTITY, item_id, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner; group = operation.combat
	var launched: Dictionary = owner.snapshot().guns[0].bomb.shot
	operation = owner.evaluate_advance(launched.remaining_ms, group, [0, 1, 2, 3], Vector3.ZERO)
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner; group = operation.combat
	var state: Dictionary = owner.snapshot()
	check(operation.events.size() == 1 and operation.events[0].action == "detonated" and operation.events[0].blast.position != launched.position, "Automatic EMP expiry did not retain its full-step damage pulse")
	check(state.guns[0].detonation.effect.position == launched.position and state.detonation_audio.size() == 1 and state.detonation_audio[0].position == launched.position, "Automatic EMP expiry confused visual and hit positions")
	check(state.guns[0].detonation.effect.active == (launched.remaining_ms <= state.guns[0].detonation.effect.duration_ms), "Large EMP frame lost same-update animation retirement")
	operation = owner.evaluate_advance(1, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	check(operation.owner.snapshot().detonation_audio.is_empty(), "Repeated expiry flag restarted the EMP burst")

func verify_burst_order(bindings: RefCounted, cat: RefCounted, resources: RefCounted, initial_group: RefCounted, lib: RefCounted) -> void:
	var owner := Ownership.new()
	var ship_id := -1; var slot_count := 0
	for row in cat.tables.ships:
		if row.stats.primary_slots > 0 and row.stats.secondary_slots > slot_count:
			ship_id = int(row.id); slot_count = int(row.stats.secondary_slots)
	if slot_count < 2: check(false, "Catalogue has no multi-secondary test hull"); return
	var items: Array = BurstResources.ITEM_IDS.slice(0, mini(3, slot_count))
	var entries := []
	for index in items.size(): entries.append({"item_id": items[index], "slot": index, "quantity": 1})
	var initial := equipped(bindings, cat, entries, ship_id)
	print("EMP multi-launcher fixture: original ship ", ship_id, "; fitted slots: ", items.size())
	if not owner.configure(bindings, cat, initial) or not owner.configure_detonations(resources): check(false, owner.error); return
	var group: RefCounted = initial_group.fork_for_frame()
	var operation: Dictionary = owner.evaluate_advance(1, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner; group = operation.combat
	for item_id in items:
		operation = owner.evaluate_trigger(Transform3D.IDENTITY, item_id, group, [0, 1, 2, 3])
		if operation.is_empty(): check(false, owner.error); return
		owner = operation.owner; group = operation.combat
		check(operation.events.size() == 1 and operation.events[0].action == "launched", "Earlier selected launch did not preserve later live EMP wrappers")
		operation = owner.evaluate_advance(10, group, [0, 1, 2, 3])
		if operation.is_empty(): check(false, owner.error); return
		owner = operation.owner; group = operation.combat
	var live: Dictionary = owner.snapshot()
	check(live.guns.size() == items.size() and live.guns.all(func(gun): return gun.bomb.shot.get("phase") == "flying" and gun.ammunition == 0), "Multi-launcher fixture did not retain all last-round projectiles")
	operation = owner.evaluate_trigger(Transform3D.IDENTITY, -1, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner; group = operation.combat
	var expected_firing := items.duplicate(); expected_firing.reverse()
	check(operation.events.map(func(event): return event.item_id) == expected_firing and owner.snapshot().detonation_audio.is_empty(), "Multi-launcher manual pulses changed firing order or played burst sounds early")
	operation = owner.evaluate_advance(16, group, [0, 1, 2, 3], Vector3.ZERO)
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner
	var observed: Dictionary = owner.snapshot()
	check(observed.detonation_camera.map(func(command): return command.item_id) == items, "EMP camera writes lost forward wrapper creation order")
	verify_camera_retirement_order(bindings, cat, resources, initial_group, initial, items)
	var expected_sounds := items.map(func(id): return BurstResources.SOUND_IDS[BurstResources.ITEM_IDS.find(id)])
	check(observed.detonation_audio.map(func(cue): return cue.source_id) == expected_sounds, "EMP burst audio did not follow forward wrapper creation order")
	var audio := BurstAudio.new(); root.add_child(audio)
	if audio.configure(lib, bindings, 730):
		var routed := audio.prepare_secondaries({"secondaries": observed, "secondary_events": []})
		check(not routed.is_empty() and routed.operations.map(func(op): return op.source_id) == expected_sounds, "Combat audio reordered simultaneous retained EMP bursts")
		var wrong_order := observed.duplicate(true); wrong_order.detonation_audio.reverse()
		check(audio.prepare_secondaries({"secondaries": wrong_order, "secondary_events": []}).is_empty(), "Combat audio accepted reversed wrapper sound order")
	else: check(false, audio.error)
	audio.clear(); audio.free()
	for index in live.guns.size():
		check(observed.guns[index].detonation.effect.position == live.guns[index].detonation.cached_position and observed.guns[index].detonation.effect.active, "A retained EMP wrapper borrowed another projectile's visual origin")

func verify_camera_burst(pending: RefCounted, group: RefCounted) -> void:
	var accepted: Dictionary = pending.snapshot(); var combat_before: Dictionary = group.snapshot()
	check(pending.evaluate_advance(16, group, [0, 1, 2, 3]).is_empty(), "A new EMP camera burst invented a missing player position")
	check(pending.evaluate_advance(16, group, [0, 1, 2, 3], Vector3(NAN, 0, 0)).is_empty(), "EMP camera accepted a non-finite observer")
	check(pending.snapshot() == accepted and group.snapshot() == combat_before, "Rejected EMP observation changed accepted physics or targets")
	var origin: Vector3 = accepted.guns[0].detonation.cached_position
	for distance in [0, 15000, 30000, 45000]:
		var branch: Dictionary = pending.evaluate_advance(16, group, [0, 1, 2, 3], origin + Vector3(distance, 0, 0))
		if branch.is_empty(): check(false, pending.error); return
		var owner: RefCounted = branch.owner
		var state: Dictionary = owner.snapshot()
		var camera_state: Dictionary = state.guns[0].detonation.camera
		var expected := maxf(0.0, 1.0 - float(distance) / 30000.0)
		check(camera_state.initial_strength == expected and camera_state.elapsed_ms == 16 and camera_state.spread == 50 and is_equal_approx(camera_state.strength, expected * 0.992), "EMP camera lost captured distance falloff or same-update decay")
		var random: RefCounted = load("res://src/simulation/seeded_random.gd").new(); random.seed_from(123)
		var seed: Dictionary = random.snapshot()
		var expected_offset := Vector3.ZERO
		if expected > 0.0:
			for axis in 3: expected_offset[axis] = PackedFloat32Array([float(random.next_int(100) - 50) * float(camera_state.strength)])[0]
		var sample: Dictionary = owner.evaluate_camera(seed)
		check(not sample.is_empty() and sample.offset == expected_offset and sample.random_state == random.snapshot(), "EMP camera did not consume exactly three ordinary-view random samples, or sampled at zero amplitude")
		check(owner.snapshot() == state and owner.evaluate_camera(seed) == sample, "Prospective camera sampling changed a retained wrapper or random input")
		check(owner.evaluate_camera({}).is_empty() and owner.snapshot() == state, "EMP camera accepted a missing random stream")
		var later: Dictionary = owner.evaluate_advance(1, branch.combat, [0, 1, 2, 3], origin + Vector3(60000, 0, 0))
		if later.is_empty(): check(false, owner.error); return
		check(later.owner.snapshot().guns[0].detonation.camera.initial_strength == expected, "EMP camera resampled attenuation after the player moved")
		var faded: Dictionary = owner.evaluate_advance(2000 - 16, branch.combat, [0, 1, 2, 3])
		if faded.is_empty(): check(false, owner.error); return
		var fade_state: Dictionary = faded.owner.snapshot().guns[0].detonation
		check(fade_state.camera.strength == 0.0 and fade_state.camera.elapsed_ms == (2000 if fade_state.effect.active else 0), "EMP camera exceeded its two-second decay or failed to reset on effect retirement")
		check(faded.owner.evaluate_camera(seed).random_state == seed, "Expired camera strength consumed world randomness")

func verify_camera_retirement_order(bindings: RefCounted, cat: RefCounted, resources: RefCounted, group: RefCounted, initial: Dictionary, items: Array) -> void:
	var owner := Ownership.new()
	if not owner.configure(bindings, cat, initial) or not owner.configure_detonations(resources): check(false, owner.error); return
	var operation: Dictionary = owner.evaluate_advance(1, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner
	operation = owner.evaluate_trigger(Transform3D.IDENTITY, int(items.back()), group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner
	var old: Dictionary = owner.snapshot().guns[0]
	operation = owner.evaluate_contact(old.slot_index, old.bomb.shot.id, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner; group = operation.combat
	operation = owner.evaluate_advance(resources.snapshot().duration_ms, group, [0, 1, 2, 3], Vector3.ZERO)
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner; group = operation.combat
	check(owner.snapshot().guns[0].detonation.effect.active, "Older camera wrapper retired before its strict endpoint")
	operation = owner.evaluate_trigger(Transform3D.IDENTITY, int(items.front()), group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner
	var young: Dictionary = owner.snapshot().guns.back()
	if young.bomb.shot.is_empty(): check(false, "Camera ordering fixture did not launch its younger bomb"); return
	operation = owner.evaluate_contact(young.slot_index, young.bomb.shot.id, group, [0, 1, 2, 3])
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner; group = operation.combat
	operation = owner.evaluate_advance(1, group, [0, 1, 2, 3], Vector3.ZERO)
	if operation.is_empty(): check(false, owner.error); return
	owner = operation.owner
	var state: Dictionary = owner.snapshot()
	check(state.guns.back().detonation.camera.strength > 0.0 and state.detonation_camera.back().strength == 0.0 and state.detonation_camera.back().spread == 0, "Later wrapper retirement did not reset an earlier active camera write")
	var random: RefCounted = load("res://src/simulation/seeded_random.gd").new(); random.seed_from(321)
	var sample: Dictionary = owner.evaluate_camera(random.snapshot())
	check(not sample.is_empty() and sample.offset == Vector3.ZERO and sample.random_state == random.snapshot(), "EMP camera added or maximized simultaneous effects instead of using the last write")
	var corrupted: RefCounted = owner.fork(); corrupted._camera_commands.reverse()
	check(corrupted.evaluate_camera(random.snapshot()).is_empty() and owner.snapshot() == state, "EMP camera accepted reversed wrapper commands or mutated the accepted owner")

func verify_sound(lib: RefCounted, bindings: RefCounted, owner_state: Dictionary, item_id: int) -> void:
	var cues: Array = owner_state.detonation_audio
	var resources := BurstSounds.new()
	if not resources.configure(lib, bindings): check(false, resources.error); return
	var id: int = 15 + BurstResources.ITEM_IDS.find(item_id)
	var clip: Dictionary = resources.prepare(id)
	check(not clip.is_empty() and not clip.has("unsupported") and not clip.get("looping", true), "Original detonation recording is unsupported: " + str(id) + " " + str(clip.get("unsupported", resources.error)))
	if clip.is_empty() or clip.has("unsupported"): return
	var audio := BurstAudio.new(); root.add_child(audio)
	if not audio.configure(lib, bindings, 730): check(false, audio.error); audio.free(); return
	audio.set_paused(true)
	var initial: Dictionary = audio.snapshot()
	var frame := {"elapsed_ms": 0, "camera": {"view": {"pose": Transform3D.IDENTITY}}}
	var combat := {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id, "elapsed_ms": 0, "actor_events": [], "secondaries": owner_state, "secondary_events": []}
	# Exercise the same combat adapter used by prepare_full_hold, rather than
	# injecting a burst into generic opening/cinematic audio commands.
	var prepared: Dictionary = audio.prepare_frame(0, frame, combat)
	check(not prepared.is_empty() and audio.snapshot() == initial, "Preparing original EMP detonation sound changed playback early")
	if prepared.is_empty(): check(false, audio.error); audio.free(); return
	check(prepared.operations.size() == 1 and prepared.operations[0].source_id == id and prepared.operations[0].item_id == item_id and prepared.operations[0].secondary_slot == owner_state.guns[0].slot_index, "Whole-frame combat audio lost its retained launcher or emitted extra sounds")
	for corruption in ["source", "position", "duplicate", "missing_cues", "missing_owner", "identity", "pitch"]:
		var bad := combat.duplicate(true)
		match corruption:
			"source": bad.secondaries.detonation_audio[0].source_id = 6
			"position": bad.secondaries.detonation_audio[0].position = Vector3(NAN, 0, 0)
			"duplicate": bad.secondaries.detonation_audio.append(bad.secondaries.detonation_audio[0].duplicate(true))
			"missing_cues": bad.secondaries.erase("detonation_audio")
			"missing_owner": bad.secondaries.guns[0].erase("detonation")
			"identity": bad.secondaries.guns[0].detonation.binding_id = "0".repeat(64)
			"pitch": bad.secondaries.detonation_audio[0].pitch_raw = 0.25
		check(audio.prepare_frame(0, frame, bad).is_empty() and audio.snapshot() == initial, "Rejected combat EMP cue changed playback: " + corruption)
	audio.commit_frame(prepared)
	var active: Dictionary = audio.snapshot()
	check(active.unsupported.is_empty() and active.active.has(id) and active.active[id].source_index == clip.source_index and active.active[id].position == cues[0].position and active.active[id].paused, "EMP detonation sound lost its decoded recording, spatial origin or pause")
	audio.commit_frame(prepared)
	check(audio.snapshot() == active, "Replayed accepted EMP sound frame started another recording")
	var repeated := audio.prepare_frame(0, frame, combat); audio.commit_frame(repeated)
	check(audio.snapshot() == active, "Repeated presentation revision replayed retained EMP cues")
	var lingering := combat.duplicate(true); lingering.elapsed_ms = 1; lingering.secondaries.detonation_audio = []
	frame.elapsed_ms = 1
	var quiet := audio.prepare_frame(1, frame, lingering)
	check(not quiet.is_empty() and quiet.operations.is_empty(), "Lingering effect generated a new detonation sound without a wrapper cue")
	print("EMP detonation sound: ", id, "; original sample: ", clip.source_index)
	audio.clear(); check(audio.get_child_count() == 0, "EMP detonation playback survived cleanup"); audio.free()
