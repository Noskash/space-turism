shader_type canvas_item;

// Вращающаяся планета для карточек уровней: атмосфера, по желанию кольца.
// Вешается на квадратный ColorRect, фон вокруг планеты прозрачный.

#include "res://shaders/space_common.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.3, 0.3, 0.32, 1.0);
uniform vec4 color_b : source_color = vec4(0.8, 0.8, 0.78, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform bool gas_giant = false;
uniform bool rings = false;
uniform vec4 ring_color : source_color = vec4(0.95, 0.85, 0.65, 1.0);
// Радиус планеты в долях стороны прямоугольника.
uniform float planet_radius : hint_range(0.1, 0.5) = 0.36;
uniform float spin : hint_range(-1.0, 1.0) = 0.06;
// 0..1 — подсветка, когда карточка выбрана.
uniform float highlight : hint_range(0.0, 1.0) = 0.0;

// Наложение цвета поверх накопленного (rgb хранится домноженным на альфу).
vec4 blend_over(vec4 dst, vec3 color, float alpha) {
	return vec4(color * alpha + dst.rgb * (1.0 - alpha), alpha + dst.a * (1.0 - alpha));
}

float ring_alpha(float rr) {
	float band = smoothstep(1.35, 1.42, rr) * (1.0 - smoothstep(2.0, 2.08, rr));
	float detail = 0.6 + 0.4 * sin(rr * 42.0) * sin(rr * 17.0 + 1.3);
	float gap = smoothstep(0.015, 0.05, abs(rr - 1.78));
	return band * detail * gap * 0.85;
}

void fragment() {
	vec2 pd = (UV - 0.5) / planet_radius;
	float r = length(pd);
	float aa = fwidth(r) * 1.5;
	float mask = 1.0 - smoothstep(1.0 - aa, 1.0, r);

	vec4 acc = vec4(0.0);

	// Ореол атмосферы.
	vec2 dir = pd / max(r, 0.0001);
	float lit_side = smoothstep(-0.4, 0.9, dot(vec2(dir.x, -dir.y), normalize(PLANET_LIGHT.xy)));
	float halo = exp(-max(r - 1.0, 0.0) * mix(11.0, 6.5, highlight));
	halo *= (0.15 + 0.6 * lit_side) * (0.7 + 0.6 * highlight);
	acc = blend_over(acc, atmosphere_color.rgb, clamp(halo, 0.0, 1.0) * (1.0 - mask));

	// Кольца в наклонённой плоскости: дальняя половина за планетой, ближняя — перед ней.
	float ring_a = 0.0;
	vec3 ring_col = ring_color.rgb;
	bool ring_in_front = false;
	if (rings) {
		float tilt = -0.35;
		vec2 pr = vec2(cos(tilt) * pd.x - sin(tilt) * pd.y, sin(tilt) * pd.x + cos(tilt) * pd.y);
		vec2 q = vec2(pr.x, pr.y / 0.3);
		ring_a = ring_alpha(length(q));
		ring_col *= 0.55 + 0.45 * smoothstep(1.0, -1.0, q.x * 0.5);
		ring_in_front = pr.y > 0.0;
	}

	if (!ring_in_front) {
		acc = blend_over(acc, ring_col * 0.8, ring_a);
	}
	if (r < 1.0) {
		vec3 body = planet_body(pd, TIME, color_a.rgb, color_b.rgb, atmosphere_color.rgb, spin, gas_giant);
		acc = blend_over(acc, body * (1.0 + 0.25 * highlight), mask);
	}
	if (ring_in_front) {
		acc = blend_over(acc, ring_col, ring_a);
	}

	COLOR = vec4(acc.rgb / max(acc.a, 0.0001), acc.a);
}
