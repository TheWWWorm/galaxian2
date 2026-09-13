#include "res://src/presentation/material_coordinates.gdshaderinc"
uniform sampler2D diffuse_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool has_diffuse = false;
uniform bool has_vertex_color = false;
varying vec4 imported_vertex_color;

vec4 source_diffuse(vec2 input_uv) {
	return (has_diffuse ? texture(diffuse_texture, source_uv(input_uv)) : vec4(1.0)) * imported_vertex_color;
}
