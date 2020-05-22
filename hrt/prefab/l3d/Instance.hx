package hrt.prefab.l3d;
using Lambda;

class Instance extends Object3D {

	public function new(?parent) {
		super(parent);
		type = "instance";
		props = {};
	}

	override function makeInstance(ctx:Context):Context {
		#if editor
		var ctx = super.makeInstance(ctx);
		var kind = getCdbKind(this);
		var unknown = kind == null || kind.idx == null;

		var modelPath = unknown ? null : findModelPath(kind.sheet, kind.idx.obj);
		if(modelPath != null) {
			try {
				if(hrt.prefab.Library.getPrefabType(modelPath) != null) {
					var ref = ctx.shared.loadPrefab(modelPath);
					var ctx = ctx.clone(this);
					ctx.isRef = true;
					if(ref != null)
						ref.make(ctx);
				}
				else {
					var obj = ctx.loadModel(modelPath);
					obj.name = name;
					ctx.local3d.addChild(obj);
				}
			} catch( e : hxd.res.NotFound ) {
				ctx.shared.onError(e);
			}
		}
		else {
			var tile = unknown ? getDefaultTile().center() : findTile(kind.sheet, kind.idx.obj).center();
			var objFollow = new h2d.ObjectFollower(ctx.local3d, ctx.shared.root2d);
			objFollow.followVisibility = true;
			var bmp = new h2d.Bitmap(tile, objFollow);
			ctx.local2d = objFollow;
		}
		addRanges(ctx, true);
		#end
		return ctx;
	}

	#if editor

	public function addRanges( ctx : Context, init = false ) {
		if( !init ) {
			for( r in ctx.shared.getObjects(this,h3d.scene.Object) )
				if( r.name == "RANGE")
					r.remove();
		}
		// add ranges
		var shared = Std.downcast(ctx.shared, hide.prefab.ContextShared);
		if( shared != null && shared.editorDisplay ) {
			var sheet = getCdbModel();
			if( sheet != null ) {
				var ranges = Reflect.field(shared.scene.config.get("sceneeditor.ranges"), sheet.name);
				if( ranges != null ) {
					for( key in Reflect.fields(ranges) ) {
						var color = Std.parseInt(Reflect.field(ranges,key));
						var value : Dynamic = props;
						for( p in key.split(".") )
							value = Reflect.field(value, p);
						if( value != null ) {
							var mesh = new h3d.scene.Mesh(h3d.prim.Cylinder.defaultUnitCylinder(128), ctx.local3d);
							mesh.name = "RANGE";
							mesh.ignoreCollide = true;
							mesh.ignoreBounds = true;
							mesh.material.mainPass.culling = None;
							mesh.material.name = "RANGE";
							mesh.setScale(value * 2);
							mesh.scaleZ = 0.01;
							mesh.material.color.setColor(color|0xFF000000);
						}
					}
				}
			}
		}
	}

	override function setSelected(ctx:Context, b:Bool):Bool {
		var b = super.setSelected(ctx, b);
		for( m in ctx.shared.getMaterials(this) )
			if( m.name == "RANGE" )
				m.removePass(m.getPass("highlight"));
		return b;
	}

	override function makeInteractive(ctx:Context):hxd.SceneEvents.Interactive {
		var int = super.makeInteractive(ctx);
		if( int == null ) {
			// no meshes ? do we have an icon instead...
			var follow = Std.downcast(ctx.local2d, h2d.ObjectFollower);
			if( follow != null ) {
				var bmp = Std.downcast(follow.getChildAt(0), h2d.Bitmap);
				if( bmp != null ) {
					var i = new h2d.Interactive(bmp.tile.width, bmp.tile.height, bmp);
					i.x = bmp.tile.dx;
					i.y = bmp.tile.dy;
					int = i;
				}
			}
		}
		return int;
	}
	#end

