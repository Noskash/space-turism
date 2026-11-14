shader_type canvas_item;

// Анимированный космический фон: туманность, звёзды с параллаксом,
// планета с атмосферой, метеоры и эффект прыжка в гиперпространство.
// Вешается на ColorRect во весь экран.

group_uniforms Sky;
uniform vec4 sky_top : source_color = vec4(0.008, 0.012, 0.035, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.035, 0.015, 0.075, 1.0);
uniform vec4 nebula_color_a : source_color = vec4(0.45, 0.12, 0.65, 1.0);
uniform vec4 nebula_color_b : source_color = vec4(0.05, 0.40, 0.75, 1.0);
uniform float nebula_strength : hint_range(0.0, 2.0) = 0.6;

group_uniforms Stars;
uniform float star_density : hint_range(0.0, 2.0) = 1.0;
uniform float drift_speed : hint_range(0.0, 0.1) = 0.006;
uniform bool show_meteors = true;
uniform float meteor_period : hint_range(1.0, 30.0) = 6.0;

group_uniforms Planet;
uniform bool show_planet = true;
// Центр планеты в долях экрана (0..1), радиус — в долях высоты экрана.
uniform vec2 planet_center = vec2(0.8, 0.78);
uniform float planet_radius : hint_range(0.05, 1.5) = 0.32;
uniform vec4 planet_color_a : source_color = vec4(0.08, 0.22, 0.5, 1.0);
uniform vec4 planet_color_b : source_color = vec4(0.5, 0.78, 0.95, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform float planet_spin : hint_range(-1.0, 1.0) = 0.03;

group_uniforms Warp;
// 0 — обычный космос, 1 — полный прыжок в гиперпространство.
uniform float warp : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

#include "res://shaders/space_common.gdshaderinc"

vec3 nebula(vec2 p, float t) {
	vec2 q = p * 1.4 + vec2(t * 0.004, 0.0);
	float n1 = fbm(q, 4);
	float n2 = fbm(q * 1.8 + vec2(n1 * 1.6, -n1 * 1.2) + vec2(3.1, 1.7) - vec2(0.0, t * 0.003), 3);
	float cloud_a = smoothstep(0.42, 0.85, n1);
	float cloud_b = smoothstep(0.48, 0.9, n2);
	vec3 color = nebula_color_a.rgb * cloud_a * 0.55 + nebula_color_b.rgb * cloud_b * 0.45;
	color *= 0.55 + 0.45 * value_noise(q * 6.0);
	return color * nebula_strength;
}

// Один слой звёзд: по одной звезде (или ни одной) на ячейку сетки.
vec3 star_layer(vec2 p, float scale, float density, float seed, float max_px, float px, float t) {
	vec2 g = p * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	if (hash21(id + seed) > density) {
		return vec3(0.0);
	}
	vec2 offset = vec2(hash21(id + seed + 17.1), hash21(id + seed + 31.7)) - 0.5;
	vec2 d = f - offset * 0.5;
	float bright = hash21(id + seed + 5.3);
	// Радиус в пикселях переводим в доли ячейки.
	float radius = mix(0.8, max_px, bright * bright) * px * scale;
	float dist = length(d);
	float core = 1.0 - smoothstep(radius * 0.25, radius, dist);
	float glow = exp(-dist / (radius * 1.8)) * 0.35;
	glow *= 1.0 - smoothstep(0.3, 0.5, max(abs(f.x), abs(f.y)));
	float twinkle = 0.6 + 0.4 * sin(t * (1.0 + hash21(id + seed + 2.2) * 3.0) + bright * 40.0);
	vec3 tint = mix(vec3(0.70, 0.82, 1.0), vec3(1.0, 0.86, 0.72), hash21(id + seed + 9.9));
	return tint * (core + glow) * twinkle * (0.35 + bright);
}

vec3 meteor(vec2 p, float t, float aspect, float px) {
	float slot = floor(t / meteor_period);
	float local_time = t - slot * meteor_period;
	float life = local_time - hash21(vec2(slot, 4.2)) * meteor_period * 0.5;
	float duration = 1.1;
	if (life < 0.0 || life > duration) {
		return vec3(0.0);
	}
	vec2 start = vec2(mix(0.35, 1.0, hash21(vec2(slot, 1.7))) * aspect, mix(0.0, 0.35, hash21(vec2(slot, 8.3))));
	vec2 dir = normalize(vec2(-1.0, mix(0.25, 0.6, hash21(vec2(slot, 2.9)))));
	float k = life / duration;
	vec2 head = start + dir * k * 0.9;
	vec2 tail = head - dir * 0.22 * smoothstep(0.0, 0.3, k);
	vec2 pa = p - tail;
	vec2 ba = head - tail;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
	float dist = length(pa - ba * h);
	float line = 1.0 - smoothstep(px * 0.5, px * 2.0, dist);
	return vec3(0.85, 0.92, 1.0) * line * h * h * sin(k * PI) * 1.5;
}

vec3 apply_planet(vec3 col, vec2 p, float aspect, float px, float t) {
	vec2 center = vec2(planet_center.x * aspect, planet_center.y);
	vec2 pd = (p - center) / planet_radius;
	float r = length(pd);
	float aa = 1.5 * px / planet_radius;
	float mask = 1.0 - smoothstep(1.0 - aa, 1.0, r);

	// Ореол атмосферы вокруг диска, ярче со стороны света.
	vec2 dir = pd / max(r, 0.0001);
	float lit_side = smoothstep(-0.4, 0.9, dot(vec2(dir.x, -dir.y), normalize(PLANET_LIGHT.xy)));
	float halo = exp(-max(r - 1.0, 0.0) * 12.0) * (0.12 + 0.55 * lit_side);
	col += atmosphere_color.rgb * halo * (1.0 - mask);

	if (r < 1.0) {
		vec3 body = planet_body(pd, t, planet_color_a.rgb, planet_color_b.rgb, atmosphere_color.rgb, planet_spin, true);
		col = mix(col, body, mask);
	}
	return col;
}

// Лучи гиперпространства, разлетающиеся из центра экрана.
vec3 hyperspace(vec2 d, float px, float t) {
	float r = length(d);
	float angle = atan(d.y, d.x) / TAU + 0.5;
	vec3 acc = vec3(0.0);
	for (int layer = 0; layer < 3; layer++) {
		float fl = float(layer);
		float rays = 60.0 + fl * 50.0;
		float cell = floor(angle * rays);
		float fa = fract(angle * rays) - 0.5;
		float h = hash21(vec2(cell, fl * 17.3 + 3.0));
		if (h < 0.3) {
			continue;
		}
		float jitter = (hash21(vec2(cell, fl * 5.1 + 11.0)) - 0.5) * 0.6;
		float speed = 0.6 + h * 0.9;
		float progress = fract(h * 13.7 + t * speed);
		float head = progress * progress * 1.4;
		float len = max((0.03 + 0.55 * progress) * warp, 0.001);
		float along = smoothstep(head - len, head, r) * (1.0 - smoothstep(head, head + 0.004, r));
		float width = (0.7 + 1.6 * progress) * px;
		float across = 1.0 - smoothstep(width * 0.5, width * 1.5, abs(fa - jitter) / rays * TAU * r);
		vec3 tint = mix(vec3(0.85, 0.95, 1.0), vec3(0.45, 0.75, 1.0), hash21(vec2(cell, fl + 0.5)));
		acc += tint * along * across * (0.4 + progress);
	}
	return acc;
}

void fragment() {
	float px = SCREEN_PIXEL_SIZE.y;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME;

	vec3 col = mix(sky_top.rgb, sky_bottom.rgb, uv.y);
	col += nebula(p, t);

	// Три слоя звёзд: дальние двигаются медленнее ближних.
	vec3 stars = vec3(0.0);
	stars += star_layer(p + vec2(t * drift_speed * 0.35, 0.0), 80.0, 0.3 * star_density, 1.0, 1.1, px, t) * 0.55;
	stars += star_layer(p + vec2(t * drift_speed, 0.0), 38.0, 0.22 * star_density, 7.0, 1.7, px, t) * 0.85;
	stars += star_layer(p + vec2(t * drift_speed * 2.4, 0.0), 16.0, 0.1 * star_density, 13.0, 2.6, px, t);
	if (show_meteors) {
		stars += meteor(p, t, aspect, px);
	}
	col += stars;

	if (show_planet) {
		col = apply_planet(col, p, aspect, px, t);
	}

	if (warp > 0.0) {
		vec2 d = p - vec2(0.5 * aspect, 0.5);
		col *= 1.0 - 0.85 * warp;
		col += hyperspace(d, px, t) * smoothstep(0.0, 0.4, warp) * 1.6;
		col += vec3(0.35, 0.65, 1.0) * exp(-length(d) * 4.0) * warp * 0.9;
	}

	// Виньетка по краям.
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.85;

	COLOR = vec4(col, 1.0);
}
