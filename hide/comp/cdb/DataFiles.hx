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
	static var watching : Map<String, Void -> Void > = new Map();

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

	public static function loadFile( file : String, sheet : cdb.Sheet) @:privateAccess {
		var sheetName = getTypeName(sheet);
		var levelID = file.split("/").pop().split(".").shift();
		levelID = levelID.charAt(0).toUpperCase()+levelID.substr(1);

		var allMap : Map<String, Array<hrt.prefab.Prefab>> = [];

		function loadRec( p : hrt.prefab.Prefab, parent : hrt.prefab.Prefab, toRemove : Array<DataProps> ) {
			// Initiliaze to remove list with the full list of lines data.
			if (parent == null) {
				toRemove = new Array<DataProps>();
				for (ld in sheet.sheet.linesData)
					if (ld.file == file)
						toRemove.push(ld);
			}

			if( p.getCdbType() == sheetName ) {
				var dprops : DataProps = {
					file : file,
					path : p.getAbsPath(),
					index : 0,
					origin : haxe.Json.stringify(p.props)
				};

				// deduplicate prefabs that have the same absPath
				var all = allMap.get(dprops.path);
				if (all == null) {
					all = getPrefabsByPath(p.getRoot(), dprops.path);
					allMap.set(dprops.path, all);
				}

				dprops.index = all.indexOf(p);

				if( sheet.idCol != null && Reflect.field(p.props,sheet.idCol.name) == "" )
					Reflect.setField(p.props,sheet.idCol.name,levelID+"_"+p.name+(dprops.index == 0 ? "" : ""+dprops.index));

				var changed = false;
				for (idx => ld in sheet.sheet.linesData) {
					if (ld.file == file && ld.path == p.getAbsPath()) {
						if (ld.index == dprops.index) {
							toRemove.remove(sheet.sheet.linesData[idx]);
							sheet.sheet.linesData[idx] = dprops;
							sheet.sheet.lines[idx] = p.props;
							changed = true;
						}
					}
				}

				// Meaning that this is new data to add so insert it at the right index
				if (!changed) {
					var sepIdx = getSeparatorForPath(file, sheet);
					var idxInsert = sheet.sheet.separators[sepIdx].index;

					// Insert new line
					sheet.sheet.linesData.insert(idxInsert, dprops);
					sheet.sheet.lines.insert(idxInsert, p.props);

					// Shift separators
					for (idx in (sepIdx + 1)...sheet.sheet.separators.length)
						sheet.sheet.separators[idx].index++;
				}
			}

			for( c in p )loadRec(c,p,toRemove);

			if (parent == null) {
				for (rem in toRemove) {
					var idxRemove = sheet.sheet.linesData.indexOf(rem);

					// Shift sperators
					var sepIdx = sheet.sheet.separators.length;
					for (idx => s in sheet.sheet.separators) {
						if (s.index > idxRemove) {
							sepIdx = idx;
							break;
						}

					}

					for (idx in (sepIdx)...sheet.sheet.separators.length)
						sheet.sheet.separators[idx].index--;

					sheet.sheet.linesData.remove(rem);
					sheet.sheet.lines.remove(sheet.sheet.lines[idxRemove]);

					// Remove potentials un-used separators
					removeSeparatorForPath(file, sheet);
				}
			}
		}

		var p = loadPrefab(file);
		loadRec(p,null,[]);
	}

	/*
		Return the index of the corresponding separator in the sheet's separators array for a path.
		If there's not already a separator for the path, create it.
	*/
	static function getSeparatorForPath(path: String, sheet: cdb.Sheet) : Int {
		var separators = @:privateAccess sheet.sheet.separators;

		function comparePath(p1 : String, p2 : String) : Int {
			var p1Parts = p1.split("/");
			var p2Parts = p2.split("/");

			var idx = 0;
			while (true) {
				if (p1Parts.length <= idx || p2Parts.length <= idx || p1Parts[idx] != p2Parts[idx])
					return idx - 1;

				idx++;
			}
		}

		function findParentSep(sepIdx : Int) : cdb.Data.Separator {
			var idx = sepIdx - 1;
			while (idx > 0) {
				if (separators[idx].level < separators[sepIdx].level)
					return separators[idx];

				idx--;
			}

			return null;
		}

		function addChildSeparator(sep: cdb.Data.Separator, parentSepIdx: Int) : Int {
			// We might want to add it following the alphabetic order and not at the last position
			for (idx in (parentSepIdx + 1)...separators.length) {
				var s = separators[idx];

				if (s.level < sep.level) {
					separators.insert(idx, sep);
					return idx;
				}
			}

			separators.push(sep);
			return separators.length -1;
		}

		// Try to find the most matching separator for this path
		var matchingSepData = { sepIdx: -1, level: -1 };
		for (sIdx => s in separators) {
			var level = comparePath(s.path, path);
			if (level > matchingSepData.level) {
				matchingSepData.sepIdx = sIdx;
				matchingSepData.level = level;
			}
		}

		// Meaning that there's already a separator for this path
		if (matchingSepData.level == path.split("/").length - 1)
			return matchingSepData.sepIdx;

		// Meaning that there is one partial matching separator for this path
		if (matchingSepData.level != -1) {
			var pathSplit = path.split("/");
			var matchingSep = separators[matchingSepData.sepIdx];
			var matchingSepPathSplit = matchingSep.path.split("/");

			// Check if the matching sep is fully matching
			if (matchingSepPathSplit.length == matchingSepData.level + 1) {
				var sep : cdb.Data.Separator = {};
				sep.level = matchingSep.level + 1;

				var newPath = [ for(idx in (matchingSepData.level + 1)...pathSplit.length) pathSplit[idx]].join("/");
				sep.path = matchingSep.path + "/" + newPath;
				sep.title = StringTools.replace(newPath, "/", " > ");
				if (sep.title.split(".").length >= 2) {
					var tmp = sep.title.split(".");
					tmp.pop();
					sep.title = tmp.join("");
				}

				var idx = addChildSeparator(sep, matchingSepData.sepIdx);
				sep.index = idx == separators.length - 1 ? @:privateAccess sheet.sheet.lines.length : separators[idx + 1].index - 1;
				return idx;
			}
			else {
				// Otherwise split the matching part of the separator

				// Modify the most matching separator in a fully matching separator (remove the diff part of it)
				var parentSep = findParentSep(matchingSepData.sepIdx);
				var newPath = [ for(idx in 0...matchingSepData.level + 1) matchingSepPathSplit[idx]].join("/");
				matchingSep.path = newPath;
				matchingSep.title = StringTools.replace(parentSep != null ? newPath.substr(parentSep.path.length + 1) : newPath, "/", " > ");

				// Create a new separator for the existings lines that were under the one we splitted
				newPath = [ for(idx in (matchingSepData.level + 1)...matchingSepPathSplit.length) matchingSepPathSplit[idx] ].join("/");
				var sep : cdb.Data.Separator = {
					title : StringTools.replace(newPath, "/", " > "),
					index : matchingSep.index,
					level : matchingSep.level + 1,
					path : matchingSep.path + "/" + newPath
				};

				if (sep.title.split(".").length >= 2) {
					var tmp = sep.title.split(".");
					tmp.pop();
					sep.title = tmp.join("");
				}

				separators.insert(matchingSepData.sepIdx + 1, sep);

				// Shift levels of separators that were children of the one we splitted
				for (idx in (matchingSepData.sepIdx + 2)...separators.length) {
					var s = separators[idx];

					if (s.level <= matchingSep.level)
						break;

					s.level++;
				}

				// Then create a new separator for the new path
				newPath = [ for(idx in (matchingSepData.level + 1)...pathSplit.length) pathSplit[idx]].join("/");
				var newSep : cdb.Data.Separator = {
					title : StringTools.replace(newPath, "/", " > "),
					level : matchingSep.level + 1,
					path : matchingSep.path + "/" + newPath
				};

				if (newSep.title.split(".").length >= 2) {
					var tmp = newSep.title.split(".");
					tmp.pop();
					newSep.title = tmp.join("");
				}

				var newSepIdx = addChildSeparator(newSep, matchingSepData.sepIdx);
				newSep.index = newSepIdx == separators.length - 1 ? @:privateAccess sheet.sheet.lines.length : separators[newSepIdx + 1].index - 1;
				return newSepIdx;
			}
		}

		// Meaning that there is no matching separator at all and we need to create one
		var newSep : cdb.Data.Separator = {
			title : StringTools.replace(path, "/", " > "),
			level : 0,
			path : path
		};

		if (newSep.title.split(".").length >= 2) {
			var tmp = newSep.title.split(".");
			tmp.pop();
			newSep.title = tmp.join("");
		}

		var newSepIdx = addChildSeparator(newSep, -1);
		newSep.index = newSepIdx == separators.length - 1 ? @:privateAccess sheet.sheet.lines.length : separators[newSepIdx + 1].index - 1;
		return newSepIdx;
	}

	/*
		Remove all separators that aren't used after modification of a file at this path
	*/
	static function removeSeparatorForPath(path: String, sheet: cdb.Sheet, deleteWithContent : Bool = false) {
		var separators = @:privateAccess sheet.sheet.separators;
		var lines = @:privateAccess sheet.sheet.lines;
		var linesData = @:privateAccess sheet.sheet.linesData;

		function isSeparatorEmpty(sepIdx : Int) : Bool {
			if (sepIdx == separators.length - 1)
				return separators[sepIdx].index > lines.length - 1;

			var next = null;

			var idx = sepIdx + 1;
			while (idx < separators.length) {
				if (separators[idx].level <= separators[sepIdx].level) {
					next = separators[idx];
					break;
				}

				idx++;
			}

			if (next == null)
				return separators[sepIdx].index > lines.length - 1;


			return next.index <= separators[sepIdx].index;
		}

		function findParentSepIdx(sepIdx : Int) : Int {
			var idx = sepIdx - 1;
			while (idx > 0) {
				if (separators[idx].level < separators[sepIdx].level)
					return idx;

				idx--;
			}

			return -1;
		}

		function findChildrenSepIdx(sepIdx : Int) : Array<Int> {
			var children = [];

			if (sepIdx < 0 || sepIdx >= separators.length)
				return children;

			for (idx in (sepIdx + 1)...separators.length) {
				var s = separators[idx];

				if (findParentSepIdx(idx) == sepIdx)
					children.push(idx);
			}

			return children;
		}

		// Find current separator corresponding to this path
		var currentSepIdx = -1;
		for (sIdx => s in separators) {
			if (s.path == path) {
				currentSepIdx = sIdx;
				break;
			}
		}

		if (currentSepIdx == -1)
			return;

		// Delete content of the separator we want to remove (lines, separator etc)
		if (deleteWithContent) {
			var currentSep = separators[currentSepIdx];
			var idx = currentSepIdx + 1;
			var begin = currentSepIdx;
			var end = currentSepIdx;
			var lineBegin = separators[begin].index;
			var lineEnd = separators[end].index + 1;
			while (true) {
				if (idx >= separators.length || separators[idx].level >= currentSep.level) {
					lineEnd = idx >= separators.length ? lines.length : separators[idx].index;
					break;
				}

				idx++;
				end = idx;
			}


			var idx = end;
			while (idx > begin) {
				separators.remove(separators[idx]);
				currentSepIdx--;
				idx--;
			}

			var idx = lineEnd - 1;
			while (idx >= lineBegin) {
				lines.remove(lines[idx]);
				linesData.remove(linesData[idx]);
				idx--;
			}

			// Shift separators
			var diff = lineEnd - lineBegin;
			for (sepIdx in (begin+1)...separators.length) {
					separators[sepIdx].index -= diff;
			}
		}

		// Remove all empty separators (deletion is applied on parents too)
		var parentSepIdx = currentSepIdx;
		while (parentSepIdx != - 1) {
			if (isSeparatorEmpty(parentSepIdx)) {
				var tmp = findParentSepIdx(parentSepIdx);
				separators.remove(separators[parentSepIdx]);
				parentSepIdx = tmp;
			}

			break;
		}

		// Merge separator with parent if parent has exactly one child separator
		var childrenSep = findChildrenSepIdx(parentSepIdx);
		if (childrenSep.length == 1) {
			var childSep = separators[childrenSep[0]];
			var parentSep = separators[parentSepIdx];

			parentSep.path = childSep.path;
			parentSep.title = parentSep.title + " > " + childSep.title;

			separators.remove(childSep);
		}
	}

	#if (editor || cdb_datafiles)
	static function onFileChanged(path: String) {
		if( skip > 0 ) {
			skip--;
			return;
		}
		changed = true;
		haxe.Timer.delay(function() {
			if( !changed ) return;
			changed = false;

			// Only reload data files that are concerned by this file modification
			function reloadFile(path: String) {
				if( !watching.exists(path) ) {
					var fun = () -> onFileChanged(path);
					watching.set(path, fun);
					Ide.inst.fileWatcher.register(path, fun, true);
				}

				var fullPath = Ide.inst.getPath(path);
				if (sys.FileSystem.isDirectory(fullPath)) {
					var files = sys.FileSystem.readDirectory(fullPath);
					for (f in files)
						reloadFile(path + "/" + f);

					// If a file is deleted, this method is triggered with parent file, in that
					// case we need to retrieve deleted file to remove it.
					var deletedFiles : Array<String> = [];
					for (p in DataFiles.watching.keys()) {
						var abs = Ide.inst.getPath(p);

						// Meaning this is a deleted file
						if (StringTools.contains(abs, fullPath) && abs != fullPath && !sys.FileSystem.exists(abs)) {
							Ide.inst.fileWatcher.unregister(p, watching.get(p));
							watching.remove(p);

							if (!sys.FileSystem.isDirectory(abs)) {
								for( sheet in base.sheets ) {
									if( sheet.props.dataFiles != null ) {
										var dataFiles = sheet.props.dataFiles.split(";");
										for (dataFile in dataFiles) {
											var reg = new EReg("^"+dataFile.split(".").join("\\.").split("*").join(".*")+"$","");
											if (reg.match(p))
												DataFiles.removeSeparatorForPath(p, sheet, true);
										}
									}
								}
							}
						}

					}

					return;
				}

				for( sheet in base.sheets ) {
					if( sheet.props.dataFiles != null ) {
						var dataFiles = sheet.props.dataFiles.split(";");
						for (dataFile in dataFiles) {
							var reg = new EReg("^"+dataFile.split(".").join("\\.").split("*").join(".*")+"$","");
							if (reg.match(path))
								DataFiles.loadFile(path, sheet);
						}
					}
				}
			}

			// When deleting a file in hide (cf FileTree -> onDeleteFile()), each files are deleted
			// one by one, and each might not trigger the onFileChanged method because of the delay.
			// So we try to find the top level folder that still exists and reload it.
			var f = path;
			while (!sys.FileSystem.exists(Ide.inst.getPath(f)) && f != "") {
				var arr = f.split("/");
				arr.pop();
				f = arr.join("/");
			}

			reloadFile(f);
			Editor.refreshAll(false, false);
		},0);
	}

	static function loadPrefab(file) {
		var p = Ide.inst.loadPrefab(file);
		if( !watching.exists(file) ) {
			var fun = () -> onFileChanged(file);
			watching.set(file, fun);
			Ide.inst.fileWatcher.register(file, fun);
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

			var allMap : Map<String, Array<hrt.prefab.Prefab>> = [];

			function loadRec( p : hrt.prefab.Prefab, parent : hrt.prefab.Prefab ) {
				if( p.getCdbType() == sheetName ) {
					var dprops : DataProps = {
						file : file,
						path : p.getAbsPath(),
						index : 0,
						origin : haxe.Json.stringify(p.props),
					};

					// deduplicate prefabs that have the same absPath
					var all = allMap.get(dprops.path);
					if (all == null) {
						all = getPrefabsByPath(p.getRoot(), dprops.path);
						allMap.set(dprops.path, all);
					}

					dprops.index = all.indexOf(p);

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
					var fun = () -> onFileChanged(path);
					watching.set(path, fun);
					Ide.inst.fileWatcher.register(path, fun, true);
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
