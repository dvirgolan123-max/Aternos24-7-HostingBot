//
//  Shaders.metal
//  Ashvale
//
//  All rendering shaders: lit world geometry (terrain splatting, materials,
//  foliage sway, cascaded-free directional shadows with PCF, flashlight,
//  muzzle light, fog, tonemapping and damage grading), depth-only shadow
//  pass, procedural sky with clouds/sun/moon/stars, water, particles and rain.
//

#include <metal_stdlib>
using namespace metal;

struct FrameUniforms {
    float4x4 viewProj;
    float4x4 view;
    float4x4 invViewProj;
    float4x4 shadowViewProj;
    float4x4 viewModelProj;
    float4 cameraPos;
    float4 sunDir;
    float4 sunColor;
    float4 skyAmbient;
    float4 groundAmbient;
    float4 skyZenith;
    float4 skyHorizon;
    float4 fogColor;
    float4 fogParams;
    float4 flashlightPos;
    float4 flashlightDir;
    float4 pointLight;
    float4 screen;
    float4 grade;
    float4 wind;
    float4 moonDir;
};

struct InstanceData {
    float4x4 model;
    float4 tint;
    float4 params;
};

struct ParticleData {
    float4 posSize;
    float4 color;
    float4 velKind;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
    float4 color    [[attribute(3)]];
    uchar4 material [[attribute(4)]];
    float4 weights  [[attribute(5)]];
};

struct VOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 uv;
    float4 color;
    float4 weights;
    float4 tint;
    float4 params;
    float4 shadowPos;
    uint material [[flat]];
    uint flags [[flat]];
};

struct ShadowOut {
    float4 position [[position]];
};

struct SkyOut {
    float4 position [[position]];
    float2 ndc;
};

struct POut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float kind;
};

constant float2 kQuadCorners[6] = {
    float2(-1.0, -1.0), float2(1.0, -1.0), float2(1.0, 1.0),
    float2(-1.0, -1.0), float2(1.0, 1.0), float2(-1.0, 1.0)
};

// MARK: - Helpers

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float hash11(float n) {
    return fract(sin(n * 12.9898) * 43758.5453);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 w = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

static float fbmNoise(float2 p) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        s += a * vnoise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return s;
}

static float3 toLinear(float3 c) {
    return c * c;
}

static float3 skyColor(float3 dir, constant FrameUniforms &u, bool details) {
    float up = clamp(dir.y, -1.0, 1.0);
    float t = sqrt(clamp(up, 0.0, 1.0));
    float3 col = mix(u.skyHorizon.rgb, u.skyZenith.rgb, t);
    if (up < 0.0) {
        float3 below = u.skyHorizon.rgb * 0.7 + u.groundAmbient.rgb * 0.15;
        col = mix(u.skyHorizon.rgb, below, clamp(-up * 4.0, 0.0, 1.0));
    }
    float3 L = normalize(u.sunDir.xyz);
    float sd = max(dot(dir, L), 0.0);
    float glow = pow(sd, 8.0) * 0.22 + pow(sd, 64.0) * 0.5;
    col += u.sunColor.rgb * glow * u.sunDir.w;
    if (details) {
        col += u.sunColor.rgb * smoothstep(0.99935, 0.9997, sd) * 10.0 * u.sunDir.w * (1.0 - u.fogParams.z);
        if (dir.y > 0.01) {
            float2 cp = dir.xz / (dir.y + 0.1) * 1.4 + u.wind.xy * u.cameraPos.w * 0.004;
            float n = fbmNoise(cp);
            float cov = u.fogParams.w;
            float c = smoothstep(0.75 - cov * 0.55, 0.95 - cov * 0.45, n);
            float lit = 0.55 + 0.45 * saturate(u.sunDir.w);
            float3 cloudCol = mix(u.skyHorizon.rgb, float3(1.0, 1.0, 1.0), 0.45) * lit;
            cloudCol = mix(cloudCol, u.skyAmbient.rgb * 0.8, u.fogParams.z * 0.85);
            cloudCol = mix(cloudCol, cloudCol * 0.62, saturate(cov - 0.55) * 1.6);
            col = mix(col, cloudCol, c * smoothstep(0.01, 0.16, dir.y));
        }
        if (u.moonDir.w > 0.01 && dir.y > 0.0) {
            float3 sp = dir * 260.0;
            float s = hash21(floor(sp.xz + float2(sp.y * 13.0, sp.y * 7.0)));
            float star = step(0.9968, s) * u.moonDir.w * saturate(1.0 - u.fogParams.w * 1.2);
            col += float3(star, star, star) * 0.9;
            float md = max(dot(dir, normalize(u.moonDir.xyz)), 0.0);
            col += float3(0.75, 0.8, 0.95) * smoothstep(0.9988, 0.9993, md) * u.moonDir.w * 1.5;
            col += float3(0.08, 0.09, 0.12) * pow(md, 32.0) * u.moonDir.w;
        }
    }
    return col;
}

