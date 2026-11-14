// Общие функции для космических шейдеров: шум и освещённый диск планеты.

// Направление на «солнце» (свет падает слева сверху).
const vec3 PLANET_LIGHT = vec3(-0.65, 0.45, 0.6);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Фрактальный шум; меньше октав — быстрее, но менее детально.
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) {
			break;
		}
		value += amp * value_noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return value;
}

// Кратеры: не больше одного на ячейку, целиком внутри неё.
// Возвращает поправку к яркости: дно темнее, вал светлее.
float craters(vec2 p) {
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	if (hash21(id + 3.7) > 0.55) {
		return 0.0;
	}
	vec2 center = (vec2(hash21(id + 1.3), hash21(id + 8.1)) - 0.5) * 0.3;
	float radius = mix(0.12, 0.28, hash21(id + 5.9));
	float d = length(f - center) / radius;
	float pit = (1.0 - smoothstep(0.75, 1.0, d)) * -0.35;
	float rim = smoothstep(0.75, 0.95, d) * (1.0 - smoothstep(0.95, 1.2, d)) * 0.25;
	return pit + rim;
}

// Цвет освещённой планеты в точке pd (в радиусах планеты, |pd| < 1, ось y вниз).
// gas_giant: полосы и облака; иначе — каменистая поверхность с кратерами.
vec3 planet_body(vec2 pd, float t, vec3 color_a, vec3 color_b, vec3 atmosphere, float spin, bool gas_giant) {
	vec3 light = normalize(PLANET_LIGHT);
	float z = sqrt(max(1.0 - dot(pd, pd), 0.0));
	vec3 n = vec3(pd.x, -pd.y, z);
	float diffuse = max(dot(n, light), 0.0);
	float lon = atan(n.x, n.z) + t * spin;
	float lat = asin(clamp(n.y, -1.0, 1.0));

	vec3 surface;
	if (gas_giant) {
		vec2 sp = vec2(lon * 1.2, lat * 2.4);
		float swirl = fbm(sp * 1.5 + vec2(5.2, 1.3), 3);
		float bands = fbm(vec2(sp.x * 0.6, sp.y * 3.0) + swirl * 1.3, 5);
		surface = mix(color_a, color_b, smoothstep(0.3, 0.75, bands));
		float clouds = smoothstep(0.55, 0.8, fbm(sp * 2.6 + vec2(t * spin * 1.5, 3.7), 3));
		surface = mix(surface, vec3(0.92, 0.95, 1.0), clouds * 0.45);
	} else {
		vec2 sp = vec2(lon, lat) * 2.0;
		float terrain = fbm(sp * 1.6 + vec2(2.3, 7.1), 5);
		surface = mix(color_a, color_b, smoothstep(0.3, 0.7, terrain));
		surface *= 1.0 + craters(sp * 3.0) + craters(sp * 6.0 + 11.0) * 0.6;
	}

	vec3 body = surface * (0.03 + 1.15 * diffuse);
	float rim = pow(1.0 - z, 2.5);
	body += atmosphere * rim * (0.1 + 0.9 * smoothstep(-0.2, 0.7, dot(n, light)));
	return body;
}
