shader_type spatial;
render_mode unshaded, cull_back;
#include "res://src/presentation/material_uv.gdshaderinc"
// Original mode 10 enables depth writes, disables blending and keeps texels
// with alpha greater than one half. Visitor lighting is baked into the sprite.
void fragment() {
	vec4 color = source_diffuse(UV);
	if (color.a <= 0.5) { discard; }
	ALBEDO = color.rgb;
}
