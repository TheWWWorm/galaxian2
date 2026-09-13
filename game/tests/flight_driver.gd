extends SceneTree
const Controls = preload("res://src/input/flight_controls.gd")
const Clock = preload("res://src/simulation/frame_clock.gd")
const Driver = preload("res://src/simulation/flight_driver.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	check_controls()
	var bindings := Bindings.new()
	bindings.base_content_id = "a".repeat(64)
	bindings.binding_id = "b".repeat(64)
	bindings.frame_clock = {"max_frame_milliseconds": 150, "time_unit": "milliseconds"}
	bindings.vehicle_response = {"base_add": 0.0, "base_divisor": 1.0, "base_scale": 1.0, "base_offset": 0.0,
		"upgrade_tag": 3, "upgrade_bonus": 0.2, "equipment_type": 16, "item_type_value_index": 5,
		"equipment_percent_property": 28, "percent_divisor": 100.0, "response_scale": 20.0, "equipment_rule": "last_matching"}
	bindings.cruise = {"speed_units_per_millisecond": 2.0, "forward_axis": [0, 0, 1]}
	bindings.manual_rotation = {"angle_unit_scale": 1.0 / 65536.0, "radians_per_turn": TAU, "time_scale": 0.033, "rotation_order": "local_x_y"}
	bindings.pilot_response = {"target_gain": 750.0, "target_divisor": 63, "ramp_bias": 3.3, "ramp_scale": 20.0, "neutral_divisor": 126.0, "mode": "elapsed", "command_curve": "signed_square"}
	var catalogues := Catalogues.new()
	catalogues.content_id = bindings.base_content_id
	catalogues.tables = {"ships": [{"stats": {"handling_factor": 1.0}}], "items": []}
	check_clock(bindings)
	check_driver(bindings, catalogues)
	for architecture in ["armv7", "x86_64"]:
		var data := {"max_frame_milliseconds": 150, "time_unit": "milliseconds", "provenance": [{"offset": 0, "bytes": 62 if architecture == "armv7" else 72}, {"offset": 100, "bytes": 28}]}
		check(Clock.validate(data, 1024, architecture).is_empty(), "Valid clock provenance rejected")
		for invalid in [0, -1, 0.5, INF, NAN, true, "150"]:
			data.max_frame_milliseconds = invalid
			check(not Clock.validate(data, 1024, architecture).is_empty(), "Invalid frame cap accepted")
	var args := OS.get_cmdline_user_args()
	check(args.size() % 2 == 0, "Pass content/bindings pairs")
	for i in range(0, args.size() - 1, 2):
		var library := Library.new()
		check(library.open(args[i]), library.error)
		check(bindings.open(args[i + 1], library.manifest), bindings.error)
		check(catalogues.open(library), catalogues.error)
		check_clock(bindings)
		check_driver(bindings, catalogues)
		print(library.manifest.profile.edition, ": native event-to-motion driver checked")
	print("Flight driver checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_controls() -> void:
	var c := Controls.new()
	check(c.configure_preferences(0.2, false, false), c.error)
	check(not c.set_touch_action("pause", true), "Hidden desktop touch action accepted")
	c.accept(key(KEY_W, true)); c.accept(key(KEY_D, true))
	check(c.snapshot().command == Vector2(-1, 1), "Keyboard pitch/yaw directions incorrect")
	c.accept(key(KEY_W, false)); c.accept(key(KEY_D, false))
	check(not c.accept(axis(1, JOY_AXIS_LEFT_X, 0.1)) and c.device == -1, "Idle controller stole ownership")
	check(c.accept(axis(1, JOY_AXIS_LEFT_X, 0.6)) and c.device == 1, "Active controller did not acquire input")
	near(c.snapshot().command.y, 0.5, "Controller deadzone remapping")
	check(not c.accept(axis(2, JOY_AXIS_TRIGGER_RIGHT, -1)) and c.device == 1, "Resting trigger stole ownership")
	c.accept(axis(2, JOY_AXIS_LEFT_Y, -1))
	check(c.device == 2 and c.snapshot().command == Vector2(-1, 0), "Controller switch retained old axes")
	c.accept(axis(2, JOY_AXIS_TRIGGER_RIGHT, 1)); c.accept(key(KEY_SPACE, true))
	c.accept(key(KEY_SPACE, false))
	check(c.snapshot().held.fire, "Releasing keyboard cancelled controller fire")
	c.disconnect_controller(2)
	check(not c.snapshot().held.fire and c.snapshot().command == Vector2.ZERO, "Controller disconnect retained input")
	c.take_pressed()
	c.accept(key(KEY_ESCAPE, true)); c.accept(key(KEY_ESCAPE, true, true))
	check(c.take_pressed() == ["pause"] and c.take_pressed().is_empty(), "Repeated or consumed key emitted extra action")
	c.accept(key(KEY_ESCAPE, false))
	c.set_touch_controls(true)
	check(c.set_touch_command(Vector2(-0.5, 0.25), true), "Touch look rejected")
	c.configure_preferences(0.2, true, true)
	check(c.snapshot().command == Vector2(0.5, 0.25), "Pitch inversion or touch order failed")
	for action in Controls.ACTIONS:
		check(c.set_touch_action(action, true) and c.snapshot().held[action], "Missing touch action: " + action)
	c.accept(key(KEY_P, true))
	c.set_touch_controls(false)
	check(c.take_pressed() == ["autopilot"] and c.snapshot().command == Vector2.ZERO, "Hiding touch retained touch actions or erased keyboard action")
	check(not c.configure_preferences(NAN, false, true) and c.deadzone == 0.2, "Invalid preference changed controls")
	c.set_enabled(false)
	check(c.snapshot().command == Vector2.ZERO and not c.accept(key(KEY_D, true)), "Disabled controls accepted input")
	c.set_enabled(true)
	check(c.snapshot().command == Vector2.ZERO and c.take_pressed().is_empty(), "Re-enabled controls retained held input")
	for mapping in [[JOY_BUTTON_START, "pause"], [JOY_BUTTON_BACK, "time"], [JOY_BUTTON_Y, "autopilot"], [JOY_BUTTON_X, "dock"], [JOY_BUTTON_A, "boost"], [JOY_BUTTON_B, "missiles"], [JOY_BUTTON_DPAD_UP, "throttle_up"], [JOY_BUTTON_DPAD_DOWN, "throttle_down"]]:
		var event := InputEventJoypadButton.new()
		event.device = 3
		event.button_index = mapping[0]
		event.pressed = true
		check(c.accept(event) and c.snapshot().held[mapping[1]] and c.take_pressed() == [mapping[1]], "Controller action binding failed: " + mapping[1])
		event.pressed = false
		c.accept(event)
		check(not c.snapshot().held[mapping[1]] and c.take_pressed().is_empty(), "Controller release emitted an action")


func check_clock(bindings: RefCounted) -> void:
	var clock := Clock.new()
	check(clock.configure(bindings, bindings.base_content_id), clock.error)
	check(clock.sample(0, false) == 0, "First frame caught up from an imaginary origin")
	var elapsed := 0.0
	for i in range(1, 121): elapsed += clock.sample(int(round(i * 1000000.0 / 120)), false)
	near(elapsed, 1.0, "Submillisecond remainder was lost at high frame rate")
	near(clock.sample(3000000, false), 0.15, "Long frame did not use source cap")
	near(clock.sample(3016000, false), 0.016, "Capped time was replayed on next frame")
	check(clock.sample(2000000, false) == 0, "Negative time became backward movement")
	check(clock.sample(9000000, true) == 0, "Blocked simulation advanced")
	near(clock.sample(9016000, false), 0.016, "Blocked wall time leaked into resumed motion")
	check(clock.rebase(20000000) and clock.sample(20000000, false) == 0, "Pause transition did not rebase")
	check(clock.sample(-1, false) == 0 and not clock.error.is_empty(), "Negative timestamp accepted")
	check(not clock.configure(bindings, "c".repeat(64)) and clock.binding_id.is_empty(), "Wrong-content clock retained context")

func check_driver(bindings: RefCounted, catalogues: RefCounted) -> void:
	var d := Driver.new()
	check(d.configure(bindings, catalogues, catalogues.content_id, 0, [], [], 0.5, Transform3D.IDENTITY), d.error)
	if d.binding_id.is_empty(): return
	check(d.step(0, 1).get("seconds") == 0.0, "Driver first tick advanced")
	d.accept(key(KEY_D, true))
	var first := d.step(100000, 1)
	check(first.pose.origin == Vector3(0, 0, 200) and d.angular_units().y > 0, "Keyboard command failed to reach staged flight response")
	var second := d.step(200000, 1)
	check(second.pose.origin.x > 0 and second.seconds == 0.1, "Established input failed to turn flight")
	d.accept(key(KEY_T, true)); d.accept(key(KEY_E, true))
	var requests := d.step(216000, 1)
	check("time" in requests.requested_actions and "dock" in requests.requested_actions, "Unsupported actions were lost rather than returned as requests")
	check(not d.set_pause("radio", true, 216000), "Timed radio was treated as a modal freeze")
	check(d.set_pause("modal", true, 220000), d.error)
	check(d.set_pause("cinematic", true, 230000), d.error)
	var frozen := d.pose()
	var angular := d.angular_units()
	d.accept(key(KEY_SPACE, true))
	check(d.step(8000000, 1).paused and d.pose() == frozen and d.angular_units() == angular, "Modal pause advanced motion/response")
	d.set_pause("modal", false, 8100000)
	check(d.is_paused(), "Closing modal incorrectly removed cinematic freeze")
	d.set_pause("cinematic", false, 8200000)
	var resumed := d.step(8216000, 1)
	check(not resumed.paused and resumed.seconds == 0.016 and not resumed.held_actions.fire, "Resume caught up paused time or fired acknowledgement input")
	d.set_focused(false, 8300000)
	check(not d.accept(key(KEY_D, true)) and d.step(9000000, 1).paused, "Unfocused flight accepted input")
	d.set_focused(true, 9100000)
	check(d.step(9116000, 1).seconds == 0.016 and d.controls.snapshot().command == Vector2.ZERO, "Focus return retained controls or elapsed backlog")
	d.accept(key(KEY_ESCAPE, true)); d.accept(key(KEY_SPACE, true))
	check(d.step(9132000, 1).paused, "Native pause key failed")
	d.accept(key(KEY_ESCAPE, false)); d.accept(key(KEY_ESCAPE, true)); d.accept(key(KEY_SPACE, true))
	var unpaused := d.step(9148000, 1)
	check(not unpaused.paused and unpaused.requested_actions.is_empty() and not unpaused.held_actions.fire, "Unpause forwarded simultaneous action")
	var before := d.pose()
	check(d.step(9164000, NAN).is_empty() and d.pose() == before, "Invalid throttle changed driver state")
	check(not d.configure(bindings, catalogues, "c".repeat(64), 0, [], [], 0.5, Transform3D.IDENTITY) and d.binding_id.is_empty(), "Failed driver configuration retained identity")

func key(code: int, down: bool, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	event.echo = echo
	return event

func axis(device_id: int, index: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = index
	event.axis_value = value
	return event

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.00001, message + ": " + str(actual))

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
