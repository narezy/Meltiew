shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// A script's own object in place of a body part (Humanoid.TorsoPart...) that keeps the
// shirt: the object's box is mapped onto the body part's box, and the clothing template
// laid over it the same way the body does it (melly_body.gdshader, ClothingLayout).

uniform vec4 base_color : source_color = vec4(1.0);
uniform int part = 0;  // Torso 0, ArmL 2, ArmR 3, LegL 4, LegR 5
uniform vec3 obj_min;  // the object's box (studs, avatar facing)
uniform vec3 obj_size = vec3(1.0);
uniform mat4 to_object;  // this mesh's place in the object
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

varying vec3 rest;

void vertex() {
	vec3 p = (to_object * vec4(VERTEX, 1.0)).xyz;
	vec3 q = clamp((p - obj_min) / obj_size, 0.0, 1.0);
	// The body model faces +Z, the avatar -Z: turned around.
	q = vec3(1.0 - q.x, q.y, 1.0 - q.z);
	rest = BOX_MIN[part] + q * BOX_SIZE[part];
}

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

vec3 over(vec3 under, sampler2D tex, vec2 uv) {
	vec4 c = texture(tex, uv);
	return mix(under, c.rgb, c.a);
}

void fragment() {
	vec3 col = base_color.rgb;
	if (cloth_count > 0) {
		vec2 uv = atlas_uv(part, rest);
		col = over(col, cloth0, uv);
		if (cloth_count > 1) col = over(col, cloth1, uv);
		if (cloth_count > 2) col = over(col, cloth2, uv);
		if (cloth_count > 3) col = over(col, cloth3, uv);
		if (cloth_count > 4) col = over(col, cloth4, uv);
	}
	ALBEDO = col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
}
