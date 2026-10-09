package hlemu;

class Api {
	public static inline function unsafeCast<From,To>( v : From ) : To {
		return cast v;
	}
	public static inline function rethrow( v : Dynamic ) : Void {
		throw v;
	}
}
