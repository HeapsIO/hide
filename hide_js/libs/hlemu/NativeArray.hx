package hlemu;

/**
	JS emulation of `hl.NativeArray` : a plain JS array. Native bindings taking a
	NativeArray convert it to an HL varray in native memory.
**/
abstract NativeArray<T>(Array<T>) {
	public var length(get, never) : Int;

	public inline function new( length : Int ) {
		this = [];
		if( length > 0 ) this[length - 1] = cast null;
	}

	inline function get_length() : Int {
		return this.length;
	}

	@:arrayAccess inline function get( pos : Int ) : T {
		return this[pos];
	}

	@:arrayAccess inline function set( pos : Int, value : T ) : T {
		return this[pos] = value;
	}

	public inline function sub( pos : Int, len : Int ) : NativeArray<T> {
		return cast this.slice(pos, pos + len);
	}

	public inline function blit( pos : Int, src : NativeArray<T>, srcPos : Int, srcLen : Int ) : Void {
		var s : Array<T> = cast src;
		if( s == this && srcPos < pos ) {
			var i = srcLen;
			while( i-- > 0 ) this[pos + i] = s[srcPos + i];
		} else
			for( i in 0...srcLen ) this[pos + i] = s[srcPos + i];
	}

	public inline function toArray() : Array<T> {
		return this;
	}

	public function iterator() {
		return this.iterator();
	}
}
