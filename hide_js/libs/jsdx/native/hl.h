// Minimal replacement of HashLink's hl.h, so that hldx's dx12.cpp compiles unmodified
// as a Node-API addon. Only what dx12.cpp uses is provided.
//
// Every DEFINE_PRIM registers its C function in a table; napi_prim.h generates the
// JS wrapper from the C signature: numbers for integers, floats, enums, int64 and
// pointers (all addresses are passed as JS numbers, exact below 2^53).
#ifndef HL_SHIM_H
#define HL_SHIM_H

#define HL_WIN
#define HL_WIN_DESKTOP
#define HL_64
#define HL_VS

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <stdarg.h>

typedef unsigned char vbyte;
typedef wchar_t uchar;
typedef long long int64;
typedef unsigned long long uint64;

#define USTR(str) L##str

// Haxe types are never inspected by dx12.cpp: they only have to exist
typedef struct hl_type { int kind; } hl_type;
extern hl_type hlt_bytes, hlt_i32, hlt_bool, hlt_dyn, hlt_abstract;

typedef struct vdynamic {
	hl_type *t;
	union {
		bool b;
		int i;
		int64 i64;
		double d;
		void *ptr;
	} v;
} vdynamic;

// same layout as HL: the data follows the header
typedef struct varray {
	hl_type *t;
	hl_type *at;
	int size;
	int __pad;
} varray;

#define hl_aptr(a,t) ((t*)(((varray*)(a))+1))

typedef struct vclosure {
	hl_type *t;
	void *fun;
	int hasValue;
	void *value;
} vclosure;

#define HL_PRIM
#define HL_API
#define EXPORT

// ---- memory: dx12.cpp results that HL would GC are malloc'ed here.
// The JS side copies what it needs and frees them (see hlemu.Bytes).

static inline void *hl_gc_alloc_raw( int size ) { return calloc(1, size); }

static inline vbyte *hl_copy_bytes( const vbyte *b, int size ) {
	vbyte *out = (vbyte*)malloc(size ? size : 1);
	memcpy(out, b, size);
	return out;
}

static inline varray *hl_alloc_array( hl_type *t, int size ) {
	varray *a = (varray*)calloc(1, sizeof(varray) + sizeof(void*) * size);
	a->t = &hlt_dyn;
	a->at = t;
	a->size = size;
	return a;
}

static inline int ustrlen( const uchar *s ) { return (int)wcslen(s); }

static inline uchar *ustrdup( const uchar *s ) {
	int len = ustrlen(s) + 1;
	uchar *out = (uchar*)malloc(len * sizeof(uchar));
	memcpy(out, s, len * sizeof(uchar));
	return out;
}

static inline uchar *hl_to_utf16( const char *str ) {
	int len = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
	uchar *out = (uchar*)malloc(len * sizeof(uchar));
	MultiByteToWideChar(CP_UTF8, 0, str, -1, out, len);
	return out;
}

// ---- errors: thrown as C++ exceptions, turned into JS exceptions by the wrapper

struct hl_shim_error {
	char msg[8192];
};

// dx12.cpp prints the D3D12 debug layer messages with printf : the renderer process has
// no console, they are kept and appended to the next error
static char hl_shim_log[6144];
static size_t hl_shim_log_len = 0;

static inline int hl_shim_printf( const char *fmt, ... ) {
	char tmp[1024];
	va_list args;
	va_start(args, fmt);
	int n = vsnprintf(tmp, sizeof(tmp), fmt, args);
	va_end(args);
	size_t len = strlen(tmp);
	if( hl_shim_log_len + len >= sizeof(hl_shim_log) ) hl_shim_log_len = 0;
	memcpy(hl_shim_log + hl_shim_log_len, tmp, len + 1);
	hl_shim_log_len += len;
	return n;
}

// HL formats errors as UTF-16, "%s" arguments are uchar* (MSVC wide printf semantics)
static inline void hl_shim_throw( const char *fmt, ... ) {
	wchar_t wfmt[256], wmsg[1024];
	MultiByteToWideChar(CP_UTF8, 0, fmt, -1, wfmt, 256);
	va_list args;
	va_start(args, fmt);
	_vsnwprintf_s(wmsg, 1024, _TRUNCATE, wfmt, args);
	va_end(args);
	hl_shim_error e;
	int len = WideCharToMultiByte(CP_UTF8, 0, wmsg, -1, e.msg, sizeof(e.msg), NULL, NULL);
	if( hl_shim_log_len > 0 && len > 0 ) {
		snprintf(e.msg + len - 1, sizeof(e.msg) - len, "\n%s", hl_shim_log);
		hl_shim_log_len = 0;
	}
	throw e;
}

#define printf hl_shim_printf

#define hl_error(msg, ...) hl_shim_throw(msg, ##__VA_ARGS__)

// ---- threads / GC: nothing to do, JS calls are on one thread

static inline void hl_blocking( bool b ) {}
static inline void hl_add_root( void *r ) {}
static inline void *hl_get_thread() { return (void*)1; }
static inline void hl_register_thread( void *ctx ) {}
static inline void hl_unregister_thread() {}
// GPU crash dumps (Aftermath) call back into Haxe: not supported in JS
static inline vdynamic *hl_dyn_call( vclosure *c, vdynamic **args, int nargs ) { return NULL; }

// ---- primitives registration

#include "napi_prim.h"

#define DEFINE_PRIM(t, name, args) static hl_shim::Register HL_SHIM_CAT(__prim_, name)(#name, hl_shim::wrap<&HL_NAME(name)>());
#define HL_SHIM_CAT2(a,b) a##b
#define HL_SHIM_CAT(a,b) HL_SHIM_CAT2(a,b)

#endif
