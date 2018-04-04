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
		var ctx = super.makeInstance(ctx);
		#if editor
		var parentLayer = getParentLayer();
		if(parentLayer != null) {
			var sheet = parentLayer.getCdbModel();			
			if(sheet != null) {
				var refCol = findRefColumn(sheet);
				if(refCol != null) {
					var refId = Reflect.getProperty(props, refCol.col.name);
					if(refId != null) {
						var refSheet = hide.ui.Ide.inst.database.getSheet(refCol.sheet);
						if(refSheet != null) {
							var idx = refSheet.index.get(refId);
							var tile = findTile(refSheet, idx.obj).center();
							var objFollow = new h2d.ObjectFollower(ctx.local3d, ctx.shared.root2d);
							var bmp = new h2d.Bitmap(tile, objFollow);
							ctx.local2d = objFollow;
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

		var parentLayer = getParentLayer();
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

	function getParentLayer() {
		var p = parent;
		while(p != null) {
			var layer = p.to(hide.prefab.l3d.Layer);
			if(layer != null) return layer;
			p = p.parent;			
		}
		return null;
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

	public static function findTile(refSheet : cdb.Sheet, obj : Dynamic) {
		var idCol = refSheet.columns.find(c -> c.type == cdb.Data.ColumnType.TTilePos);
		if(idCol != null) {
			var tile: cdb.Types.TilePos = Reflect.getProperty(obj, idCol.name);
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