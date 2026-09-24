extends SceneTree
## Original Unicode text must shape with its source-declared bitmap glyphs.
const Metrics = preload("res://src/content/image_font.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Frontend = preload("res://src/presentation/player_frontend.gd")
const EquipmentPanel = preload("res://src/presentation/station_equipment_panel.gd")
var checks := 0
var failures := 0
var captures := ""

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [3, 4]:
		check(false, "Expected content, bindings, visuals and optional captures"); quit(1); return
	captures = args[3] if args.size() == 4 else ""
	var library := Library.new(); var bindings := Bindings.new(); var visuals := Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1], library.manifest) or not visuals.open(args[2], library.manifest):
		check(false, library.error + bindings.error + visuals.error); quit(1); return
	var aliases := {}
	for row in bindings.text_aliases.aliases: aliases[int(row[0])] = int(row[1])
	check(aliases.size() == 20, "The source character-alias declaration is unavailable")
	for language in Frontend.Preferences.LANGUAGES:
		if not library.select_language(language): check(false, library.error); continue
		var metrics := Metrics.new()
		if not metrics.open_selected(library, bindings): check(false, metrics.error); continue
		var font := metrics.create_font(visuals)
		if font == null: check(false, metrics.error); continue
		var height: int = font.get_meta("source_height")
		var cache := Vector2i(height, 0)
		var before: Dictionary = metrics.glyphs.duplicate()
		for code in aliases:
			var target: int = aliases[code]
			if not before.has(target): continue
			check(font.has_char(code), "%s missing source alias U+%04X → U+%04X" % [language, code, target])
			# Do not query absent cache entries: Godot creates empty glyph entries
			# for some cache getters, which would hide the actual fallback defect.
			if not font.has_char(code): continue
			var glyph: int = font.get_glyph_index(height, code, 0)
			check(font.get_glyph_uv_rect(0, cache, glyph) == Rect2(before[target]) and font.get_glyph_size(0, cache, glyph) == Vector2(before[target].size), "%s alias U+%04X selects another glyph rectangle" % [language, code])
			check(font.get_glyph_offset(0, cache, glyph) == Vector2(0, -height) and font.get_glyph_advance(0, height, glyph) == Vector2(metrics.advance(target), 0), "%s alias U+%04X changes the source baseline/advance" % [language, code])
		var preserved := true
		for code in before:
			if aliases.has(code): continue
			var glyph: int = font.get_glyph_index(height, code, 0)
			if font.get_glyph_uv_rect(0, cache, glyph) != Rect2(before[code]) or font.get_glyph_advance(0, height, glyph) != Vector2(metrics.advance(code), 0): preserved = false
		check(preserved and metrics.glyphs == before, language + " changed unaliased source glyphs or timing metrics")
		var sample := source_sample(library)
		for size in [14, 20, 24]:
			var line := TextLine.new(); line.add_string(sample, font, size); line.get_size()
			var own := font.get_rids(); var foreign := 0
			var shaped := TextServerManager.get_primary_interface().shaped_text_get_glyphs(line.get_rid())
			check(not shaped.is_empty(), "%s %dpx text did not shape any glyphs" % [language, size])
			for glyph in shaped:
				if glyph.font_rid not in own: foreign += 1
			check(foreign == 0, "%s %dpx source UI text uses %d fallback glyphs" % [language, size, foreign])
			check(font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, size).is_equal_approx(font.get_string_size(substitute(sample, aliases), HORIZONTAL_ALIGNMENT_LEFT, -1, size)), "%s %dpx Unicode text has different source-alias advances" % [language, size])
		if language == "ru":
			print("Russian original font: %s; height=%d; raw glyphs=%d; aliases=%d" % [metrics.resource, height, metrics.glyphs.size(), aliases.size()])
			await capture_comparison(library, bindings, visuals, font, aliases)
	await verify_equipment_theme_reconfiguration(library, bindings, visuals)
	# Reopening a raw atlas must not retain aliases from a prior bound selection.
	var reopened := Metrics.new(); check(reopened.open_selected(library, bindings), reopened.error)
	var resource: String = reopened.resource; var choice: Dictionary = bindings.resolve_font(library.active_language)
	check(reopened.open(library, resource, choice.font_group, choice.spacing), reopened.error)
	var raw_font := reopened.create_font(visuals)
	var raw_only := true
	for code in aliases:
		if not reopened.glyphs.has(code) and raw_font.has_char(code): raw_only = false
	check(raw_only, "Raw font reopening retained another binding's aliases")
	print("Original font rendering: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

func verify_equipment_theme_reconfiguration(library: RefCounted, bindings: RefCounted, visuals: RefCounted) -> void:
	var panel := EquipmentPanel.new(); root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.visible = true
	for language in ["gb", "de", "ru", "gb"]:
		if not library.select_language(language) or not panel.configure(library, bindings, visuals):
			check(false, "Hangar original-font reconfiguration failed: " + library.error + panel.error); break
		check(panel._panel.theme.default_font == panel._art.font and panel._art.font.get_meta("source_resource") == bindings.resolve_font(language).resource,
			"Hangar changed or lost its imported original font: " + language)
		await process_frame
	check(panel.configure(library, bindings) and panel._panel.theme == null,
		"Text-only hangar retained a previous imported font")
	await process_frame
	check(panel.configure(library, bindings, visuals) and panel._panel.theme.default_font == panel._art.font,
		"Hangar did not restore the original font after text-only configuration")
	panel.free(); await process_frame

func source_sample(library: RefCounted) -> String:
	var pieces := PackedStringArray()
	for index in [31, 36, 489, 178]: pieces.append(library.strings[index])
	return "   ".join(pieces)

func substitute(value: String, aliases: Dictionary) -> String:
	var result := ""
	for character in value: result += String.chr(aliases.get(character.unicode_at(0), character.unicode_at(0)))
	return result

func capture_comparison(library: RefCounted, bindings: RefCounted, visuals: RefCounted, font: FontFile, aliases: Dictionary) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(1120, 560)
	var canvas := Control.new(); root.add_child(canvas); canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sample := source_sample(library); var regions := []
	for i in 3:
		var size: int = [14, 20, 24][i]; var y := 16 + i * 176
		var caption := Label.new(); caption.text = "%d px — Russian Unicode / source glyph aliases / Latin reference" % size
		caption.position = Vector2(24, y); canvas.add_child(caption)
		for row in 3:
			var label := Label.new(); label.position = Vector2(24, y + 36 + row * 44); label.size = Vector2(1060, 36)
			label.add_theme_font_override("font", font); label.add_theme_font_size_override("font_size", size)
			label.text = sample if row == 0 else substitute(sample, aliases) if row == 1 else "Options   Voice   Invert controls   Back"
			canvas.add_child(label)
			if row < 2: regions.append(Rect2i(label.position, label.size))
	for tick in 3: await process_frame
	var picture := await capture("russian-glyph-comparison")
	for i in 3: check(picture.get_region(regions[i * 2]).get_data() == picture.get_region(regions[i * 2 + 1]).get_data(), "Rendered Russian and source aliases differ at %dpx" % [14, 20, 24][i])
	canvas.free(); await process_frame
	var app := Frontend.new(); root.add_child(app); app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.library = library; app.bindings = bindings; app.visuals = visuals
	check(app.menu.configure(library, bindings, visuals), app.menu.error)
	root.size = Vector2i(1280, 720); app.set_mobile_layout(false); app._details.hide(); app.menu.present(false, false)
	for tick in 3: await process_frame
	await capture("russian-menu-desktop")
	for mobile in [false, true]:
		root.size = Vector2i(844, 390) if mobile else Vector2i(1280, 720)
		app.set_mobile_layout(mobile); app.show_options()
		for tick in 3: await process_frame
		app._settings_controls["touch_controls" if mobile else "mouse_sensitivity"].grab_focus()
		for tick in 3: await process_frame
		app._settings_controls.voice.grab_focus()
		for tick in 3: await process_frame
		await capture("russian-options-" + ("touch" if mobile else "desktop"))
	app.free(); await process_frame

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	var image := root.get_texture().get_image()
	check(image.save_png(captures.path_join(name + ".png")) == OK, "Could not capture original font rendering")
	return image

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
