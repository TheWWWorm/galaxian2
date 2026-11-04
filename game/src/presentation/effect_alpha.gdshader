shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled;
#include "res://src/presentation/effect_texture.gdshaderinc"
#include "res://src/presentation/material_coordinates.gdshaderinc"

// Expansion effects carry per-vertex colours in CUSTOM0.
uniform bool vertex_colors = false;
varying vec3 vertex_color;

void vertex() {
	vertex_color = vertex_colors ? CUSTOM0.rgb : vec3(1.0);
}

void fragment() {
	ALBEDO = effect_color(source_uv(UV)).rgb * vertex_color;
	// Source type 1 blends by the texture/tint alpha.
	ALPHA = effect_color(source_uv(UV)).a;
}
