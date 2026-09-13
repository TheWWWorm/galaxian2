extends RefCounted
## Shared model clocks; loop wrapping uses the source absolute end time. Owners validate durations and own effect lifetime.
static func advance(models: Array, increment: int, loop := false) -> void:
	for model in models:
		if not model.playing: continue
		model.time_ms+=increment
		if model.time_ms>model.end_ms:
			if loop:
				model.time_ms=model.start_ms if model.end_ms==0 else model.start_ms+model.time_ms%model.end_ms
			else:
				model.time_ms=model.end_ms
				model.playing=false

static func restart(models: Array) -> void:
	for model in models:
		model.time_ms=model.start_ms
		model.playing=true
