package hlemu;

/**
	JS emulation of `hl.I64` : a 64 bits integer stored as a haxe.Int64 (exact on 64 bits :
	GPU addresses, descriptor handles, sizes, fence values).

	At the native boundary (hlemu.Macros.makeNativeCall), a 64 bits argument is passed as its
	two 32 bits words (low, high) and a 64 bits result comes back as a BigInt.

	Also hosts the conversions between JS numbers (CPU pointers, see hlemu.Bytes) and haxe.Int64.
**/
@:notNull abstract I64(haxe.Int64) from haxe.Int64 to haxe.Int64 {

	@:from static inline function fromInt( v : Int ) : I64 {
		return haxe.Int64.ofInt(v);
	}

	/** the low 32 bits, as the I64 to Int conversion of HL **/
	public inline function toInt() : Int {
		return this.low;
	}

	@:to inline function implicitToInt() : Int {
		return toInt();
	}

	/** a 64 bits native result (BigInt) **/
	public static inline function ofBigInt( v : Dynamic ) : haxe.Int64 {
		return haxe.Int64.make(js.Syntax.code("Number(BigInt.asIntN(32, ({0}) >> 32n))", v), js.Syntax.code("Number(BigInt.asIntN(32, ({0})))", v));
	}

	// the arguments of js.Syntax.code are pasted without parentheses once inlined : without them,
	// ofInt64(toInt64(v)) gave "x | 0 >>> 0" (">>>" first : a signed low word, addresses 4 GB off)

	/** a JS number (CPU pointer) as a haxe.Int64 **/
	public static inline function toInt64( v : Float ) : haxe.Int64 {
		var high = Math.floor(v / 4294967296.);
		return haxe.Int64.make(Std.int(high), js.Syntax.code("((({0}) >>> 0) | 0)", v - high * 4294967296.));
	}

	/** a haxe.Int64 as a JS number (CPU pointer, exact below 2^53) **/
	public static inline function ofInt64( v : haxe.Int64 ) : Float {
		return v.high * 4294967296. + js.Syntax.code("(({0}) >>> 0)", v.low);
	}
}
