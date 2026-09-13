extends RefCounted
## Shared source packed-color modulation before explicit renderer tint.
static func tint(parent_rgba: PackedByteArray, global_tint: Vector4, animation_byte := -1) -> Dictionary:
	if parent_rgba.size()!=4 or not global_tint.is_finite() or animation_byte< -1 or animation_byte>255: return {}
	var value := Vector4()
	for channel in 4:
		var byte := int(parent_rgba[channel])
		if animation_byte>=0: byte=(byte*animation_byte)>>8
		value[channel]=single(single(float(byte)*single(global_tint[channel]))/255.0)
	return {"value":value} if value.is_finite() else {}

static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]