	override function removeInstance(ctx:Context):Bool {
		if(!super.removeInstance(ctx))
			return false;
		if(ctx.local2d != null)
			ctx.local2d.remove();
		return true;
	}

	public static function getCdbKind(p: Prefab) {
		if(p.props == null)
			return null;
		var sheet = p.getCdbModel();
		if( sheet == null )
			return null;
		var refCol = findRefColumn(sheet);
		if(refCol == null)
			return null;
		var refId = Reflect.getProperty(p.props, refCol.col.name);
		if(refId == null)
			return null;
		var refSheet = sheet.base.getSheet(refCol.sheet);
		if(refSheet == null)
			return null;
		return {sheet: refSheet, idx: refSheet.index.get(refId)};
	}

	public static function findRefColumn(sheet : cdb.Sheet) {
		for(col in sheet.columns) {
			switch(col.type) {
				case TRef(sheet):
					return {col: col, sheet: sheet};
				default:
			}
		}
		return null;
	}

	public static function findIDColumn(refSheet : cdb.Sheet) {
		return refSheet.columns.find(c -> c.type == cdb.Data.ColumnType.TId);
	}

	public static function findModelPath(refSheet : cdb.Sheet, obj : Dynamic) {
		function filter(f: String) {
			if(f != null) {
				var lower = f.toLowerCase();
				if(StringTools.endsWith(lower, ".fbx") || hrt.prefab.Library.getPrefabType(lower) != null)
					return f;
			}
			return null;
		}
		var path = null;
		for(c in refSheet.columns) {
			if(c.type == cdb.Data.ColumnType.TList) {
				var sub = refSheet.getSub(c);
				if(sub == null) continue;
				var lines : Array<Dynamic> = Reflect.field(obj, c.name);
				if(lines == null || lines.length == 0) continue;
				// var lines = sub.getLines();
				// if(lines.length == 0) continue;
				var col = sub.columns.find(sc -> sc.type == cdb.Data.ColumnType.TFile);
				if(col == null) continue;
				path = filter(Reflect.getProperty(lines[0], col.name));
				if(path != null) break;
			}
			else if(c.type == cdb.Data.ColumnType.TFile) {
				path = filter(Reflect.getProperty(obj, c.name));
				if(path != null) break;
			}
		}
		return path;
	}

	#if editor

	override function getHideProps() : HideProps {
		return { icon : "circle", name : "Instance" };
	}

	static function getModel(refSheet : cdb.Sheet, obj : Dynamic) {
		var path = findModelPath(refSheet, obj);
		if(path == null)
			return null;
		try {
			var model = hxd.res.Loader.currentInstance.load(path).toModel();
			return model;
		} catch( e : hxd.res.NotFound ) {}
		return null;
	}

	static function findTile(refSheet : cdb.Sheet, obj : Dynamic) {
		var tileCol = refSheet.columns.find(c -> c.type == cdb.Data.ColumnType.TTilePos);
		if(tileCol != null) {
			var tile: cdb.Types.TilePos = Reflect.getProperty(obj, tileCol.name);
			if(tile != null)
				return makeTile(tile);
		}
		return getDefaultTile();
	}

	static function getDefaultTile() : h2d.Tile {
		var engine = h3d.Engine.getCurrent();
		var t = @:privateAccess engine.resCache.get(Instance);
		if( t == null ) {
			t = hxd.res.Any.fromBytes("",sys.io.File.getBytes(hide.Ide.inst.getPath("${HIDE}/res/icons/unknown.png"))).toTile();
			@:privateAccess engine.resCache.set(Instance, t);
		}
		return t.clone();
	}

	static function makeTile(p:cdb.Types.TilePos) : h2d.Tile {
		var w = (p.width == null ? 1 : p.width) * p.size;
		var h = (p.height == null ? 1 : p.height) * p.size;
		return hxd.res.Loader.currentInstance.load(p.file).toTile().sub(p.x * p.size, p.y * p.size, w, h);
	}
	#end

	static var _ = Library.register("instance", Instance);
}