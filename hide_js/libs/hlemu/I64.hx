package hlemu;

/**
	JS emulation of `hl.I64` : a 64 bits integer stored as a JS number (exact below 2^53,
	enough for sizes, offsets, fence values and addresses).

	Also hosts the conversions between JS numbers and haxe.Int64.
**/
@:notNull abstract I64(Float) from Int from Float to Float {

	public inline function toInt() : Int {
		return Std.int(this);
	}

	@:to inline function implicitToInt() : Int {
		return toInt();
	}

	// the arguments of js.Syntax.code are pasted without parentheses once inlined : without them,
	// ofInt64(toInt64(v)) gave "x | 0 >>> 0" (">>>" first : a signed low word, addresses 4 GB off)

	public static inline function toInt64( v : Float ) : haxe.Int64 {
		var high = Math.floor(v / 4294967296.);
		return haxe.Int64.make(Std.int(high), js.Syntax.code("((({0}) >>> 0) | 0)", v - high * 4294967296.));
	}

	public static inline function ofInt64( v : haxe.Int64 ) : Float {
		return v.high * 4294967296. + js.Syntax.code("(({0}) >>> 0)", v.low);
	}
}
