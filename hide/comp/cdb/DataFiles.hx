package hide.comp.cdb;

typedef DataProps = {
	var file : String;
	var path : String;
	var index : Int;
	var origin : String;
}

private typedef DataDef = {
	var name : String;
	var path : String;
	var subs : Array<DataDef>;
	var msubs : Map<String, DataDef>;
	var lines : Array<Dynamic>;
	var linesData: Array<DataProps>;
}

class DataFiles {

	static var changed : Bool;
	static var skip : Int = 0;
	static var watching : Map<String, Bool> = new Map();

	#if (editor || cdb_datafiles)
	static var base(get,never) : cdb.Database;
	static function get_base() return Ide.inst.database;
	#else
	public static var base : cdb.Database;
	#end

	public static function load() {
		for( sheet in base.sheets )
			if( sheet.props.dataFiles != null && sheet.lines == null )
				loadSheet(sheet);
	}

	#if (editor || cdb_datafiles)
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

	static function loadPrefab(file) {
		var p = Ide.inst.loadPrefab(file);
		if( !watching.exists(file) ) {
			watching.set(file, true);
			Ide.inst.fileWatcher.register(file, onFileChanged);
		}
		return p;
	}
	#else
	static function loadPrefab(file:String) {
		var path = getPath(file);
		var content = sys.io.File.getContent(path);
		var parsed = haxe.Json.parse(content);
		return hrt.prefab.Prefab.createFromDynamic(parsed);
	}
	#end

