package hlemu;

#if !macro

import hlemu.Native as N;

/**
	JS emulation of `hl.Bytes` : a raw native address.

	It can point to native memory (allocated by the addon, or mapped GPU memory) or to
	the data of a JS ArrayBuffer : V8 never moves a backing store, so its address stays
	valid as long as the buffer is alive. Electron does not allow JS to see native memory
	directly, so every access goes through the addon (one call per blit).
**/
abstract Bytes(Float) {

	/** native allocation. Like small GC allocations in HL, it is never freed. **/
	public inline function new( size : Int ) {
		this = N.mem_alloc(size);
	}

	public inline function offset( delta : Int ) : Bytes {
		return cast (this + delta);
	}

	public inline function subtract( other : Bytes ) : Int {
		return Std.int(this - (cast other : Float));
	}

	public inline function blit( pos : Int, src : Bytes, srcPos : Int, len : Int ) : Void {
		N.mem_copy(this + pos, (cast src : Float) + srcPos, len);
	}

	public inline function fill( pos : Int, size : Int, v : Int ) : Void {
		N.mem_fill(this + pos, v, size);
	}

	@:arrayAccess public inline function getUI8( pos : Int ) : Int {
		return N.mem_get_ui8(this + pos);
	}

	@:arrayAccess public inline function setUI8( pos : Int, value : Int ) : Int {
		N.mem_set_ui8(this + pos, value);
		return value;
	}

	public inline function getUI16( pos : Int ) : Int {
		return N.mem_get_ui16(this + pos);
	}

	public inline function setUI16( pos : Int, v : Int ) : Void {
		N.mem_set_ui16(this + pos, v);
	}

	public inline function getI32( pos : Int ) : Int {
		return N.mem_get_i32(this + pos);
	}

	public inline function setI32( pos : Int, value : Int ) : Void {
		N.mem_set_i32(this + pos, value);
	}

	public inline function getF32( pos : Int ) : Single {
		return N.mem_get_f32(this + pos);
	}

	public inline function setF32( pos : Int, value : Single ) : Void {
		N.mem_set_f32(this + pos, value);
	}

	public inline function getF64( pos : Int ) : Float {
		return N.mem_get_f64(this + pos);
	}

	public inline function setF64( pos : Int, value : Float ) : Void {
		N.mem_set_f64(this + pos, value);
	}

	public inline function address() : haxe.Int64 {
		return I64.toInt64(cast this);
	}

	public static inline function fromAddress( h : haxe.Int64 ) : Bytes {
		return cast I64.ofInt64(h);
	}

	/** copies `size` bytes into a new haxe.io.Bytes (JS can't share native memory) **/
	public function sub( pos : Int, size : Int ) : haxe.io.Bytes {
		var out = haxe.io.Bytes.alloc(size);
		N.mem_copy(N.mem_address(@:privateAccess out.b), this + pos, size);
		return out;
	}

	public inline function toBytes( len : Int ) : haxe.io.Bytes {
		return sub(0, len);
	}

	@:from public static inline function fromBytes( bytes : haxe.io.Bytes ) : Bytes {
		return bytes == null ? null : convert(bytes);
	}

	static var lastConverted : haxe.io.Bytes;
	static var lastAddress : Float = 0;

	static function convert( bytes : haxe.io.Bytes ) : Bytes {
		var a = N.mem_address(@:privateAccess bytes.b);
		lastConverted = bytes;
		lastAddress = a;
		return cast a;
	}

	/**
		The haxe.io.Bytes the given address was just converted from, if any. Used by the
		struct fields to keep the JS object alive, like the HL GC does.
	**/
	@:noCompletion public static inline function convertedFrom( b : Bytes ) : haxe.io.Bytes {
		return b != null && (cast b : Float) == lastAddress ? lastConverted : null;
	}

	/**
		Address of the data of an array of basic types, like `hl.Bytes.getArray`.
		Typed arrays are not copied; plain JS arrays (16 bits indexes) are copied into a
		temporary buffer, valid until the next call.
	**/
	public static macro function getArray( a : haxe.macro.Expr ) : haxe.macro.Expr {
		return hlemu.Macros.getArray(a);
	}

	// ---- JS helpers (not in hl.Bytes)

	/** null-terminated UTF-16 copy of `s`, in native memory (to free with `free`) **/
	public static function ofUcs2( s : String ) : Bytes {
		if( s == null ) return null;
		var b = new Bytes((s.length + 1) << 1);
		for( i in 0...s.length )
			b.setUI16(i << 1, StringTools.fastCodeAt(s, i));
		b.setUI16(s.length << 1, 0);
		return b;
	}

	/** reads a null-terminated UTF-16 string **/
	public function toUcs2() : String {
		var len = N.mem_ustrlen(this);
		var buf = new StringBuf();
		for( i in 0...len )
			buf.addChar(getUI16(i << 1));
		return buf.toString();
	}

	public inline function free() : Void {
		N.mem_free(this);
	}

	public inline function isNull() : Bool {
		return this == null || this == 0;
	}

	@:noCompletion public static var tmpArray : Dynamic;
}

#else

// the type is loaded in the macro context to run getArray
abstract Bytes(Float) {
	public static macro function getArray( a : haxe.macro.Expr ) : haxe.macro.Expr {
		return hlemu.Macros.getArray(a);
	}
}

#end
