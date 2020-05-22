package hide.comp.cdb;

typedef DataProps = {
	var file : String;
	var path : String;
	var origin : String;
}

class DataFiles {

	static var changed : Bool;
	static var skip : Int = 0;
	static var watching : Map<String, Bool> = new Map();
	static var base(get,never) : cdb.Database;

	static function get_base() return Ide.inst.database;

	public static function load() {
		for( sheet in base.sheets )
			if( sheet.props.dataFiles != null && sheet.lines == null )
				loadSheet(sheet);
	}

	static function onFileChanged() {
		if( skip > 0 ) {
			skip--;
			return;
		}
		changed = true;
		haxe.Timer.delay(function() {
			if( !changed ) return;
			changed = false;
			for( s in base.sheets )
				if( s.props.dataFiles != null ) @:privateAccess {
					s.sheet.lines = null;
					s.sheet.linesData = null;
				}
			load();
			Editor.refreshAll(true);
		},0);
	}

	static function loadSheet( sheet : cdb.Sheet ) {
		var ide = Ide.inst;
		var lines : Array<Dynamic> = [];
		var linesData : Array<DataProps> = [];
		@:privateAccess {
			sheet.sheet.lines = lines;
			sheet.sheet.linesData = linesData;
		}
		if( !sys.FileSystem.exists(ide.getPath(sheet.props.dataFiles)) )
			return;
		function loadFile( file : String ) {
			function loadRec( p : hrt.prefab.Prefab ) {
				if( p.getCdbModel() == sheet ) {
					var dprops : DataProps = {
						file : file,
						path : p.getAbsPath(),
						origin : haxe.Json.stringify(p.props),
					};
					linesData.push(dprops);
					lines.push(p.props);
				}
				for( p in p ) loadRec(p);
			}
			var p = ide.loadPrefab(file);
			loadRec(p);
			if( !watching.exists(file) ) {
				watching.set(file, true);
				ide.fileWatcher.register(file, onFileChanged);
			}
		}
		loadFile(sheet.props.dataFiles);
	}

	public static function save( ?onSaveBase, ?force ) {
		var ide = Ide.inst;
		var temp = [];
		var prefabs = new Map();
		for( s in base.sheets )
			if( s.props.dataFiles != null ) {
				var ldata = @:privateAccess s.sheet.linesData;
				temp.push({ lines : s.lines, data : ldata });
				for( i in 0...s.lines.length ) {
					var o = s.lines[i];
					var p : DataProps = ldata[i];
					var str = haxe.Json.stringify(o);
					if( str != p.origin || force ) {
						p.origin = str;
						var pf : hrt.prefab.Prefab = prefabs.get(p.file);
						if( pf == null ) {
							pf = ide.loadPrefab(p.file);
							prefabs.set(p.file, pf);
						}
						var inst : hrt.prefab.Prefab = pf.getPrefabByPath(p.path);
						if( inst == null || inst.getCdbModel() != s )
							ide.error("Can't save prefab data "+p.path);
						else
							inst.props = o;
					}
				}
				@:privateAccess {
					Reflect.deleteField(s.sheet,"lines");
					Reflect.deleteField(s.sheet,"linesData");
				}
			}
		for( file => pf in prefabs ) {
			skip++;
			sys.io.File.saveContent(ide.getPath(file), ide.toJSON(pf.saveData()));
		}
		if( onSaveBase != null )
			onSaveBase();
		for( s in base.sheets ) {
			if( s.props.dataFiles != null ) {
				var d = temp.shift();
				@:privateAccess {
					s.sheet.lines = d.lines;
					s.sheet.linesData = d.data;
				}
			}
		}
	}

}