	static dynamic function getPath(file:String) {
		#if (editor || cdb_datafiles)
		return Ide.inst.getPath(file);
		#else
		return "res/"+file;
		#end
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
		var sheetName = getTypeName(sheet);
		var root : DataDef = {
			name : null,
			path : null,
			lines : null,
			linesData : null,
			subs : [],
			msubs : new Map(),
		};
		function loadFile( file : String ) {
			var content = null;
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
					if( sheet.idCol != null && Reflect.field(p.props,sheet.idCol.name) == "" )
						Reflect.setField(p.props,sheet.idCol.name,levelID+"_"+p.name+(dprops.index == 0 ? "" : ""+dprops.index));
					if( content == null ) {
						content = root;
						var path = [];
						for( p in file.split("/") ) {
							var n = content.msubs.get(p);
							path.push(p);
							if( n == null ) {
								n = { name : p.split(".").shift(), path : path.join("/"), lines : [], linesData: [], subs : [], msubs : new Map() };
								content.subs.push(n);
								content.msubs.set(p, n);
							}
							content = n;
						}
					}
					content.linesData.push(dprops);
					content.lines.push(p.props);
				}
				for( c in p ) loadRec(c,p);
			}
			var p = loadPrefab(file);
			loadRec(p,null);
		}

		function gatherRec( basePath : Array<String>, curPath : Array<String>, i : Int ) {
			var part = basePath[i++];
			if( part == null ) {
				var file = curPath.join("/");
				if( sys.FileSystem.exists(getPath(file)) ) loadFile(file);
				return;
			}
			if( part.indexOf("*") < 0 ) {
				curPath.push(part);
				gatherRec(basePath,curPath,i);
				curPath.pop();
			} else {
				var path = curPath.join("/");
				var dir = getPath(path);
				if( !sys.FileSystem.isDirectory(dir) )
					return;
				#if (editor || cdb_datafiles)
				if( !watching.exists(path) ) {
					watching.set(path, true);
					Ide.inst.fileWatcher.register(path, onFileChanged, true);
				}
				#end
				var reg = new EReg("^"+part.split(".").join("\\.").split("*").join(".*")+"$","");
				var subs = sys.FileSystem.readDirectory(dir);
				subs.sort(Reflect.compare);
				for( f in subs ) {
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


		var lines : Array<Dynamic> = [];
		var linesData : Array<DataProps> = [];
		var separators = [];
		@:privateAccess {
			sheet.sheet.lines = lines;
			sheet.sheet.linesData = linesData;
			sheet.sheet.separators = separators;
		}
		function browseRec( d : DataDef, level : Int ) {
			if( d.subs.length == 1 ) {
				// shortcut
				d.subs[0].name = d.name+" > "+d.subs[0].name;
				browseRec(d.subs[0], level);
				return;
			}
			separators.push({ title : d.name, level : level, index : lines.length, path : d.path });
			for( i in 0...d.lines.length ) {
				lines.push(d.lines[i]);
				linesData.push(d.linesData[i]);
			}
			d.subs.sort(function(d1,d2) return Reflect.compare(d1.name.toLowerCase(), d2.name.toLowerCase()));
			for( s in d.subs )
				browseRec(s, level + 1);
		}
		for( r in root.subs )
			browseRec(r, 0);
	}
	
	public static function getPrefabsByPath(prefab: hrt.prefab.Prefab, path : String ) : Array<hrt.prefab.Prefab> {
		function rec(prefab: hrt.prefab.Prefab, parts : Array<String>, index : Int, out : Array<hrt.prefab.Prefab> ) {
			var name = parts[index++];
			if( name == null ) {
				out.push(prefab);
				return;
			}
			var r = name.indexOf('*') < 0 ? null : new EReg("^"+name.split("*").join(".*")+"$","");
			for( c in prefab.children ) {
				var cname = c.name;
				if( cname == null ) cname = c.getDefaultEditorName();
				if( r == null ? c.name == name : r.match(cname) )
					rec(c, parts, index, out);
			}
		}

		var out = [];
		if( path == "" )
			out.push(prefab);
		else
			rec(prefab,path.split("."), 0, out);
		return out;
	}

	#if (editor || cdb_datafiles)

	public static function resolveCDBValue( path : String, key : Dynamic, obj : Dynamic ) : Dynamic {
		// allow Array as key (first choice)
		if( Std.isOfType(key,Array) ) {
			for( v in (key:Array<Dynamic>) ) {
				var value = resolveCDBValue(path, v, obj);
				if( value != null ) return value;
			}
			return null;
		}
		path += "."+key;

		var path = path.split(".");
		var sheet = base.getSheet(path.shift());
		if( sheet == null )
			return null;
		while( path.length > 0 && sheet != null ) {
			var f = path.shift();
			var value : Dynamic;
			if( f.charCodeAt(f.length-1) == "]".code ) {
				var parts = f.split("[");
				f = parts[0];
				value = Reflect.field(obj, f);
				if( value != null )
					value = value[Std.parseInt(parts[1])];
			} else
 				value = Reflect.field(obj, f);
			if( value == null )
				return null;
			var current = sheet;
			sheet = null;
			for( c in current.columns ) {
				if( c.name == f ) {
					switch( c.type ) {
					case TRef(name):
						sheet = base.getSheet(name);
						var ref = sheet.index.get(value);
						if( ref == null )
							return null;
						value = ref.obj;
					case TProperties, TList:
						sheet = current.getSub(c);
					default:
					}
					break;
				}
			}
			obj = value;
		}
		for( f in path )
			obj = Reflect.field(obj, f);
		return obj;
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
						var all = getPrefabsByPath(pf, p.path);
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
				temp.push(function() {
					sheet.lines = old.lines;
					sheet.linesData = old.linesData;
					sheet.separators = old.separators;
				});
				Reflect.deleteField(sheet,"lines");
				Reflect.deleteField(sheet,"linesData");
				sheet.separators = [];
			}
		}
		for( file => pf in prefabs ) {
			skip++;
			var path = ide.getPath(file);
			@:privateAccess var out = ide.toJSON(pf.serialize());
			if( force ) {
				var txt = try sys.io.File.getContent(path) catch( e : Dynamic ) null;
				if( txt == out ) continue;
			}
			sys.io.File.saveContent(path, out);
		}
		if( onSaveBase != null )
			onSaveBase();
		temp.reverse();
		for( t in temp )
			t();
	}

	// ---- TYPES Instances API -----

	public static function getAvailableTypes() {
		var sheets = [];
		var ide = Ide.inst;
		for( s in ide.database.sheets )
			if( s.props.dataFiles != null )
				sheets.push(s);
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

	#end

	public static function getTypeName( sheet : cdb.Sheet ) {
		return sheet.name.split("@").pop();
	}

}
