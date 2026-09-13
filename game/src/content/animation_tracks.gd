extends RefCounted
## Native linear sampler for source keyframes. Does not invent a playback clock.

static func sample(track: Dictionary, time: float, fallback: PackedFloat32Array) -> PackedFloat32Array:
	if track.is_empty():
		return fallback
	var width: int = track.dimensions
	var keys: PackedFloat32Array = track.keys
	var stride := width + 1
	var count: int = keys.size() / stride
	if count == 0:
		return fallback
	var low := 0
	var high := count
	while low < high:
		var mid: int = (low + high) / 2
		if keys[mid * stride] <= time:
			low = mid + 1
		else:
			high = mid
	var left := maxi(0, low - 1)
	var right := mini(count - 1, low)
	var start := keys[left * stride]
	var end := keys[right * stride]
	var weight := clampf((time - start) / (end - start), 0.0, 1.0) if end > start else 0.0
	var result := PackedFloat32Array()
	result.resize(width)
	for component in width:
		result[component] = lerpf(keys[left * stride + component + 1], keys[right * stride + component + 1], weight)
	return result

static func vector(group: Array, time: float, fallback: Vector3) -> Vector3:
	if group.size() == 1:
		var values := sample(group[0], time, PackedFloat32Array([fallback.x, fallback.y, fallback.z]))
		return Vector3(values[0], values[1], values[2])
	if group.size() == 3:
		var result := fallback
		for axis in 3:
			result[axis] = sample(group[axis], time, PackedFloat32Array([fallback[axis]]))[0]
		return result
	return fallback

static func range_of(surfaces: Array) -> Vector2:
	var first := INF
	var last := -INF
	for surface in surfaces:
		for group in surface.tracks.values():
			for track in group:
				var keys: PackedFloat32Array = track.get("keys", PackedFloat32Array())
				if not keys.is_empty():
					first = minf(first, keys[0])
					last = maxf(last, keys[keys.size() - int(track.dimensions) - 1])
	return Vector2(first, last) if first != INF else Vector2.ZERO

## Static scene adapters can safely accept authored identity keys: neither
## interpolation, clock units nor looping changes an identity transform. Keep
## material animation unsupported even if a current sample happens to be neutral.
static func has_identity_tracks(surfaces: Array) -> bool:
	for surface in surfaces:
		if not surface is Dictionary or not surface.get("tracks") is Dictionary:return false
		for name in surface.tracks:
			var group: Variant = surface.tracks[name]
			if not group is Array:return false
			if name in ["translation","rotation","scale"]:
				if group.size() not in [0,1,3]:return false
				var width := 3 if group.size()==1 else 1
				var neutral := 1.0 if name=="scale" else 0.0
				for track in group:
					if not identity_track(track,width,neutral):return false
			elif name in ["scalar","uv"]:
				for track in group:
					if not identity_track(track,1,0.0) or not track.keys.is_empty():return false
			else:return false
	return true

static func identity_track(track: Variant, width: int, neutral: float) -> bool:
	if not track is Dictionary or track.get("dimensions")!=width or not track.get("keys") is PackedFloat32Array:return false
	var keys: PackedFloat32Array = track.keys
	var stride := width+1
	if keys.size()%stride!=0:return false
	var previous := -INF
	for offset in range(0,keys.size(),stride):
		if not is_finite(keys[offset]) or keys[offset]<previous:return false
		previous=keys[offset]
		for component in width:
			if keys[offset+component+1]!=neutral:return false
	return true
