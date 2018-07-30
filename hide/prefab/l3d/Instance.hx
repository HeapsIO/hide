package hide.prefab.l3d;
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
		var modelPath = findModelPath(kind.sheet, kind.idx.obj);
		if(modelPath != null) {
			try {
				var obj = ctx.loadModel(modelPath);
				obj.name = name;
				ctx.local3d.addChild(obj);
			} catch( e : hxd.res.NotFound ) {
				ctx.shared.onError(e);
			}
		}
		else {
			var tile = findTile(kind.sheet, kind.idx.obj).center();
			var objFollow = new h2d.ObjectFollower(ctx.local3d, ctx.shared.root2d);
			var bmp = new h2d.Bitmap(tile, objFollow);
			ctx.local2d = objFollow;
			var mesh = new h3d.scene.Mesh(h3d.prim.Cube.defaultUnitCube(), ctx.local3d);
			mesh.scale(0.5);
			var mat = mesh.material;
			mat.color.setColor(0xff00ff);
			mat.shadows = false;
		}
		#end
		return ctx;
	}

	#if editor

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		var sheet = getCdbModel();
		if( sheet == null ) return;
		//ctx.properties.addProps([for(c in sheet.columns) {t: getPropType(c), name: c.name}], this.props);
	}

	override function getHideProps() : HideProps {
		return { icon : "circle", name : "Instance", allowParent : function(p) return p.type == "layer" };
	}

	// Move to Prefab?
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

	static function findModelPath(refSheet : cdb.Sheet, obj : Dynamic) {
		function filter(f: String) {
			if(f != null) {
				var lower = f.toLowerCase();
				if(StringTools.endsWith(lower.toLowerCase(), ".fbx"))
					return f;
			}
			return null;
		}
		var col = refSheet.columns.find(c -> c.type == cdb.Data.ColumnType.TFile);
		var path = null;
		if(col != null) {
			path = filter(Reflect.getProperty(obj, col.name));
		}
		if(path == null) {
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
			}
		}
		return path;
	}

	static function findTile(refSheet : cdb.Sheet, obj : Dynamic) {
		var tileCol = refSheet.columns.find(c -> c.type == cdb.Data.ColumnType.TTilePos);
		if(tileCol != null) {
			var tile: cdb.Types.TilePos = Reflect.getProperty(obj, tileCol.name);
			if(tile != null)
				return makeTile(tile);
		}
		return h2d.Tile.fromColor(0xFF00FF, 16, 16, 0.8).sub(0, 0, 8, 8);
	}

	static function makeTile(p:cdb.Types.TilePos) : h2d.Tile {
		var w = (p.width == null ? 1 : p.width) * p.size;
		var h = (p.height == null ? 1 : p.height) * p.size;
		return hxd.res.Loader.currentInstance.load(p.file).toTile().sub(p.x * p.size, p.y * p.size, w, h);
	}
	#end

	static var _ = hxd.prefab.Library.register("instance", Instance);
}