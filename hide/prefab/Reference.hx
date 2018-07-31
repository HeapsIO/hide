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
		var lib = getParent(hxd.prefab.Library);
		if(lib == null)
			return null;
		var all = lib.getAll(Prefab);
		for(p in all) {
			if(!Std.is(p, Reference) && p.getAbsPath() == refpath) {
				ref = p;
				return ref;
			}
		}
		return null;
	}

	override function makeInstance(ctx: Context) : Context {
		var p = resolveRef();
		if(p == null)
			return ctx;

		ctx = ctx.clone(this);
		ctx.isRef = true;
		return p.makeInstance(ctx);
	}

	#if editor


	override function edit( ctx : EditContext ) {
		var element = new hide.Element('
			<dl>
				<dt>Reference</dt><dd><input type="text" field="refpath"/></dd>
			</dl>');

		function updateProps() {
			var input = element.find("input");
			var found = resolveRef() != null;
			input.toggleClass("error", !found);
		}
		updateProps();

		var props = ctx.properties.add(element, this, function(pname) {
			ctx.onChange(this, pname);
			if(pname == "refpath") {
				ref = null;
				updateProps();
				if(!ctx.properties.isTempChange)
					ctx.rebuildPrefab(this);
			}
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "share", name : "Reference" };
	}
	#end

	static var _ = hxd.prefab.Library.register("reference", Reference);
}