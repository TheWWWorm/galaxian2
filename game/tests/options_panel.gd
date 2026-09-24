extends SceneTree
## Actual options controls with matching imported art, without starting a career.
const Frontend = preload("res://src/presentation/player_frontend.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
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
	if not library.open(args[0]) or not bindings.open(args[1], library.manifest) or not library.select_language("gb") or not visuals.open(args[2], library.manifest):
		check(false, library.error + bindings.error + visuals.error); quit(1); return
	root.content_scale_size = Vector2i.ZERO
	var app := Frontend.new(); root.add_child(app); app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.library = library; app.bindings = bindings; app.visuals = visuals
	if not app.menu.configure(library, bindings, visuals):
		check(false, app.menu.error); app.free(); quit(1); return
	var preferences: Dictionary = app.preferences.values.duplicate(true)
	for mobile in [false, true]:
		root.size = Vector2i(844, 390); app.set_mobile_layout(mobile); app.show_options()
		await settle()
		var scroll: ScrollContainer = app._body.get_parent()
		var context := "touch" if mobile else "desktop"
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(app._details.get_global_rect()), context + " options exceed the short landscape viewport")
		check(app._back.has_focus() and scroll.get_global_rect().end.y < app._back.get_global_rect().position.y, context + " opening lost the fixed Back action")
		check(scroll.scroll_vertical == 0 and scroll.get_global_rect().encloses(find_label(app._body, "UI scale").get_global_rect()), context + " reopening starts at a stale scroll offset")
		await capture("options-top-" + context)
		for key in app._settings_controls:
			var control: Control = app._settings_controls[key]
			check(control.size.y >= (44 if mobile else 30), key + " lost its desktop/touch target")
			if control is OptionButton or control is CheckButton:
				check(control.get_theme_stylebox("normal") == app.menu._ui.styles[mobile].normal, key + " does not use the verified original button artwork")
		await key_event(KEY_TAB, true)
		check(root.gui_get_focus_owner() == app._settings_controls["touch_controls" if mobile else "mouse_sensitivity"], context + " reverse Tab does not reach the last setting")
		await capture("options-last-" + context)
		var reverse_order: Array = ["invert_pitch", "voice", "fx", "music"] if mobile else ["mouse_steering", "touch_controls", "invert_pitch", "voice", "fx", "music"]
		for name in reverse_order:
			await key_event(KEY_TAB, true)
			check(root.gui_get_focus_owner() == app._settings_controls[name], context + " reverse Tab missed " + name)
			if name in ["music", "fx", "voice"]:
				var caption := find_label(app._body, library.strings[{"music":34,"fx":35,"voice":36}[name]])
				check(caption != null and scroll.get_global_rect().encloses(caption.get_global_rect()), context + " focused " + name + " label is clipped above its slider")
				check(scroll.get_global_rect().encloses(app._settings_controls[name].get_global_rect()), context + " focused " + name + " slider is clipped")
		await capture("options-music-" + context)
		var choice: OptionButton = app._settings_controls.frame_rate
		choice.grab_focus(); await settle(); await key_event(KEY_ENTER)
		var popup: PopupMenu = choice.get_popup()
		check(popup.visible and app.phase == "options", context + " keyboard acceptance did not open the frame-rate choices")
		check(popup.get_theme_font("font") == app.menu._ui.font and popup.get_theme_stylebox("panel") == app.menu._ui.styles[mobile].panel, context + " choice list lost original font/panel artwork")
		check(not popup.transparent and not popup.transparent_bg, context + " original popup artwork lets underlying settings show through")
		check(popup.get_theme_stylebox("hover") == app.menu._ui.styles[mobile].pressed, context + " highlighted choice lost original selected artwork")
		check(popup.size.y <= root.size.y and popup.position.y >= 0, context + " choice list exceeds the short landscape viewport")
		check(popup.get_theme_font("font").get_height(popup.get_theme_font_size("font_size")) + popup.get_theme_constant("v_separation") >= (44 if mobile else 30), context + " choice list lost its desktop/touch row target")
		await capture("options-choice-" + context)
		var popup_image := await capture("options-choice-popup-" + context, popup)
		if popup_image != null:
			check(popup_image.get_pixel(0, 0).a == 1 and popup_image.get_pixel(popup_image.get_width() / 2, popup_image.get_height() - 2).a == 1, context + " rendered choice list still has a transparent background")
		var cancel := InputEventKey.new(); cancel.physical_keycode = KEY_ESCAPE; cancel.keycode = KEY_ESCAPE; cancel.pressed = true
		cancel.window_id = popup.get_window_id(); Input.parse_input_event(cancel); await settle()
		cancel = cancel.duplicate(); cancel.pressed = false; Input.parse_input_event(cancel); await settle()
		check(not popup.visible and app.phase == "options" and choice.has_focus(), context + " dismissing the choice list lost options focus: visible=%s, phase=%s, focused=%s" % [popup.visible, app.phase, choice.has_focus()])
	check(app.preferences.values == preferences and not app.has_session(), "Options presentation changed preferences or started gameplay")
	app._preferences_path = "user://options-panel/player.json"
	app.set_mobile_layout(false); root.size = Vector2i(844, 390); app.show_options(); await settle()
	app._settings_controls.invert_pitch.grab_focus(); await settle()
	await controller(JOY_BUTTON_DPAD_UP)
	check(root.gui_get_focus_owner() == app._settings_controls.voice, "Controller Up did not focus the preceding audio setting")
	var voice_caption := find_label(app._body, library.strings[36])
	check(app._body.get_parent().get_global_rect().encloses(voice_caption.get_global_rect()), "Controller focus clipped the voice caption")
	await controller(JOY_BUTTON_DPAD_LEFT)
	check(is_equal_approx(app.preferences.values.voice, 0.95), "Controller Left no longer adjusts the focused audio slider through its existing signal: value=%s, saved=%s" % [app._settings_controls.voice.value, app.preferences.values.voice])
	await key_event(KEY_TAB)
	check(root.gui_get_focus_owner() == app._settings_controls.invert_pitch, "Keyboard forward traversal lost the following toggle")
	await key_event(KEY_SPACE)
	check(app.preferences.values.invert_pitch and app._settings_controls.invert_pitch.button_pressed, "Keyboard accept no longer persists the pitch toggle")
	check(app._settings_controls.invert_pitch.get_draw_mode() == BaseButton.DRAW_PRESSED and app._settings_controls.invert_pitch.get_theme_stylebox("pressed") == app.menu._ui.styles[false].pressed, "Enabled toggle lost original selected artwork")
	await capture("options-toggle-focused-desktop")
	var saved := Frontend.Preferences.new()
	check(saved.read_file(app._preferences_path) and saved.values == app.preferences.values, "Existing option signals did not preserve the preference round trip")
	for key in preferences:
		if key not in ["voice", "invert_pitch"]: check(app.preferences.values[key] == preferences[key], "Options input changed unrelated " + key + " preference")
	app.preferences.values.window_mode = "fullscreen"; app.show_options(); await settle()
	var resolution: OptionButton = app._settings_controls.resolution
	check(resolution.disabled and resolution.get_theme_stylebox("disabled") == app.menu._ui.styles[false].normal, "Fullscreen resolution lost its original disabled state")
	resolution.grab_focus(); await key_event(KEY_ENTER)
	check(not resolution.get_popup().visible and app.preferences.values.resolution == preferences.resolution, "Disabled resolution accepted a keyboard edit")
	await capture("options-disabled-desktop")
	app.preferences.values.window_mode = preferences.window_mode
	for language in Frontend.Preferences.LANGUAGES:
		check(library.select_language(language) and app.menu.configure(library, bindings, visuals), "Cannot prepare original options font for " + language)
		for mobile in [false, true]:
			app.set_mobile_layout(mobile); app.show_options(); await settle()
			var scroll: ScrollContainer = app._body.get_parent()
			check(app._detail_title.text == library.strings[31] and app._back.text == library.strings[178] and app._settings_controls.invert_pitch.text == library.strings[489], language + " options lost source labels")
			check(app._details.theme.default_font == app.menu._ui.font and app._settings_controls.invert_pitch.get_theme_font("font") == app.menu._ui.font, language + " options lost the selected original font")
			check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(app._details.get_global_rect()) and app._body.size.x <= scroll.size.x, language + " options overflow short landscape")
			app._settings_controls["touch_controls" if mobile else "mouse_sensitivity"].grab_focus(); await settle()
			app._settings_controls.voice.grab_focus(); await settle()
			var caption := find_label(app._body, library.strings[36])
			check(caption != null and scroll.get_global_rect().encloses(caption.get_global_rect()) and scroll.get_global_rect().encloses(app._settings_controls.voice.get_global_rect()), language + " focused voice setting is clipped")
			if language in ["de", "ru", "ja"] and mobile: await capture("options-voice-" + language + "-touch")
	if not captures.is_empty() and DisplayServer.get_name() != "headless":
		check(library.select_language("gb") and app.menu.configure(library, bindings, visuals), "Could not restore the capture language")
		for mobile in [false, true]:
			root.size = Vector2i(960, 540) if mobile else Vector2i(1280, 720)
			app.set_mobile_layout(mobile); app.show_options(); await settle()
			check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(app._details.get_global_rect()), "Standard landscape options exceed the viewport")
			await capture("options-standard-" + ("touch" if mobile else "desktop"))
	app.free(); await process_frame
	print("Options panel: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

func find_label(node: Node, value: String) -> Label:
	for child in node.get_children():
		if child is Label and child.text == value: return child
		var found := find_label(child, value)
		if found != null: return found
	return null

func settle() -> void:
	for tick in 4: await process_frame

func key_event(code: int, shift := false) -> void:
	var event := InputEventKey.new(); event.physical_keycode = code; event.keycode = code; event.shift_pressed = shift; event.pressed = true
	root.push_input(event); await process_frame
	event = event.duplicate(); event.pressed = false; root.push_input(event); await settle()

func controller(code: int) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = code; event.pressed = true
	# Sliders poll held joypad actions, so feed Input as a real device event does.
	Input.parse_input_event(event); await settle()
	event = event.duplicate(); event.pressed = false; Input.parse_input_event(event); await settle()

func capture(label: String, viewport: Viewport = null) -> Image:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return null
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	var image := (root if viewport == null else viewport).get_texture().get_image()
	check(image.save_png(captures.path_join(label + ".png")) == OK, "Could not capture options presentation")
	return image

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
