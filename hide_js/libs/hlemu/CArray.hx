package hlemu;


/**
	JS emulation of `hl.CArray` : structs stored contiguously in one ArrayBuffer.
	The element views are created on demand and cached.
**/
abstract CArray<T>(CArrayData) {

	@:arrayAccess inline function get( index : Int ) : T {
		var it = this.items[index];
		if( it == null ) {
			var o = index * this.stride;
			it = this.items[index] = this.cl.__view(this.view, o, this.__a + o);
		}
		return it;
	}

	public static function alloc<T>( cl : Class<T>, size : Int ) : CArray<T> {
		var d = new CArrayData();
		d.cl = cl;
		d.stride = (cast cl).__SIZE;
		d.count = size;
		var buf = new js.lib.ArrayBuffer(d.stride * size > 0 ? d.stride * size : 1);
		d.view = new js.lib.DataView(buf);
		d.__a = Native.mem_address(buf);
		d.items = [];
		return cast d;
	}

	public function toBytes( cl : Class<T>, count : Int ) : haxe.io.Bytes {
		if( this == null ) return null;
		return (cast this.__a : Bytes).sub(0, this.stride * count);
	}

	public inline function blit( cl : Class<T>, pos : Int, src : CArray<T>, srcPos : Int, srcLen : Int ) : Void {
		var s : CArrayData = cast src;
		Native.mem_copy(this.__a + pos * this.stride, s.__a + srcPos * this.stride, srcLen * this.stride);
	}
}
