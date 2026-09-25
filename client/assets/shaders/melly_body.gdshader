shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Order matches the skin joints: Torso, Head, ArmL, ArmR, LegL, LegR
uniform vec4 part_colors[6] : source_color;
varying flat int part;

void vertex() {
	part = int(BONE_INDICES.x);
}

void fragment() {
	ALBEDO = part_colors[clamp(part, 0, 5)].rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
}
