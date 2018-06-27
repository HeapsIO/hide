package hide.prefab;

class Reference extends Prefab {

	public var refpath : String;
	var ref: Prefab = null;

	public function new(?parent) {
		super(parent);
		type = "reference";
	}

	override function save() {
		return {
			// Recalc abs path if ref has been resolved to supprot renaming
			refpath: ref != null ? ref.getAbsPath() : refpath
		};
	}

	override function load( o : Dynamic ) {
		refpath = o.refpath;
	}

	function resolveRef() {
		if(ref != null)
			return ref;
		if(refpath == null)
			return null;	
		var lib = getParent(hide.prefab.Library);
		if(lib == null)
			return null;
		return lib.getOpt(Prefab, refpath);
	}

	override function makeInstance(ctx: Context) : Context {
		var p = resolveRef();
		if(p == null)
			return ctx;

		ctx = ctx.clone(this);
		ctx.isRef = true;
		return p.makeInstance(ctx);
	}

	override function getHideProps() {
		return { icon : "share", name : "Reference", fileSource : null };
	}

	static var _ = Library.register("reference", Reference);
}