static float3 gradeColor(float3 c, constant FrameUniforms &u, float2 pixel) {
    c *= u.grade.w;
    c = saturate((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14));
    float l = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = mix(float3(l, l, l), c, u.grade.x);
    float2 d = pixel / u.screen.xy - 0.5;
    float r2 = dot(d, d);
    c *= 1.0 - r2 * u.grade.y * 1.5;
    c = mix(c, float3(0.45, 0.0, 0.0), saturate(u.grade.z * r2 * 3.5));
    return c;
}

static float sampleShadow(float4 sp, depth2d<float> shadowMap, constant FrameUniforms &u) {
    constexpr sampler ss(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less_equal);
    float3 p = sp.xyz / sp.w;
    float2 uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || p.z > 1.0 || p.z < 0.0) {
        return 1.0;
    }
    float texel = u.screen.z;
    float bias = 0.0008;
    float sum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            sum += shadowMap.sample_compare(ss, uv + float2(float(x), float(y)) * texel, p.z - bias);
        }
    }
    return sum / 9.0;
}

static float fogAmount(float dist, float height, constant FrameUniforms &u) {
    float density = u.fogColor.w;
    float heightFade = exp(-max(height - 45.0, 0.0) * u.fogParams.x);
    return 1.0 - exp(-dist * density * mix(0.35, 1.0, heightFade));
}

// MARK: - Lit geometry

static VOut makeVOut(VertexIn in, InstanceData inst, constant FrameUniforms &u, bool viewModel) {
    VOut o;
    float4 wp = inst.model * float4(in.position, 1.0);
    uint flags = uint(in.material.y);
    if ((flags & 8u) != 0u && inst.params.x > 0.0) {
        float h = max(in.position.y, 0.0);
        float t = u.cameraPos.w;
        float phase = wp.x * 0.11 + wp.z * 0.07;
        float sway = (sin(t * 1.3 + phase) * 0.6 + sin(t * 2.7 + phase * 2.1) * 0.25) * u.wind.z;
        float2 offs = u.wind.xy * (sway * h * 0.025 * inst.params.x);
        wp.x += offs.x;
        wp.z += offs.y;
    }
    o.worldPos = wp.xyz;
    if (viewModel) {
        o.position = u.viewModelProj * (u.view * wp);
    } else {
        o.position = u.viewProj * wp;
    }
    float3x3 nm = float3x3(inst.model[0].xyz, inst.model[1].xyz, inst.model[2].xyz);
    o.normal = normalize(nm * in.normal);
    o.uv = in.uv;
    o.color = in.color;
    o.weights = in.weights;
    o.tint = inst.tint;
    o.params = inst.params;
    o.shadowPos = u.shadowViewProj * wp;
    o.material = uint(in.material.x);
    o.flags = flags;
    return o;
}

vertex VOut lit_vertex(VertexIn in [[stage_in]],
                       device const InstanceData *instances [[buffer(1)]],
                       constant FrameUniforms &u [[buffer(2)]],
                       uint iid [[instance_id]]) {
    return makeVOut(in, instances[iid], u, false);
}

vertex VOut viewmodel_vertex(VertexIn in [[stage_in]],
                             device const InstanceData *instances [[buffer(1)]],
                             constant FrameUniforms &u [[buffer(2)]],
                             uint iid [[instance_id]]) {
    return makeVOut(in, instances[iid], u, true);
}

