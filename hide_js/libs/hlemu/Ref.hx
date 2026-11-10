package hlemu;

/**
	JS emulation of `hl.Ref`. JS can't take the address of a local variable: native
	bindings taking a Ref are generated as macros that write the result back to the
	argument (see hlemu.NativeBind). This box is only used when a Ref is stored.
**/
class Ref<T> {
	var v : T;
	public function new( v : T ) {
		this.v = v;
	}
	public inline function get() : T {
		return v;
	}
	public inline function set( v : T ) : Void {
		this.v = v;
	}
}
