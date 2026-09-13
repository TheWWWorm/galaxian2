shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
#include "res://src/presentation/material_sampling.gdshaderinc"
void vertex() {
	imported_vertex_color = has_vertex_color ? CUSTOM0 : vec4(1.0);
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = CLIP_SPACE_FAR * POSITION.w;
}
void fragment() {
	ALBEDO = source_diffuse(UV).rgb;
	// Original mode 2 uses ONE, ONE; texture alpha is not a blend factor.
	ALPHA = 1.0;
}
