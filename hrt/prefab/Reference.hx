package hrt.prefab;

class Reference extends Object3D {

	public var refpath : String;
	var ref: Prefab = null;

	public function new(?parent) {
		super(parent);
		type = "reference";
	}

	public function isFile() {
		// TODO: Use source instead?
		return refpath != null && refpath.charAt(0) == "/";
	}

	override function save() {
		var obj : Dynamic = super.save();
		// Recalc abs path if ref has been resolved to supprot renaming
		obj.refpath = ref != null && !isFile() ? ref.getAbsPath() : refpath;
		return obj;
	}

	override function load( o : Dynamic ) {
		super.load(o);
		refpath = o.refpath;
	}

	public function resolveRef(shared : hrt.prefab.ContextShared) {
		if(ref != null)
			return ref;
		if(refpath == null)
			return null;
		if(isFile()) {
			if(shared == null) { // Allow resolving ref in Hide prefore makeInstance
				#if editor
				ref = hide.Ide.inst.loadPrefab(refpath.substr(1));
				#else
				return null;
				#end
			}
			else
				ref = shared.loadPrefab(refpath.substr(1));
			return ref;
		}
		else {
			var lib = getParent(hrt.prefab.Library);
			if(lib == null)
				return null;
			var all = lib.getAll(Prefab);
			for(p in all) {
				if(!Std.is(p, Reference) && p.getAbsPath() == refpath) {
					ref = p;
					return ref;
				}
			}
		}
		return null;
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		var p = resolveRef(ctx.shared);
		if(p == null)
			return;
		var parentCtx = ctx.shared.contexts.get(parent);
		if(parentCtx == null || parentCtx.local3d != ctx.local3d) {
			// Only apply reference Object3D properties (pos, scale...) to own local3D
			// Not all refs will create their own scene object
			super.updateInstance(ctx, propName);
		}
	}

	override function makeInstance(ctx: Context) : Context {
		var p = resolveRef(ctx.shared);
		if(p == null)
			return ctx;

		if(isFile()) {
			ctx = super.makeInstance(ctx);
			ctx.isRef = true;
			p.make(ctx);

			#if editor
			var path = hide.Ide.inst.appPath + "/res/icons/fileRef.png";
			var data = sys.io.File.getBytes(path);
			var tile = hxd.res.Any.fromBytes(path, data).toTile().center();
			var objFollow = new h2d.ObjectFollower(ctx.local3d, ctx.shared.root2d);
			objFollow.followVisibility = true;
			var bmp = new h2d.Bitmap(tile, objFollow);
			ctx.local2d = objFollow;
			#end

		}
		else {
			ctx = ctx.clone(this);
			ctx.isRef = true;
			var refCtx = p.make(ctx);
			ctx.local3d = refCtx.local3d;
			updateInstance(ctx);
		}

		return ctx;
	}

	override function removeInstance(ctx:Context):Bool {
		if(!super.removeInstance(ctx))
			return false;
		if(ctx.local2d != null)
			ctx.local2d.remove();
		return true;
	}

	override function to<T:Prefab>( c : Class<T> ) : Null<T> {
		var base = super.to(c);
		if(base != null)
			return base;
		var p = resolveRef(null);
		if(p == null) return null;
		return Std.downcast(p, c);
	}


	#if editor


	override function edit( ctx : EditContext ) {
		var element = new hide.Element('
			<div class="group" name="Reference">
			<dl>
				<dt>Reference</dt><dd><input type="text" field="refpath"/></dd>
			</dl>
			</div>');

		function updateProps() {
			var input = element.find("input");
			var found = resolveRef(ctx.rootContext.shared) != null;
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

		var parentCtx = ctx.getContext(parent);
		var selfCtx = ctx.getContext(this);
		var p = resolveRef(ctx.rootContext.shared);
		if(selfCtx != null && parentCtx != null && parentCtx.local3d != selfCtx.local3d) {
			super.edit(ctx);
		}
	}

	override function getHideProps() : HideProps {
		return { icon : "share", name : "Reference" };
	}
	#end

	static var _ = Library.register("reference", Reference);
}