fragment float4 lit_fragment(VOut in [[stage_in]],
                             constant FrameUniforms &u [[buffer(0)]],
                             texture2d_array<float> albedo [[texture(0)]],
                             depth2d<float> shadowMap [[texture(1)]],
                             sampler texSampler [[sampler(0)]],
                             bool frontFacing [[front_facing]]) {
    uint flags = in.flags;
    float3 base;
    if (in.material == 255u) {
        float2 uv = in.uv;
        float3 g = albedo.sample(texSampler, uv, 0).rgb;
        float3 d = albedo.sample(texSampler, uv, 1).rgb;
        float3 r = albedo.sample(texSampler, uv * 0.5, 2).rgb;
        float3 f = albedo.sample(texSampler, uv, 3).rgb;
        float macro = albedo.sample(texSampler, uv * 0.031, 0).g;
        if ((flags & 2u) != 0u) {
            float rows = sin(in.worldPos.z * 4.2) * 0.5 + 0.5;
            float3 field = albedo.sample(texSampler, uv, 22).rgb * (0.75 + rows * 0.35);
            d = mix(d, field, 0.85);
        }
        float4 w = in.weights;
        base = (g * w.x + d * w.y + r * w.z + f * w.w) / max(w.x + w.y + w.z + w.w, 0.001);
        base *= mix(0.82, 1.15, saturate(macro * 2.2 - 0.3));
    } else {
        float layer = in.tint.a >= 0.0 ? in.tint.a : float(in.material);
        base = albedo.sample(texSampler, in.uv, uint(layer)).rgb;
    }
    base *= toLinear(in.color.rgb);
    if ((flags & 1u) != 0u) {
        base *= toLinear(in.tint.rgb);
    }
    base *= 1.0 - in.params.w * 0.6;

    float3 N = normalize(in.normal);
    if (!frontFacing) {
        N = -N;
    }
    float3 V = u.cameraPos.xyz - in.worldPos;
    float dist = length(V);
    V = V / max(dist, 0.0001);
    float3 L = normalize(u.sunDir.xyz);
    float ndl = dot(N, L);
    float wrap = 0.0;
    if ((flags & 32u) != 0u) { wrap = 0.35; }
    if ((flags & 8u) != 0u) { wrap = 0.5; }
    float diffuse = saturate((ndl + wrap) / (1.0 + wrap));
    float shadow = 1.0;
    if (diffuse > 0.0 && u.sunDir.w > 0.0) {
        float fade = saturate((dist - u.screen.w * 0.8) / (u.screen.w * 0.2));
        shadow = mix(sampleShadow(in.shadowPos, shadowMap, u), 1.0, fade);
    }
    float skyVis = in.color.a;
    float3 ambient = mix(u.groundAmbient.rgb, u.skyAmbient.rgb, N.y * 0.5 + 0.5) * skyVis;
    float3 light = ambient + u.sunColor.rgb * (u.sunDir.w * diffuse * shadow);

    float gloss = (flags & 16u) != 0u ? 1.0 : 0.0;
    float wet = u.fogParams.y * step(0.8, skyVis) * saturate(N.y);
    float specAmt = max(gloss * 0.6, wet * 0.5);
    float3 spec = float3(0.0, 0.0, 0.0);
    if (specAmt > 0.0) {
        float3 H = normalize(L + V);
        float s = pow(saturate(dot(N, H)), mix(24.0, 96.0, gloss)) * specAmt;
        spec = u.sunColor.rgb * (u.sunDir.w * s * shadow);
        base *= 1.0 - wet * 0.35;
    }
    if (u.flashlightPos.w > 0.0) {
        float3 toP = in.worldPos - u.flashlightPos.xyz;
        float fd = length(toP);
        float3 dirP = toP / max(fd, 0.001);
        float cone = smoothstep(u.flashlightDir.w, u.flashlightDir.w + 0.05, dot(dirP, normalize(u.flashlightDir.xyz)));
        float att = 1.0 / (1.0 + fd * fd * 0.015);
        float nd = saturate(dot(N, -dirP) * 0.8 + 0.2);
        light += float3(1.0, 0.95, 0.85) * (cone * att * nd * 3.5 * u.flashlightPos.w);
    }
    if (u.pointLight.w > 0.0) {
        float3 toL = u.pointLight.xyz - in.worldPos;
        float d2 = dot(toL, toL);
        float nd = saturate(dot(N, toL * rsqrt(max(d2, 0.0001))) * 0.7 + 0.3);
        light += float3(1.0, 0.72, 0.38) * (u.pointLight.w * nd / (1.0 + d2 * 0.4));
    }
    float3 col = base * light + spec;
    if ((flags & 4u) != 0u) {
        col += base * 1.5;
    }
    col += float3(0.9, 0.85, 0.55) * (in.params.z * (0.18 + 0.12 * sin(u.cameraPos.w * 6.0)));

    float3 fogCol = skyColor(-V, u, false) * u.fogColor.rgb;
    float fa = fogAmount(dist, in.worldPos.y, u);
    col = mix(col, fogCol, fa);
    return float4(gradeColor(col, u, in.position.xy), 1.0);
}

