// Generates Node-API wrappers from the C signature of HashLink primitives.
//
// JS -> C : bool, integers and enums (int32 semantics, uint32 wraps), int64 and
//           pointers (JS numbers; null/undefined -> 0), float/double, and 8-byte
//           structs passed by value (descriptor handles, _I64 in HL).
// C -> JS : the same, null pointers become null.
#ifndef HL_SHIM_NAPI_PRIM_H
#define HL_SHIM_NAPI_PRIM_H

#define NAPI_VERSION 8
#include <node_api.h>
#include <type_traits>
#include <utility>
#include <map>
#include <string>
#include <string.h>

namespace hl_shim {

typedef napi_value (*Callback)( napi_env, napi_callback_info );

inline std::map<std::string, Callback> &registry() {
	static std::map<std::string, Callback> r;
	return r;
}

// a later registration under the same name replaces the previous one
struct Register {
	Register( const char *name, Callback cb ) { registry()[name] = cb; }
};

template<typename T> inline T fromJs( napi_env env, napi_value v ) {
	if constexpr( std::is_same_v<T, bool> ) {
		bool b = false;
		if( napi_get_value_bool(env, v, &b) != napi_ok ) {
			double d = 0;
			napi_get_value_double(env, v, &d);
			b = d != 0;
		}
		return b;
	} else if constexpr( std::is_floating_point_v<T> ) {
		double d = 0;
		napi_get_value_double(env, v, &d);
		return (T)d;
	} else if constexpr( std::is_pointer_v<T> ) {
		double d = 0;
		napi_get_value_double(env, v, &d);
		return reinterpret_cast<T>((uintptr_t)(uint64_t)d);
	} else if constexpr( std::is_enum_v<T> || std::is_integral_v<T> ) {
		if constexpr( sizeof(T) == 8 ) {
			double d = 0;
			napi_get_value_double(env, v, &d);
			return (T)(int64_t)d;
		} else {
			int32_t i = 0;
			napi_get_value_int32(env, v, &i);
			return (T)i;
		}
	} else if constexpr( std::is_class_v<T> && std::is_trivially_copyable_v<T> && sizeof(T) == 8 ) {
		double d = 0;
		napi_get_value_double(env, v, &d);
		int64_t i = (int64_t)d;
		T out;
		memcpy(&out, &i, 8);
		return out;
	} else {
		static_assert(sizeof(T) == 0, "unsupported primitive argument type");
	}
}

template<typename T> inline napi_value toJs( napi_env env, T v ) {
	napi_value r;
	if constexpr( std::is_same_v<T, bool> )
		napi_get_boolean(env, v, &r);
	else if constexpr( std::is_floating_point_v<T> )
		napi_create_double(env, (double)v, &r);
	else if constexpr( std::is_pointer_v<T> ) {
		if( v == nullptr )
			napi_get_null(env, &r);
		else
			napi_create_double(env, (double)(uintptr_t)v, &r);
	} else if constexpr( std::is_class_v<T> ) {
		static_assert(std::is_trivially_copyable_v<T> && sizeof(T) == 8, "unsupported primitive return type");
		int64_t i;
		memcpy(&i, &v, 8);
		napi_create_double(env, (double)i, &r);
	} else if constexpr( sizeof(T) == 8 )
		napi_create_double(env, (double)(int64_t)v, &r);
	else if constexpr( std::is_unsigned_v<T> )
		napi_create_uint32(env, (uint32_t)v, &r);
	else
		napi_create_int32(env, (int32_t)v, &r);
	return r;
}

template<auto F> struct Prim;

template<typename R, typename... A, R (*F)(A...)> struct Prim<F> {
	template<size_t... I> static napi_value invoke( napi_env env, napi_value *argv, std::index_sequence<I...> ) {
		if constexpr( std::is_void_v<R> ) {
			F(fromJs<A>(env, argv[I])...);
			return nullptr;
		} else
			return toJs<R>(env, F(fromJs<A>(env, argv[I])...));
	}
	static napi_value call( napi_env env, napi_callback_info info ) {
		constexpr size_t N = sizeof...(A);
		size_t argc = N;
		napi_value argv[N > 0 ? N : 1];
		napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
		if( argc < N ) {
			napi_value undef;
			napi_get_undefined(env, &undef);
			for( size_t i = argc; i < N; i++ ) argv[i] = undef;
		}
		try {
			return invoke(env, argv, std::index_sequence_for<A...>{});
		} catch( hl_shim_error &e ) {
			napi_throw_error(env, nullptr, e.msg);
			return nullptr;
		}
	}
};

template<auto F> constexpr Callback wrap() { return &Prim<F>::call; }

}

#endif
