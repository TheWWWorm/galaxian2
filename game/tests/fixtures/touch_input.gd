extends RefCounted
## Mark a real device touch before enabling the application touch preference.

static func set_preference(preview: Control, enabled: bool) -> void:
	if enabled:
		var event:=InputEventScreenTouch.new()
		event.device=0;event.index=0;event.pressed=true
		preview.call("_input",event)
	preview.call("set_touch_controls",enabled)
