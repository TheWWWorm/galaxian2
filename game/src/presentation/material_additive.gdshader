shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
#include "res://src/presentation/material_uv.gdshaderinc"
void fragment() {
	ALBEDO = source_diffuse(UV).rgb;
	// The source uses ONE, ONE. Texture alpha is not a blend factor.
	ALPHA = 1.0;
}
