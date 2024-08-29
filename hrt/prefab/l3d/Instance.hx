package hrt.prefab.l3d;
using Lambda;

class Instance extends Object3D {

	var instance : Prefab;
	var model : h3d.scene.Object;
	var icon : h2d.Object;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
		props = {};
	}

	#if editor
	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {

		var kind = getRefSheet(this);
		var unknown = kind == null || kind.idx == null;

		var modelPath = unknown ? null : findModelPath(kind.sheet, kind.idx.obj);
		if(modelPath != null) {
			try {
				if(hrt.prefab.Prefab.getPrefabType(modelPath) != null) {
					var ref = hxd.res.Loader.currentInstance.load(modelPath).to(hrt.prefab.Resource).load();
					if(ref != null) {
						var sh = new hrt.prefab.ContextShared(findFirstLocal2d(), parent3d);
						sh.currentPath = source;
						sh.parentPrefab = this;
						sh.customMake = this.shared.customMake;
						#if editor
						ref.setEditor(shared.editor, shared.scene);
						#end

						instance = ref.make(sh);
						return instance.findFirstLocal3d();
					}
				}
				else {
					model = shared.loadModel(modelPath);
					model.name = name;
					return model;
				}
			} catch( e : hxd.res.NotFound ) {
				shared.onError(e);
			}
		}
        return super.makeObject(parent3d);
	}

	override function makeInteractive():hxd.SceneEvents.Interactive {
		var int = super.makeInteractive();
		if( int == null ) {
			// no meshes ? do we have an icon instead...
			var follow = Std.downcast(findFirstLocal2d(), h2d.ObjectFollower);
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

	// ---- statics

	public static function getRefSheet(p: Prefab) {
		var name = p.getCdbType();
		if( name == null )
			return null;
		var sheet = hide.comp.cdb.DataFiles.resolveType(name);
		if( sheet == null )
			return null;
		var refCols = findRefColumns(sheet);
		if(refCols == null)
			return null;
		var refId : Dynamic = p.props;
		for( c in refCols.cols )
			refId = Reflect.field(refId, c.name);
		if(refId == null)
			return null;
		var refSheet = sheet.base.getSheet(refCols.sheet);
		if(refSheet == null)
			return null;
		return {sheet: refSheet, idx: refSheet.index.get(refId)};
	}

	public static function findRefColumns(sheet : cdb.Sheet) {
		for(col in sheet.columns) {
			switch(col.type) {
				case TRef(sheet):
					return {cols: [col], sheet: sheet};
				default:
			}
		}
		for(col in sheet.columns) {
			switch(col.type) {
			case TProperties:
				var sub = sheet.getSub(col);
				for( col2 in sub.columns )
					switch( col2.type ) {
					case TRef(sheet2):
						return {cols: [col,col2], sheet: sheet2};
					default:
					}
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
				if(StringTools.endsWith(lower, ".fbx") || hrt.prefab.Prefab.getPrefabType(lower) != null)
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

	override function editorRemoveInstance() : Void {
		if (icon != null) {
			icon.remove();
		}
		super.editorRemoveInstance();
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "circle", name : "Instance" };
	}
	#end

	static var _ = Prefab.register("instance", Instance);
}