fragment float4 water_fragment(VOut in [[stage_in]],
                               constant FrameUniforms &u [[buffer(0)]],
                               texture2d_array<float> albedo [[texture(0)]],
                               depth2d<float> shadowMap [[texture(1)]],
                               sampler texSampler [[sampler(0)]]) {
    float t = u.cameraPos.w;
    float2 p = in.worldPos.xz;
    float nx = sin(p.x * 0.8 + t * 1.1) * 0.035 + sin(p.y * 1.3 - t * 0.9) * 0.025 + (vnoise(p * 0.6 + float2(t * 0.3, 0.0)) - 0.5) * 0.12;
    float nz = cos(p.y * 0.7 + t * 1.3) * 0.035 + (vnoise(p * 0.5 - float2(0.0, t * 0.25)) - 0.5) * 0.12;
    float rain = u.wind.w;
    if (rain > 0.0) {
        float2 cell = floor(p * 2.0);
        float h = hash21(cell + floor(t * 3.0));
        float ring = fract(t * 3.0 + h);
        float2 c = (cell + 0.5) / 2.0;
        float rd = length(p - c) * 4.0;
        float wave = sin((rd - ring * 3.0) * 12.0) * saturate(1.0 - ring) * step(rd, ring * 3.0) * rain;
        nx += wave * 0.08;
        nz += wave * 0.08;
    }
    float3 N = normalize(float3(nx, 1.0, nz));
    float3 Vv = u.cameraPos.xyz - in.worldPos;
    float dist = length(Vv);
    float3 V = Vv / max(dist, 0.001);
    float3 R = reflect(-V, N);
    float fres = 0.04 + 0.96 * pow(1.0 - saturate(dot(N, V)), 5.0);
    float3 refl = skyColor(R, u, false);
    float3 deep = float3(0.02, 0.07, 0.075) * (u.skyAmbient.rgb * 1.5 + u.sunColor.rgb * u.sunDir.w * 0.25);
    float3 col = mix(deep, refl, fres);
    float3 H = normalize(normalize(u.sunDir.xyz) + V);
    float shadow = mix(sampleShadow(in.shadowPos, shadowMap, u), 1.0, saturate((dist - u.screen.w * 0.8) / (u.screen.w * 0.2)));
    col += u.sunColor.rgb * (pow(saturate(dot(N, H)), 220.0) * 2.5 * u.sunDir.w * shadow);
    float3 fogCol = skyColor(-V, u, false) * u.fogColor.rgb;
    col = mix(col, fogCol, fogAmount(dist, in.worldPos.y, u));
    return float4(gradeColor(col, u, in.position.xy), 1.0);
}

// MARK: - Shadow pass

vertex ShadowOut shadow_vertex(VertexIn in [[stage_in]],
                               device const InstanceData *instances [[buffer(1)]],
                               constant FrameUniforms &u [[buffer(2)]],
                               uint iid [[instance_id]]) {
    ShadowOut o;
    float4 wp = instances[iid].model * float4(in.position, 1.0);
    o.position = u.shadowViewProj * wp;
    return o;
}

// MARK: - Sky

vertex SkyOut sky_vertex(uint vid [[vertex_id]]) {
    SkyOut o;
    float2 p = float2(float((vid << 1) & 2u), float(vid & 2u));
    o.ndc = p * 2.0 - 1.0;
    o.position = float4(o.ndc, 0.0, 1.0);
    return o;
}

fragment float4 sky_fragment(SkyOut in [[stage_in]], constant FrameUniforms &u [[buffer(0)]]) {
    float4 w = u.invViewProj * float4(in.ndc, 1.0, 1.0);
    float3 dir = normalize(w.xyz / w.w - u.cameraPos.xyz);
    float3 col = skyColor(dir, u, true);
    // Haze towards the horizon when foggy.
    float haze = saturate(u.fogColor.w * 260.0) * (1.0 - smoothstep(0.0, 0.35, abs(dir.y)));
    col = mix(col, skyColor(float3(dir.x, 0.0, dir.z), u, false) * u.fogColor.rgb, haze);
    return float4(gradeColor(col, u, in.position.xy), 1.0);
}

