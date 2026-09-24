extends "res://tests/secondary_weapons.gd"
## Focused landscape layout around real detached ammunition ownership. This
## does not fit a player ship, advance a mission or produce an earned save.
const WeaponPanel = preload("res://src/presentation/secondary_weapon_panel.gd")
const Visuals = preload("res://src/content/visual_library.gd")
var _menu_confirmations := []
var _menu_cancellations := 0

func _initialize() -> void: call_deferred("run_panel")

func run_panel() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [3, 4]: check(false, "Expected content, bindings, visuals and optional captures")
	else: await verify_panel(args)
	await process_frame
	print("Secondary panel landscape: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

func verify_panel(args: PackedStringArray) -> void:
	var lib := Library.new()
	var bindings := Bindings.new()
	var cat := Catalogues.new()
	var visuals := Visuals.new()
	if not lib.open(args[0]) or not bindings.open(args[1], lib.manifest) or not cat.open(lib) or not visuals.open(args[2], lib.manifest):
		check(false, lib.error + bindings.error + cat.error + visuals.error); return
	var ship := -1
	for row in cat.tables.ships:
		if row.stats.primary_slots > 0 and row.stats.secondary_slots >= 3: ship = int(row.id); break
	if ship < 0: check(false, "No imported hull supports the three-launcher layout"); return
	var owner := Ownership.new()
	if not owner.configure(bindings, cat, equipped(bindings, cat, [
		{"item_id": 41, "slot": 0, "quantity": 2},
		{"item_id": 42, "slot": 1, "quantity": 3},
		{"item_id": 43, "slot": 2, "quantity": 4}], ship)):
		check(false, owner.error); return
	var sample: Dictionary = owner.selection_feedback(-1)
	var retained: Dictionary = owner.snapshot()
	var panel := WeaponPanel.new()
	root.add_child(panel)
	root.content_scale_size = Vector2i.ZERO
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.selection_requested.connect(func(id): _menu_confirmations.append(id))
	panel.selection_cancelled.connect(func(): _menu_cancellations += 1)
	for language in lib.manifest.languages:
		if not lib.select_language(language) or not panel.configure(lib, bindings, visuals) or not panel.present(sample):
			check(false, lib.error + panel.error); continue
		check(panel.matches_context(lib, bindings, visuals), "Prepared menu lost its language/artwork identity")
		check(panel._menu_title.text == lib.strings[255] and panel._menu_confirm.text == lib.strings[130] and panel._menu_cancel.text == lib.strings[414], "Menu actions did not use the current original localization")
		var selected_font: Dictionary = bindings.resolve_font(language, 0, "main")
		check(panel._menu.theme.default_font.get_meta("source_resource") == selected_font.resource, "Menu lost the active original bitmap font")
		for mobile in [false, true]:
			panel.close_selection()
			panel.set_mobile_layout(mobile)
			panel.set_interaction(true, mobile)
			root.size = Vector2i(844, 390) if mobile else Vector2i(640, 360)
			await process_frame
			check(panel.open_selection(), panel.error)
			for tick in 3: await process_frame
			var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
			check(viewport.encloses(panel._menu.get_global_rect()), "Secondary menu escaped %s landscape %s" % [language, root.size])
			check(panel._menu.get_theme_stylebox("panel") is StyleBoxTexture and panel._menu.get_theme_stylebox("panel").get_meta("source_image_ids") == panel._art.styles[mobile].panel.get_meta("source_image_ids"), "Selection dropped the verified original panel artwork")
			for button in [panel._menu_confirm, panel._menu_cancel]:
				check(viewport.encloses(button.get_global_rect()), "Secondary confirmation became unreachable in " + language)
				check(button.size.y >= (56 if mobile else 42) and button.get_theme_stylebox("normal") is StyleBoxTexture, "Menu action lost its target size or original button artwork")
			check(panel.snapshot().touch_controls == mobile, "Desktop unexpectedly exposed flight touch actions")
			check(panel._menu_rows.get_child(3).text == lib.strings[275], "Explicit unselected row is not localized")
			verify_highlight_visible(panel, language)
			var down := InputEventKey.new(); down.physical_keycode = KEY_DOWN; down.pressed = true
			panel.handle_selection_event(down); down.pressed = false; panel.handle_selection_event(down)
			for tick in 2: await process_frame
			check(panel.selection_snapshot().highlighted_item_id == sample.weapons[0].item_id, "Keyboard browsing lost equipped order")
			verify_highlight_visible(panel, language)
			if language == "gb":
				await click_menu_button(panel._menu_confirm)
				check(_menu_confirmations == [sample.weapons[0].item_id] and panel.snapshot().state == sample, "Visible confirmation failed to emit the preview choice exactly once")
				_menu_confirmations.clear()
			var up := InputEventJoypadButton.new(); up.button_index = JOY_BUTTON_DPAD_UP; up.pressed = true
			panel.handle_selection_event(up); up.pressed = false; panel.handle_selection_event(up)
			for tick in 2: await process_frame
			check(panel.selection_snapshot().highlighted_item_id == -1, "Controller browsing lost the unselected choice")
			verify_highlight_visible(panel, language)
			check(_menu_confirmations.is_empty() and _menu_cancellations == 0 and panel.snapshot().state == sample, "Scrolling committed or cancelled gameplay")
			if args.size() == 4 and DisplayServer.get_name() != "headless" and language in ["gb", "ru", "ja", "zs"]:
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute(args[3])
				var image := root.get_texture().get_image()
				check(image != null and image.save_png(args[3].path_join("secondary-" + language + ("-touch" if mobile else "-desktop") + ".png")) == OK, "Cannot capture original secondary menu")
	check(owner.snapshot() == retained and panel.snapshot().state == sample, "Layout changed accepted ammunition or selection")
	# Failed preparation must not replace accepted art or content. Supplying
	# visuals later upgrades an earlier text-only context instead of reusing it.
	var accepted_art: RefCounted = panel._art
	var bad_visuals := Visuals.new(); bad_visuals.base_content_id = "f".repeat(64)
	check(not panel.configure(lib, bindings, bad_visuals) and panel._art == accepted_art and panel.snapshot().state == sample, "Rejected artwork changed the accepted menu")
	check(panel.configure(lib, bindings) and not panel.matches_context(lib, bindings, visuals) and panel._menu.theme == null, "Two-argument context retained another language's bitmap artwork")
	panel.free()

func verify_highlight_visible(panel: Control, language: String) -> void:
	var selected: int = panel.selection_snapshot().highlighted_item_id
	var choices: Array = panel.selection_snapshot().choices
	for index in choices.size():
		if choices[index].item_id == selected:
			var row: Button = panel._menu_rows.get_child(index)
			check(panel._menu_scroll.get_global_rect().encloses(row.get_global_rect()), "Highlighted choice cannot be seen after scrolling: " + language)
			check(row.button_pressed and row.get_theme_stylebox("pressed") is StyleBoxTexture, "Original selected button state disappeared")
			return
	check(false, "Menu highlight refers to no equipped choice")

func click_menu_button(button: Button) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = button.get_global_rect().get_center(); click.global_position = click.position
	click.pressed = true; root.push_input(click); await process_frame
	click = click.duplicate(); click.pressed = false
	root.push_input(click); await process_frame
