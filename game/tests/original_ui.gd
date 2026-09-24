extends SceneTree
## Actual main-menu/options controls, using imported art without starting a
## campaign, writing preferences, or claiming original focus-style fidelity.
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
	var library := Library.new()
	var bindings := Bindings.new()
	var visuals := Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1], library.manifest) or not library.select_language("gb") or not visuals.open(args[2], library.manifest):
		check(false, library.error + bindings.error + visuals.error); quit(1); return
	root.content_scale_size = Vector2i.ZERO
	var app := Frontend.new()
	root.add_child(app); app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.library = library; app.bindings = bindings; app.visuals = visuals
	if not app.menu.configure(library, bindings, visuals):
		check(false, app.menu.error); app.free(); quit(1); return
	var preferences: Dictionary = app.preferences.values.duplicate(true)
	for mobile in [false, true]:
		root.size = Vector2i(960, 540) if mobile else Vector2i(1280, 720)
		app.set_mobile_layout(mobile); app.phase = "menu"; app._details.hide()
		app.menu.present(false, false)
		for tick in 3: await process_frame
		app.menu.focus_first(); await process_frame
		check(root.gui_get_focus_owner() == app.menu._buttons.new_game, "Menu opening did not focus its first usable action")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == app.menu._buttons.supernova and app.menu._buttons.supernova.disabled, "Native traversal lost the disabled Challenge control")
		check(app.menu._buttons.supernova.get_draw_mode() == BaseButton.DRAW_DISABLED, "Focused disabled control lost its disabled presentation")
		await capture("menu-disabled-focused-" + ("touch" if mobile else "desktop"))
		await key(KEY_ENTER)
		check(app.phase == "menu" and not app.has_session(), "Focused disabled Challenge dispatched gameplay")
		await key(KEY_TAB); await key(KEY_TAB)
		var option: Button = app.menu._buttons.options
		check(root.gui_get_focus_owner() == option, "Keyboard focus did not traverse to Options")
		var accepted_rect := option.get_global_rect()
		verify_focus_style(option, mobile, "Options")
		option.release_focus(); await process_frame
		check(option.get_global_rect() == accepted_rect, "Releasing focus changed original button dimensions")
		var normal_image: Image = await capture("menu-normal-" + ("touch" if mobile else "desktop"))
		app.menu.focus_first()
		for move in 3: await controller(JOY_BUTTON_DPAD_DOWN)
		check(root.gui_get_focus_owner() == option, "Controller focus did not reach Options")
		check(option.get_global_rect() == accepted_rect, "Controller focus moved or resized the original button")
		var focused_image: Image = await capture("menu-focused-" + ("touch" if mobile else "desktop"))
		if normal_image != null and focused_image != null:
			check(normal_image.get_region(Rect2i(accepted_rect)).get_data() != focused_image.get_region(Rect2i(accepted_rect)).get_data(), "Keyboard/controller focus made no visible button difference")
		var enter := InputEventKey.new(); enter.physical_keycode = KEY_ENTER; enter.keycode = KEY_ENTER; enter.pressed = true
		root.push_input(enter); await process_frame
		check(option.get_draw_mode() == BaseButton.DRAW_PRESSED and option.has_focus(), "Keyboard press did not retain native pressed/focus state")
		check(option.get_theme_stylebox("pressed") == app.menu._ui.styles[mobile].pressed, "Focus replaced the original amber pressed artwork")
		await capture("menu-pressed-focused-" + ("touch" if mobile else "desktop"))
		enter = enter.duplicate(); enter.pressed = false; root.push_input(enter)
		for tick in 3: await process_frame
		check(app.phase == "options" and app._back.has_focus(), "Accepting Options lost focus on its original Back action")
		verify_focus_style(app._back, mobile, "Back")
		check(app._back.get_theme_stylebox("normal") == app.menu._ui.styles[mobile].back_normal and app._back.get_theme_stylebox("pressed") == app.menu._ui.styles[mobile].back_pressed, "Back arrow artwork changed with the focus cue")
		await capture("options-back-focused-" + ("touch" if mobile else "desktop"))
		var hover := InputEventMouseMotion.new(); hover.position = app._back.get_global_rect().get_center(); hover.global_position = hover.position
		root.push_input(hover); await process_frame
		check(app._back.get_draw_mode() == BaseButton.DRAW_HOVER and app._back.has_focus(), "Pointer hover lost the focused Back control")
		await capture("options-back-hover-focused-" + ("touch" if mobile else "desktop"))
		check(app.menu._buttons.supernova.disabled and app.menu._buttons.load.disabled, "Focus handling enabled unavailable menu actions")
	check(app.preferences.values == preferences and not app.has_session(), "Focus navigation changed preferences or started gameplay")
	app.free(); await process_frame
	print("Original UI focus: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

func verify_focus_style(button: Button, mobile: bool, context: String) -> void:
	var focus: StyleBox = button.get_theme_stylebox("focus")
	check(focus != button.get_theme_stylebox("normal"), context + " focus repeats the opaque normal artwork")
	check(focus is StyleBoxFlat and not focus.draw_center and focus.border_color.a == 1 and focus.get_border_width(SIDE_TOP) >= 2, context + " lacks a distinct transparent native focus outline")
	check(button.get_theme_stylebox("normal") is StyleBoxTexture and button.get_theme_stylebox("hover") == button.get_theme_stylebox("normal") and button.get_theme_stylebox("disabled") == button.get_theme_stylebox("normal"), context + " focus replaced normal/hover/disabled original artwork")
	check(button.get_theme_stylebox("hover_pressed") == button.get_theme_stylebox("pressed"), context + " pointer press lost original selected artwork")
	check(button.size.y >= (44 if mobile else 30), context + " focus reduced the desktop/touch action target")

func key(code: int) -> void:
	var event := InputEventKey.new(); event.physical_keycode = code; event.keycode = code; event.pressed = true
	root.push_input(event); await process_frame
	event = event.duplicate(); event.pressed = false; root.push_input(event); await process_frame

func controller(code: int) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = code; event.pressed = true
	root.push_input(event); await process_frame
	event = event.duplicate(); event.pressed = false; root.push_input(event); await process_frame

func capture(label: String) -> Image:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return null
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(captures)
	var image := root.get_texture().get_image()
	check(image.save_png(captures.path_join(label + ".png")) == OK, "Could not capture focus presentation")
	return image

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
