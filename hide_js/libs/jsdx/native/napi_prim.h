// Generates Node-API wrappers from the C signature of HashLink primitives.
//
// JS -> C : bool, integers and enums (int32 semantics, uint32 wraps), pointers (JS numbers;
//           null/undefined -> 0) and float/double take one JS argument. 64 bits integers and
//           8-byte structs passed by value (descriptor handles, _I64 in HL) take two : their
//           low and high 32 bits words (exact, see hlemu.I64).
// C -> JS : the same, null pointers become null, 64 bits values become BigInt.
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

// 64 bits integers and 8-byte structs passed by value : two JS arguments (low, high)
template<typename T> constexpr bool is64 =
	(!std::is_same_v<T, bool> && (std::is_enum_v<T> || std::is_integral_v<T>) && sizeof(T) == 8)
	|| (std::is_class_v<T> && sizeof(T) == 8);

template<typename T> constexpr size_t argWidth = is64<T> ? 2 : 1;

template<typename T> inline T fromJs64( napi_env env, napi_value lo, napi_value hi ) {
	int32_t l = 0, h = 0;
	napi_get_value_int32(env, lo, &l);
	napi_get_value_int32(env, hi, &h);
	uint64_t v = (uint64_t)(uint32_t)l | ((uint64_t)(uint32_t)h << 32);
	T out;
	memcpy(&out, &v, 8);
	return out;
}

template<typename T> inline T fromJs( napi_env env, napi_value v ) {
	static_assert(!is64<T>, "64 bits arguments take two JS values : use arg()");
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
		int32_t i = 0;
		napi_get_value_int32(env, v, &i);
		return (T)i;
	} else {
		static_assert(sizeof(T) == 0, "unsupported primitive argument type");
	}
}

// the C argument starting at argv[i]
template<typename T> inline T arg( napi_env env, napi_value *argv, size_t i ) {
	if constexpr( is64<T> ) {
		static_assert(std::is_trivially_copyable_v<T>, "unsupported primitive argument type");
		return fromJs64<T>(env, argv[i], argv[i + 1]);
	} else
		return fromJs<T>(env, argv[i]);
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
	} else if constexpr( std::is_class_v<T> || sizeof(T) == 8 ) {
		static_assert(std::is_trivially_copyable_v<T> && sizeof(T) == 8, "unsupported primitive return type");
		int64_t i;
		memcpy(&i, &v, 8);
		napi_create_bigint_int64(env, i, &r);
	} else if constexpr( std::is_unsigned_v<T> )
		napi_create_uint32(env, (uint32_t)v, &r);
	else
		napi_create_int32(env, (int32_t)v, &r);
	return r;
}

template<auto F> struct Prim;

template<typename R, typename... A, R (*F)(A...)> struct Prim<F> {
	static constexpr size_t widths[] = { argWidth<A>..., 0 };
	// index of the first JS argument of the C argument i
	static constexpr size_t jsIndex( size_t i ) {
		size_t n = 0;
		for( size_t k = 0; k < i; k++ ) n += widths[k];
		return n;
	}
	template<size_t... I> static napi_value invoke( napi_env env, napi_value *argv, std::index_sequence<I...> ) {
		if constexpr( std::is_void_v<R> ) {
			F(arg<A>(env, argv, jsIndex(I))...);
			return nullptr;
		} else
			return toJs<R>(env, F(arg<A>(env, argv, jsIndex(I))...));
	}
	static napi_value call( napi_env env, napi_callback_info info ) {
		constexpr size_t N = jsIndex(sizeof...(A));
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
