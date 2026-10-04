// Minimal C++ emulation of the Metal Shading Language standard library, used only to
// syntax/type-check Shaders.metal with clang on machines without the Metal compiler.
#pragma once
typedef float float2 __attribute__((ext_vector_type(2)));
typedef float float3 __attribute__((ext_vector_type(3)));
typedef float float4 __attribute__((ext_vector_type(4)));
typedef int int2 __attribute__((ext_vector_type(2)));
typedef unsigned int uint;
typedef unsigned char uchar;
typedef unsigned char uchar4 __attribute__((ext_vector_type(4)));
typedef unsigned short ushort;
typedef __fp16 half;

#define device
#define constant
#define thread
#define threadgroup
#define vertex
#define fragment
#define kernel

namespace metal {
inline float2 make_float2(float a, float b) { float2 r; r.x = a; r.y = b; return r; }
inline float2 make_float2(float a) { return make_float2(a, a); }
inline float3 make_float3(float a, float b, float c) { float3 r; r.x = a; r.y = b; r.z = c; return r; }
inline float3 make_float3(float a) { return make_float3(a, a, a); }
inline float3 make_float3(float2 a, float b) { return make_float3(a.x, a.y, b); }
inline float3 make_float3(float a, float2 b) { return make_float3(a, b.x, b.y); }
inline float4 make_float4(float a, float b, float c, float d) { float4 r; r.x = a; r.y = b; r.z = c; r.w = d; return r; }
inline float4 make_float4(float a) { return make_float4(a, a, a, a); }
inline float4 make_float4(float3 a, float b) { return make_float4(a.x, a.y, a.z, b); }
inline float4 make_float4(float2 a, float b, float c) { return make_float4(a.x, a.y, b, c); }
inline float4 make_float4(float2 a, float2 b) { return make_float4(a.x, a.y, b.x, b.y); }

struct float4x4 {
    float4 c[4];
    float4& operator[](int i) { return c[i]; }
    const float4& operator[](int i) const { return c[i]; }
};
struct float3x3 {
    float3 c[3];
    float3& operator[](int i) { return c[i]; }
    const float3& operator[](int i) const { return c[i]; }
};
inline float3x3 make_float3x3(float3 a, float3 b, float3 c) { float3x3 m; m.c[0] = a; m.c[1] = b; m.c[2] = c; return m; }
inline float4 operator*(const float4x4& m, float4 v) { return m.c[0] * v.x + m.c[1] * v.y + m.c[2] * v.z + m.c[3] * v.w; }
inline float3 operator*(const float3x3& m, float3 v) { return m.c[0] * v.x + m.c[1] * v.y + m.c[2] * v.z; }
inline float4x4 operator*(const float4x4& a, const float4x4& b) { float4x4 r; for (int i = 0; i < 4; i++) r.c[i] = a * b.c[i]; return r; }

#define F1(name, expr) \
  inline float name(float x) { return expr; } \
  inline float2 name(float2 v) { return make_float2(name(v.x), name(v.y)); } \
  inline float3 name(float3 v) { return make_float3(name(v.x), name(v.y), name(v.z)); } \
  inline float4 name(float4 v) { return make_float4(name(v.x), name(v.y), name(v.z), name(v.w)); }
F1(sin, __builtin_sinf(x))
F1(cos, __builtin_cosf(x))
F1(tan, __builtin_tanf(x))
F1(exp, __builtin_expf(x))
F1(exp2, __builtin_exp2f(x))
F1(log, __builtin_logf(x))
F1(sqrt, __builtin_sqrtf(x))
F1(rsqrt, 1.0f / __builtin_sqrtf(x))
F1(floor, __builtin_floorf(x))
F1(ceil, __builtin_ceilf(x))
F1(fract, x - __builtin_floorf(x))
F1(abs, __builtin_fabsf(x))
F1(saturate, x < 0.0f ? 0.0f : (x > 1.0f ? 1.0f : x))
F1(sign, x > 0.0f ? 1.0f : (x < 0.0f ? -1.0f : 0.0f))
#undef F1
inline float atan2(float y, float x) { return __builtin_atan2f(y, x); }
inline float pow(float a, float b) { return __builtin_powf(a, b); }
inline float fmod(float a, float b) { return __builtin_fmodf(a, b); }
inline float max(float a, float b) { return a > b ? a : b; }
inline float min(float a, float b) { return a < b ? a : b; }
inline int max(int a, int b) { return a > b ? a : b; }
inline int min(int a, int b) { return a < b ? a : b; }
inline uint max(uint a, uint b) { return a > b ? a : b; }
inline uint min(uint a, uint b) { return a < b ? a : b; }
inline float clamp(float x, float a, float b) { return min(max(x, a), b); }
inline float mix(float a, float b, float t) { return a + (b - a) * t; }
inline float step(float e, float x) { return x < e ? 0.0f : 1.0f; }
inline float smoothstep(float e0, float e1, float x) { float t = saturate((x - e0) / (e1 - e0)); return t * t * (3.0f - 2.0f * t); }
#define VOPS(T, N) \
  inline T max(T a, T b) { T r; for (int i = 0; i < N; i++) r[i] = max(a[i], b[i]); return r; } \
  inline T min(T a, T b) { T r; for (int i = 0; i < N; i++) r[i] = min(a[i], b[i]); return r; } \
  inline T clamp(T x, T a, T b) { return min(max(x, a), b); } \
  inline T clamp(T x, float a, float b) { T r; for (int i = 0; i < N; i++) r[i] = clamp(x[i], a, b); return r; } \
  inline T mix(T a, T b, float t) { return a + (b - a) * t; } \
  inline T mix(T a, T b, T t) { return a + (b - a) * t; } \
  inline T pow(T a, T b) { T r; for (int i = 0; i < N; i++) r[i] = pow(a[i], b[i]); return r; } \
  inline T step(T e, T x) { T r; for (int i = 0; i < N; i++) r[i] = step(e[i], x[i]); return r; } \
  inline T smoothstep(float e0, float e1, T x) { T r; for (int i = 0; i < N; i++) r[i] = smoothstep(e0, e1, x[i]); return r; } \
  inline float dot(T a, T b) { float s = 0; for (int i = 0; i < N; i++) s += a[i] * b[i]; return s; } \
  inline float length(T a) { return sqrt(dot(a, a)); } \
  inline float distance(T a, T b) { return length(a - b); } \
  inline T normalize(T a) { return a / length(a); }
VOPS(float2, 2)
VOPS(float3, 3)
VOPS(float4, 4)
#undef VOPS
inline float3 cross(float3 a, float3 b) { return make_float3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x); }
inline float3 reflect(float3 i, float3 n) { return i - 2.0f * dot(n, i) * n; }

namespace coord { enum C { normalized, pixel }; }
namespace filter { enum F { nearest, linear }; }
namespace mip_filter { enum M { none, nearest, linear }; }
namespace address { enum A { repeat, clamp_to_edge, mirrored_repeat }; }
namespace compare_func { enum CF { never, less, less_equal, greater, greater_equal, equal, not_equal, always }; }
struct sampler {
    template <typename... Args> constexpr sampler(Args...) {}
};
enum class access { sample, read, write };
template <typename T, access A = access::sample> struct texture2d {
    float4 sample(sampler, float2) const { return make_float4(0.0f); }
    float4 sample(sampler, float2, float) const { return make_float4(0.0f); }
    uint get_width() const { return 1; }
    uint get_height() const { return 1; }
};
template <typename T, access A = access::sample> struct texture2d_array {
    float4 sample(sampler, float2, uint) const { return make_float4(0.0f); }
};
template <typename T, access A = access::sample> struct depth2d {
    float sample_compare(sampler, float2, float) const { return 1.0f; }
    float sample(sampler, float2) const { return 1.0f; }
};
}
