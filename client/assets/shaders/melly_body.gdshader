shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Order matches the skin joints: Torso, Head, ArmL, ArmR, LegL, LegR
uniform vec4 part_colors[6] : source_color;

// Clothing, bottom to top, laid out like the template (see ClothingLayout, same numbers).
uniform int cloth_count = 0;
uniform sampler2D cloth0 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cloth1 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cloth2 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cloth3 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cloth4 : source_color, filter_linear_mipmap, repeat_disable;

const float PX = 96.0;
const vec2 TEMPLATE = vec2(1024.0, 768.0);
const vec3 BOX_MIN[6] = { vec3(-0.83, 2.0, -0.39), vec3(0.0), vec3(0.79118, 1.88, -0.37986),
	vec3(-1.62882, 1.88, -0.37986), vec3(0.03004, 0.0, -0.42723), vec3(-0.82996, 0.0, -0.42723) };
const vec3 BOX_SIZE[6] = { vec3(1.66, 2.0, 0.78), vec3(1.0), vec3(0.83764, 2.0, 0.75972),
	vec3(0.83764, 2.0, 0.75972), vec3(0.79992, 2.0, 0.85446), vec3(0.79992, 2.0, 0.85446) };
const vec2 ORIGIN[6] = { vec2(16.0, 16.0), vec2(0.0), vec2(16.0, 382.0), vec2(512.0, 16.0),
	vec2(688.0, 382.0), vec2(346.0, 382.0) };

varying flat int part;
// Where this point of the body is in the rest pose (baked into UV / UV2).
varying vec3 rest;

void vertex() {
	part = int(BONE_INDICES.x);
	rest = vec3(UV.x, UV.y, UV2.x);
}

// The template pixel for a point on a part: the box face it's on (the one it's furthest
// out towards), unfolded like the template's cross.
vec2 atlas_uv(int p, vec3 pos) {
	vec3 mn = BOX_MIN[p];
	vec3 sz = BOX_SIZE[p];
	vec3 d = (pos - (mn + sz * 0.5)) / (sz * 0.5);
	vec3 f = clamp((pos - mn) / sz, 0.003, 0.997);
	float fw = floor(sz.x * PX + 0.5);
	float fh = floor(sz.y * PX + 0.5);
	float fd = floor(sz.z * PX + 0.5);
	vec2 o = ORIGIN[p];
	vec3 a = abs(d);
	vec2 px;
	if (a.z >= a.x && a.z >= a.y) {
		px = d.z > 0.0
			? o + vec2(fd, fd) + vec2(f.x * fw, (1.0 - f.y) * fh)
			: o + vec2(2.0 * fd + fw, fd) + vec2((1.0 - f.x) * fw, (1.0 - f.y) * fh);
	} else if (a.x >= a.y) {
		px = d.x < 0.0
			? o + vec2(0.0, fd) + vec2(f.z * fd, (1.0 - f.y) * fh)
			: o + vec2(fd + fw, fd) + vec2((1.0 - f.z) * fd, (1.0 - f.y) * fh);
	} else {
		px = d.y > 0.0
			? o + vec2(fd, 0.0) + vec2(f.x * fw, f.z * fd)
			: o + vec2(fd, fd + fh) + vec2(f.x * fw, (1.0 - f.z) * fd);
	}
	return px / TEMPLATE;
}

vec3 over(vec3 under, sampler2D tex, vec2 uv, float lod) {
	vec4 c = textureLod(tex, uv, lod);
	return mix(under, c.rgb, c.a);
}

void fragment() {
	int p = clamp(part, 0, 5);
	vec3 col = part_colors[p].rgb;
	// The mip level from the smooth rest position, not the atlas UV: across a fold of the
	// cross the UV jumps, and that would pick a blurry level along every edge.
	float lod = log2(max(max(length(dFdx(rest)), length(dFdy(rest))) * PX, 1e-4));
	if (cloth_count > 0 && p != 1) {
		vec2 uv = atlas_uv(p, rest);
		col = over(col, cloth0, uv, lod);
		if (cloth_count > 1) col = over(col, cloth1, uv, lod);
		if (cloth_count > 2) col = over(col, cloth2, uv, lod);
		if (cloth_count > 3) col = over(col, cloth3, uv, lod);
		if (cloth_count > 4) col = over(col, cloth4, uv, lod);
	}
	ALBEDO = col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
}
