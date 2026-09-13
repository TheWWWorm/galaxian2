shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
#include "res://src/presentation/material_uv.gdshaderinc"
void fragment() {
	vec4 color = source_diffuse(UV);
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