// MARK: - Particles

vertex POut particle_vertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            device const ParticleData *parts [[buffer(0)]],
                            constant FrameUniforms &u [[buffer(2)]]) {
    ParticleData pd = parts[iid];
    float2 c = kQuadCorners[vid];
    float3 right = float3(u.view[0][0], u.view[1][0], u.view[2][0]);
    float3 up = float3(u.view[0][1], u.view[1][1], u.view[2][1]);
    float3 pos = pd.posSize.xyz;
    float size = pd.posSize.w;
    float3 world;
    if (pd.velKind.w > 0.5 && pd.velKind.w < 1.5) {
        float3 vel = pd.velKind.xyz;
        float speed = length(vel);
        float3 axis = speed > 0.001 ? vel / speed : float3(0.0, 1.0, 0.0);
        float3 toCam = normalize(u.cameraPos.xyz - pos);
        float3 side = normalize(cross(axis, toCam));
        world = pos + side * (c.x * size) + axis * (c.y * max(speed * 0.02, size));
    } else {
        world = pos + (right * c.x + up * c.y) * size;
    }
    POut o;
    o.position = u.viewProj * float4(world, 1.0);
    o.uv = c;
    o.color = pd.color;
    o.kind = pd.velKind.w;
    return o;
}

vertex POut rain_vertex(uint vid [[vertex_id]],
                        uint iid [[instance_id]],
                        constant FrameUniforms &u [[buffer(2)]]) {
    float3 cam = u.cameraPos.xyz;
    float t = u.cameraPos.w;
    float fi = float(iid);
    float h1 = hash11(fi * 1.37 + 0.11);
    float h2 = hash11(fi * 2.11 + 0.37);
    float h3 = hash11(fi * 0.73 + 0.71);
    float box = 18.0;
    float cell = box * 2.0;
    float fall = 11.0 + h3 * 3.0;
    float3 pos;
    pos.x = cam.x + (fract((h1 * cell - cam.x) / cell) - 0.5) * cell;
    pos.z = cam.z + (fract((h3 * cell - cam.z) / cell) - 0.5) * cell;
    pos.y = cam.y + (fract((h2 * cell - t * fall - cam.y) / cell) - 0.5) * cell;
    float3 vel = float3(u.wind.x * u.wind.z * 3.0, -fall, u.wind.y * u.wind.z * 3.0);
    float3 axis = normalize(vel);
    float3 toCam = normalize(cam - pos);
    float3 side = normalize(cross(axis, toCam));
    float2 c = kQuadCorners[vid];
    float3 world = pos + side * (c.x * 0.008) + axis * (c.y * 0.35);
    POut o;
    o.position = u.viewProj * float4(world, 1.0);
    o.uv = c;
    float lit = 0.35 + 0.65 * saturate(u.sunDir.w + 0.2);
    o.color = float4(0.75 * lit, 0.8 * lit, 0.85 * lit, 0.28 * u.wind.w);
    o.kind = 1.0;
    return o;
}

fragment float4 particle_fragment(POut in [[stage_in]]) {
    float2 d = in.uv;
    float r = length(d);
    float a = 0.0;
    bool additive = false;
    if (in.kind < 0.5) {
        a = saturate(1.0 - r);
        a = a * a;
    } else if (in.kind < 1.5) {
        a = saturate(1.0 - abs(d.x)) * saturate(1.0 - abs(d.y) * 0.6);
    } else if (in.kind < 2.5) {
        float core = saturate(1.0 - r * 1.6);
        float rays = saturate(1.0 - abs(d.x) * 7.0) * saturate(1.0 - abs(d.y)) + saturate(1.0 - abs(d.y) * 7.0) * saturate(1.0 - abs(d.x));
        a = saturate(core * core * 1.5 + rays * 0.6);
        additive = true;
    } else {
        a = smoothstep(1.0, 0.1, r) * 0.7;
    }
    float alpha = in.color.a * a;
    float3 rgb = in.color.rgb * alpha;
    return float4(rgb, additive ? 0.0 : alpha);
}
