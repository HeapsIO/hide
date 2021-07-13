package hide.comp.cdb;

typedef DataProps = {
	var file : String;
	var path : String;
	var index : Int;
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
			reload();
			Editor.refreshAll(true);
		},0);
	}

	static function reload() {
		for( s in base.sheets )
			if( s.props.dataFiles != null ) @:privateAccess {
				s.sheet.lines = null;
				s.sheet.linesData = null;
			}
		load();
	}

	static function loadSheet( sheet : cdb.Sheet ) {
		var ide = Ide.inst;
		var lines : Array<Dynamic> = [];
		var linesData : Array<DataProps> = [];
		var separators = [];
		var separatorTitles = [];
		var sheetName = getTypeName(sheet);
		@:privateAccess {
			sheet.sheet.lines = lines;
			sheet.sheet.linesData = linesData;
			sheet.sheet.separators = separators;
			sheet.props.separatorTitles = separatorTitles;
		}
		function loadFile( file : String ) {
			var needSep = true;
			var levelID = file.split("/").pop().split(".").shift();
			levelID = levelID.charAt(0).toUpperCase()+levelID.substr(1);
			function loadRec( p : hrt.prefab.Prefab, parent : hrt.prefab.Prefab ) {
				if( p.getCdbType() == sheetName ) {
					var dprops : DataProps = {
						file : file,
						path : p.getAbsPath(),
						index : 0,
						origin : haxe.Json.stringify(p.props),
					};
					if( parent != null ) {
						for( c in parent.children ) {
							if( c == p ) break;
							if( c.name == p.name ) dprops.index++;
						}
					}
					if( needSep ) {
						separators.push(lines.length);
						separatorTitles.push(file);
						needSep = false;
					}
					if( sheet.idCol != null && Reflect.field(p.props,sheet.idCol.name) == "" )
						Reflect.setField(p.props,sheet.idCol.name,levelID+"_"+p.name+(dprops.index == 0 ? "" : ""+dprops.index));
					linesData.push(dprops);
					lines.push(p.props);
				}
				for( c in p ) loadRec(c,p);
			}
			var p = ide.loadPrefab(file);
			loadRec(p,null);
			if( !watching.exists(file) ) {
				watching.set(file, true);
				ide.fileWatcher.register(file, onFileChanged);
			}
		}

		function gatherRec( basePath : Array<String>, curPath : Array<String>, i : Int ) {
			var part = basePath[i++];
			if( part == null ) {
				var file = curPath.join("/");
				if( sys.FileSystem.exists(ide.getPath(file)) ) loadFile(file);
				return;
			}
			if( part.indexOf("*") < 0 ) {
				curPath.push(part);
				gatherRec(basePath,curPath,i);
				curPath.pop();
			} else {
				var path = curPath.join("/");
				var dir = ide.getPath(path);
				if( !sys.FileSystem.isDirectory(dir) )
					return;
				if( !watching.exists(path) ) {
					watching.set(path, true);
					ide.fileWatcher.register(path, onFileChanged, true);
				}
				var reg = new EReg("^"+part.split(".").join("\\.").split("*").join(".*")+"$","");
				for( f in sys.FileSystem.readDirectory(dir) ) {
					if( !reg.match(f) ) {
						if( sys.FileSystem.isDirectory(dir+"/"+f) ) {
							curPath.push(f);
							gatherRec(basePath,curPath,i-1);
							curPath.pop();
						}
						continue;
					}
					curPath.push(f);
					gatherRec(basePath,curPath,i);
					curPath.pop();
				}
			}
		}

		for( dir in sheet.props.dataFiles.split(";") )
			gatherRec(dir.split("/"),[],0);
	}

	public static function save( ?onSaveBase, ?force, ?prevSheetNames : Map<String,String> ) {
		var ide = Ide.inst;
		var temp = [];
		var titles = [];
		var prefabs = new Map();
		for( s in base.sheets ) {
			for( c in s.columns ) {
				var p : Editor.EditorColumnProps = c.editor;
				if( p != null && p.ignoreExport ) {
					var prev = [for( o in s.lines ) Reflect.field(o, c.name)];
					for( o in s.lines ) Reflect.deleteField(o, c.name);
					temp.push(function() {
						for( i in 0...prev.length ) {
							var v = prev[i];
							if( v == null ) continue;
							Reflect.setField(s.lines[i], c.name, v);
						}
					});
				}
			}
			if( s.props.dataFiles != null ) {
				var sheet = @:privateAccess s.sheet;
				var sheetName = getTypeName(s);
				var prevName = sheetName;
				if( prevSheetNames != null && prevSheetNames.exists(sheetName) )
					prevName = prevSheetNames.get(sheetName);
				var ldata = sheet.linesData;
				for( i in 0...s.lines.length ) {
					var o = s.lines[i];
					var p : DataProps = sheet.linesData[i];
					var str = haxe.Json.stringify(o);
					if( str != p.origin || force ) {
						p.origin = str;
						var pf : hrt.prefab.Prefab = prefabs.get(p.file);
						if( pf == null ) {
							pf = ide.loadPrefab(p.file);
							prefabs.set(p.file, pf);
						}
						var all = pf.getPrefabsByPath(p.path);
						var inst : hrt.prefab.Prefab = all[p.index];
						if( inst == null || inst.getCdbType() != prevName )
							ide.error("Can't save prefab data "+p.path);
						else {
							if( prevName != sheetName ) Reflect.setField(o,"$cdbtype", sheetName);
							inst.props = o;
						}
					}
				}
				var old = Reflect.copy(sheet);
				var oldTitles = sheet.props.separatorTitles;
				temp.push(function() {
					sheet.lines = old.lines;
					sheet.linesData = old.linesData;
					sheet.separators = old.separators;
					sheet.props.separatorTitles = oldTitles;
				});
				Reflect.deleteField(sheet,"lines");
				Reflect.deleteField(sheet,"linesData");
				sheet.separators = [];
				Reflect.deleteField(sheet.props,"separatorTitles");
			}
		}
		for( file => pf in prefabs ) {
			skip++;
			sys.io.File.saveContent(ide.getPath(file), ide.toJSON(pf.saveData()));
		}
		if( onSaveBase != null )
			onSaveBase();
		temp.reverse();
		for( t in temp )
			t();
	}

	// ---- TYPES Instances API -----

	public static function getTypeName( sheet : cdb.Sheet ) {
		return sheet.name.split("@").pop();
	}

	public static function getAvailableTypes() {
		var sheets = [];
		var ide = Ide.inst;
		var levelSheet = ide.database.getSheet(ide.currentConfig.get("sceneeditor.cdbLevel", "level"));
		for( s in ide.database.sheets )
			if( s.props.dataFiles != null )
				sheets.push(s);
		if(levelSheet != null) {
			for(c in levelSheet.columns)
				if( c.type == TList )
					sheets.push(levelSheet.getSub(c));
		}
		return sheets;
	}

	public static function resolveType( name : String ) {
		if( name == null )
			return null;
		for( s in getAvailableTypes() )
			if( getTypeName(s) == name )
				return s;
		return null;
	}


}
