package hide.prefab.l3d;
using Lambda;

class Instance extends Object3D {

	public var props : Dynamic;

	public function new(?parent) {
		super(parent);
		type = "instance";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		props = obj.props;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.props = props;
		return obj;
	}

	override function makeInstance(ctx:Context):Context {
		#if editor
		var ctx = super.makeInstance(ctx);
		var parentLayer = getParent(Layer);
		if(parentLayer != null) {
			var sheet = parentLayer.getCdbModel();			
			if(sheet != null) {
				var refCol = findRefColumn(sheet);
				if(refCol != null) {
					var refId = Reflect.getProperty(props, refCol.col.name);
					if(refId != null) {
						var refSheet = sheet.base.getSheet(refCol.sheet);
						if(refSheet != null) {
							var idx = refSheet.index.get(refId);
							var modelPath = findModelPath(refSheet, idx.obj);
							if(modelPath != null) {
								try {
									var obj = ctx.loadModel(modelPath);
									obj.name = name;
									applyPos(obj);
									ctx.local3d.addChild(obj);
									ctx.local3d = obj;
								} catch( e : hxd.res.NotFound ) {
									ctx.onError(e);
								}
							}
							else {
								var tile = findTile(refSheet, idx.obj).center();
								var objFollow = new h2d.ObjectFollower(ctx.local3d, ctx.shared.root2d);
								var bmp = new h2d.Bitmap(tile, objFollow);
								ctx.local2d = objFollow;
								var obj = new h3d.scene.Object(ctx.local3d);
								var prim = h3d.prim.Cube.defaultUnitCube();
								var mesh = new h3d.scene.Mesh(prim, obj);
								mesh.setPos(-0.25, -0.25, -0.25);
								mesh.scale(0.5);
								var mat = mesh.material;
								mat.color.setColor(parentLayer.color);
								mat.shadows = false;
							}
						}
					}
				}
			}
		}
		#end
		return ctx;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Instance">
			</div>
		'),this);

		var parentLayer = getParent(Layer);
		if(parentLayer == null) return;

		var sheet = parentLayer.getCdbModel();
		if(sheet == null) return;
		ctx.properties.addProps([for(c in sheet.columns) {t: getPropType(c), name: c.name}], this.props);
		#end
	}

	function getPropType(col : cdb.Data.Column) : hide.comp.PropsEditor.PropType {
		return switch(col.type) {
			// case TString: TODO
			case TBool: PBool;
			case TInt: PInt();
			case TFloat: PFloat();
			default: PUnsupported(col.name);
		}
	}

	override function getHideProps() {
		return { icon : "circle", name : "Instance", fileSource : null };
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
			var model = hxd.Res.load(path).toModel();
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
					if(sub != null) {
						var lines = sub.getLines();
						if(lines.length > 0) {
							var col = sub.columns.find(sc -> sc.type == cdb.Data.ColumnType.TFile);
							if(col != null) {
								path = filter(Reflect.getProperty(lines[0], col.name));
								if(path != null) break;
							}
						}
					}
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
		return hxd.Res.load(p.file).toTile().sub(p.x * p.size, p.y * p.size, w, h);
	}

	static var _ = Library.register("instance", Instance);
}