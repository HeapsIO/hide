package hrt.prefab;

class Reference extends Object3D {

	@:s var editMode : Bool = false;
	public var ref: Prefab = null;

	public function new(?parent) {
		super(parent);
		type = "reference";
	}

	override function load(v:Dynamic) {
		super.load(v);
		// backward compatibility
		var old : String = v.refpath;
		if( old != null ) {
			source = old.charCodeAt(0) == "/".code ? old.substr(1) : "/"+old;
		}
	}

	public function isFile() {
		return source != null && source.charCodeAt(0) != "/".code;
	}

	override function save() {
		// Recalc abs path if ref has been resolved to supprot renaming
		if( ref != null && !isFile() )
			source = "/"+ref.getAbsPath();
		var obj : Dynamic = super.save();
		#if editor
		if( editMode && isFile() && ref != null )
			hide.Ide.inst.savePrefab(source, ref);
		#end
		return obj;
	}

	public function resolveRef(shared : hrt.prefab.ContextShared) {
		if(ref != null)
			return ref;
		if(source == null)
			return null;
		if(isFile()) {
			if(shared == null) { // Allow resolving ref in Hide prefore makeInstance
				#if editor
				ref = hide.Ide.inst.loadPrefab(source, null, true);
				#else
				return null;
				#end
			}
			else
				ref = shared.loadPrefab(source);
			return ref;
		}
		else {
			var lib = getParent(hrt.prefab.Library);
			if(lib == null)
				return null;
			var all = lib.getAll(Prefab);
			var path = source.substr(1);
			for(p in all) {
				if(!Std.is(p, Reference) && p.getAbsPath() == path) {
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
		var parentCtx = parent == null ? null : ctx.shared.contexts.get(parent);
		if(parentCtx == null || parentCtx.local3d != ctx.local3d) {
			// Only apply reference Object3D properties (pos, scale...) to own local3D
			// Not all refs will create their own scene object
			super.updateInstance(ctx, propName);
		}
	}

	override function find<T>( f : Prefab -> Null<T>, ?followRefs : Bool ) : T {
		if( followRefs && ref != null ) {
			var v = ref.find(f, followRefs);
			if( v != null ) return v;
		}
		return super.find(f, followRefs);
	}

	override function findAll<T>( f : Prefab -> Null<T>, ?followRefs : Bool, ?arr : Array<T> ) : Array<T> {
		if( followRefs && ref != null )
			arr = ref.findAll(f, followRefs, arr);
		return super.findAll(f, followRefs, arr);
	}

	override function getOpt<T:Prefab>( cl : Class<T>, ?name : String, ?followRefs ) : T {
		if( followRefs && ref != null ) {
			var v = ref.getOpt(cl, name, true);
			if( v != null )
				return v;
		}
		return super.getOpt(cl, name, followRefs);
	}

	override function makeInstance(ctx: Context) : Context {
		var p = resolveRef(ctx.shared);
		if(p == null)
			return ctx;

		if(isFile()) {
			ctx = super.makeInstance(ctx);
			var prevShared = ctx.shared;
			ctx.shared = ctx.shared.cloneRef(this, source);
			makeChildren(ctx, p);
			ctx.shared = prevShared;

			#if editor
			if (ctx.local2d == null) {
				var path = hide.Ide.inst.appPath + "/res/icons/fileRef.png";
				var data = sys.io.File.getBytes(path);
				var tile = hxd.res.Any.fromBytes(path, data).toTile().center();
				var objFollow = new h2d.ObjectFollower(ctx.local3d, ctx.shared.root2d);
				objFollow.followVisibility = true;
				var bmp = new h2d.Bitmap(tile, objFollow);
				ctx.local2d = objFollow;
			}
			#end

		}
		else {
			ctx = ctx.clone(this);
			ctx.isSceneReference = true;
			var refCtx = p.make(ctx); // no customMake here
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

	override function makeInteractive(ctx) {
		if( editMode )
			return null;
		return super.makeInteractive(ctx);
	}

	override function edit( ctx : EditContext ) {
		var element = new hide.Element('
			<div class="group" name="Reference">
			<dl>
				<dt>Reference</dt><dd><input type="text" field="source"/></dd>
				<dt>Edit</dt><dd><input type="checkbox" field="editMode"/></dd>
			</dl>
			</div>');

		function updateProps() {
			var input = element.find("input");
			var found = resolveRef(ctx.rootContext.shared) != null;
			input.toggleClass("error", !found);
		}
		updateProps();

		element.find("input").contextmenu((e) -> {
			e.preventDefault();
			if( isFile() ) {
				new hide.comp.ContextMenu([
					{ label : "Open", click : () -> ctx.ide.openFile(ctx.ide.getPath(source)) },
				]);
			}
		});

		var props = ctx.properties.add(element, this, function(pname) {
			ctx.onChange(this, pname);
			if(pname == "source" || pname=="editMode") {
				ref = null;
				updateProps();
				if(!ctx.properties.isTempChange)
					ctx.rebuildPrefab(this);
			}
		});

		super.edit(ctx);
	}

	override function getHideProps() : HideProps {
		return { icon : "share", name : "Reference" };
	}
	#end

	static var _ = Library.register("reference", Reference);
}