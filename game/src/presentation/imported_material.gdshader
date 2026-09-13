shader_type spatial;
render_mode cull_disabled;

#include "res://src/presentation/material_uv.gdshaderinc"
uniform sampler2D normal_specular_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal_specular = false;

void fragment() {
	vec2 coordinates = source_uv(UV);
	ALBEDO = has_diffuse ? source_diffuse(UV).rgb : vec3(0.46, 0.55, 0.64) * imported_vertex_color.rgb;
	ROUGHNESS = 0.55;
	if (has_normal_specular) {
		vec4 packed_normal = texture(normal_specular_texture, coordinates);
		NORMAL_MAP = packed_normal.rgb;
		SPECULAR = packed_normal.a;
	}
}
