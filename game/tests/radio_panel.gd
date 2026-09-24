extends SceneTree
const PanelView = preload("res://src/presentation/radio_panel.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	var events := []
	for i in 23: events.append({"text_id": i, "speaker_id": i % 2, "condition": 5, "values": [50 if i == 0 else 100000]})
	bindings.opening_dialogue = {"campaign_cursor": 0, "events": events, "timing": {"display_delay_ms": 2000, "base_duration_ms": 1500, "per_line_ms": 2000}}
	var library := Library.new()
	library.manifest = {"content_id": bindings.base_content_id}
	library.active_language = "gb"
	for i in 23: library.strings.append("[b]Literal transmission[/b] — Unicode Ж. " + "Long native text for scrolling. ".repeat(90))
	var counts := []
	counts.resize(23)
	counts.fill(3)
	var radio := Radio.new()
	check(radio.configure(bindings, library, counts), radio.error)
	var view := PanelView.new()
	root.add_child(view)
	view.size = Vector2(1120, 720)
	var portrait_image := Image.create(12, 15, false, Image.FORMAT_RGBA8)
	portrait_image.fill(Color.CADET_BLUE)
	var portrait := ImageTexture.create_from_image(portrait_image)
	var speakers := {0: {"name": "Synthetic speaker", "portrait": portrait}}
	check(view.configure(bindings.base_content_id, bindings.binding_id, "gb", speakers), view.error)
	speakers[0].name = "Changed outside the view"
	radio.step(50, {}, 0)
	check(view.present(radio.snapshot()) and not view.visible and view._body.text.is_empty(), "Activation displayed before source delay")
	radio.step(2050, {}, 0)
	check(view.present(radio.snapshot()) and not view.visible, "Delay boundary was inclusive")
	radio.step(2051, {}, 0)
	check(view.present(radio.snapshot()) and view.visible, view.error)
	check(view._body.text == library.strings[0] and not view._body.bbcode_enabled, "Source text interpreted as markup or changed")
	check(view._name.text == "Synthetic speaker" and view._portrait.texture == portrait, "Resolved speaker not captured")
	await process_frame
	var before := radio.snapshot()
	var desktop_width: float = view._panel.size.x
	for phone in [true, false]:
		view.set_mobile_layout(phone)
		for viewport in [Vector2(1120, 720), Vector2(844, 390), Vector2(320, 200)]:
			view.size = viewport
			await process_frame
			check(view._panel.position.x >= 0 and view._panel.position.y >= 0 and view._panel.position.x + view._panel.size.x <= viewport.x + 1 and view._panel.position.y + view._panel.size.y <= viewport.y + 1, "Radio panel escaped viewport")
			check(view._body.size.x > 0 and view._body.size.y > 0, "Text has no usable viewport")
			check(view._body.scroll_active and view._body.get_content_height() > view._body.size.y, "Long transmission cannot be scrolled")
			check(view.present(radio.snapshot()) and radio.snapshot() == before, "Native resizing changed radio timing/state")
	view.size = Vector2(1120, 720)
	view.set_mobile_layout(true)
	check(is_equal_approx(view._panel.size.x, desktop_width * 2), "Desktop composition is not half phone composition")
	# A preceding HUD readout can reserve more than a small landscape viewport.
	# The passive radio must retain a usable scroll area without leaving it.
	for phone in [false, true]:
		view.set_mobile_layout(phone)
		view.size = Vector2(844, 390)
		view.set_top_inset(440)
		await process_frame
		check(Rect2(Vector2.ZERO, view.size).encloses(view._panel.get_rect()), "Reserved HUD inset pushed radio beyond the landscape viewport")
		check(view._body.size.y >= view._body.get_theme_font_size("normal_font_size"), "Reserved HUD inset removed the radio's readable line")
		check(view.present(radio.snapshot()) and radio.snapshot() == before, "Inset clamping changed source radio state")
		var args := OS.get_cmdline_user_args()
		if args.size() == 4 and DisplayServer.get_name() != "headless":
			root.content_scale_size = Vector2i.ZERO; root.size = Vector2i(view.size)
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(args[3])
			var image := root.get_texture().get_image()
			check(image != null and image.save_png(args[3].path_join("radio-inset-" + ("touch" if phone else "desktop") + ".png")) == OK, "Cannot capture bounded radio inset")
	view.set_top_inset(0)
	view.size = Vector2(1120, 720)
	view.set_mobile_layout(true)
	view._body.get_v_scroll_bar().value = 50
	var scroll: float = view._body.get_v_scroll_bar().value
	check(view.present(radio.snapshot()) and view._body.get_v_scroll_bar().value == scroll, "Per-frame refresh reset scroll")
	check(not paused and view.mouse_filter == Control.MOUSE_FILTER_IGNORE and view._body.focus_mode == Control.FOCUS_NONE, "Radio captured flight focus or paused simulation")
	radio.step(9550, {}, 0)
	check(not radio.snapshot().finished[0] and view.present(radio.snapshot()) and view.visible, "Native layout shortened source duration")
	radio.step(9551, {}, 0)
	check(radio.snapshot().finished[0] and view.present(radio.snapshot()) and not view.visible and view._body.text.is_empty() and view._portrait.texture == null, "Finished transmission retained presentation")
	# Failure must remove old text/art; a previous edition or language must never
	# leak into a newly selected context. A later valid snapshot can recover.
	var active := before.duplicate(true)
	for key in ["base_content_id", "binding_id", "language", "text", "speaker_id", "active_event", "visible"]:
		check(view.present(active), view.error)
		var invalid := active.duplicate(true)
		invalid[key] = "wrong" if key in ["base_content_id", "binding_id", "language"] else null
		check(not view.present(invalid) and not view.visible and view._body.text.is_empty() and view._portrait.texture == null and not view.error.is_empty(), "Invalid snapshot retained stale view: " + key)
	active.speaker_id = 1
	check(view.present(active) and view._name.text.is_empty() and not view._portrait.visible, "Unknown speaker inherited previous portrait")
	check(view.present({}) and not view.visible, "Empty snapshot did not clear view")
	check(not view.configure(bindings.base_content_id, bindings.binding_id, "gb", {0: {"name": "Bad", "portrait": "not a texture"}}) and not view.present(active), "Failed context retained identity")
	view.queue_free()
	await process_frame
	print("Radio presentation checks: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
