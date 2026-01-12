package hide.tools;

class IdeData {

	public var projectDir(get,never) : String;
	public var resourceDir(get,never) : String;
	public var appPath(get, null): String;
	public var userStatePath(get, null): String;
	public var database : cdb.Database = new cdb.Database();
	public var fileWatcher : hide.tools.FileWatcher;

	var databaseFile : String;
	var databaseDiff : String;
	var originDataBase : cdb.Database;
	var dbWatcher : hide.tools.FileWatcher.FileWatchEvent;

	var pakFile : hxd.fmt.pak.FileSystem;


	// Default settings for HideGlobalConfig since we can't init values in a typedef
	public var defaultIdeConfig : Map<String, Dynamic> = [
		"closeSearchOnFileOpen" => false,
		"typingDebounceThreshold" => 300,
		"autoSavePrefab" => false,
		"colorPickerEscUndo" => true,
		"trackGpuAlloc" => false,
		"svnShowVersionedFiles" => true,
		"svnShowModifiedFiles" => true,
		"unfocusCPUSavingMode" => true,
		"screenCaptureResolution" => 4096,
		"sceneEditorClickCycleObjects" => true,
		"orientMeshOnDrag" => true,
		"collisionOnDrag" => true,
		"minDistFromCameraOnDrag" => 1,
		"searchOnKeyPress" => true
	];

	public var currentConfig(get,never) : Config;
	public var ideConfig(get, never) : hide.Config.HideGlobalConfig;
	public var projectConfig(get, never) : hide.Config.HideProjectConfig;
	public var config : {
		global : Config, // Per user, for all projects
		user : Config, // Per user, specific project
		project : Config, // All users, specific project
		current : Config, // Merge of all configs above
	};

	public function new() {
	}

	function get_ideConfig() {
		applyDefaultValues();
		return cast config.global.source.hide;
	}
	function get_projectConfig() return cast config.user.source.hide;
	function get_currentConfig() return config.user;

	function get_projectDir() return ideConfig.currentProject.split("\\").join("/");
	function get_resourceDir() return projectDir+"/res";

	function getAppDataPath() {
		return new haxe.io.Path(Sys.programPath()).dir+"/";
	}

	function initConfig( cwd : String ) {
		config = Config.loadForProject(cwd, cwd+"/res", getAppDataPath());
		fileWatcher = new hide.tools.FileWatcher();
	}

	function setProject( dir : String ) {
		fileWatcher.dispose();
		dbWatcher = null;
		if( dir != ideConfig.currentProject ) {
			ideConfig.currentProject = dir;
			ideConfig.recentProjects.remove(dir);
			ideConfig.recentProjects.unshift(dir);
			if( ideConfig.recentProjects.length > 10 ) ideConfig.recentProjects.pop();
			config.global.save();
		}
		config = Config.loadForProject(projectDir, resourceDir, getAppDataPath());
		databaseFile = config.project.get("cdb.databaseFile");
		databaseDiff = config.user.get("cdb.databaseDiff");

		var pak = config.project.get("pak.dataFile");
		pakFile = null;
		if( pak != null ) {
			pakFile = new hxd.fmt.pak.FileSystem();
			try {
				pakFile.loadPak(getPath(pak));
			} catch( e : Dynamic ) {
				error(""+e);
			}
		}
	}

	public function error( e : Dynamic ) {
		throw e;
	}

	function fatalError( msg : String ) {
		error(msg);
		Sys.exit(0);
	}

	function get_appPath() {
		if( appPath != null )
			return appPath;
		var path = getAppPath();
		if( path == null )
			fatalError("Hide application path was not found");
		return appPath = path;
	}

	static function getAppPath() {
		var path = #if hl Sys.programPath() #else js.Node.process.argv[0] #end.split("\\").join("/").split("/");
		path.pop();
		var hidePath = path.join("/");
		if( !sys.FileSystem.exists(hidePath + "/package.json") ) {
			var prevPath = new haxe.io.Path(hidePath).dir;
			if( sys.FileSystem.exists(prevPath + "/hide.js") )
				return prevPath;
			// nwjs launch
			var path = Sys.getCwd().split("\\").join("/");
			if( sys.FileSystem.exists(path+"/hide.js") )
				return path;
			return null;
		}
		return hidePath;
	}

	function get_userStatePath() {
		var appPath = appPath;
		if( sys.FileSystem.exists(appPath + "/props.json") ) {
			return appPath;
		}
		if( Sys.systemName() ==  "Linux" ) {
			var statePath = Sys.getEnv("XDG_STATE_HOME");
			if( statePath == null ) {
				statePath = Sys.getEnv("HOME") + "/.local/state";
			}
			return statePath + "/hide";
		}
		return appPath;
	}

	public function makeRelative( path : String ) {
		path = path.split("\\").join("/");
		if( StringTools.startsWith(path.toLowerCase(), resourceDir.toLowerCase()+"/") )
			return path.substr(resourceDir.length+1);

		// is already a relative path
		if( path.charCodeAt(0) != "/".code && path.charCodeAt(1) != ":".code )
			return path;

		var resParts = resourceDir.split("/");
		var pathParts = path.split("/");
		for( i in 0...resParts.length ) {
			if( pathParts[i].toLowerCase() != resParts[i].toLowerCase() ) {
				if( pathParts[i].charCodeAt(pathParts[i].length-1) == ":".code )
					return path; // drive letter change
				var newPath = pathParts.splice(i, pathParts.length - i);
				for( k in 0...resParts.length - i )
					newPath.unshift("..");
				return newPath.join("/");
			}
		}
		return path;
	}

	public function getPath( relPath : String ) {
		if( relPath == null )
			return null;
		relPath = relPath.split("${HIDE}").join(appPath);
		if( haxe.io.Path.isAbsolute(relPath) )
			return relPath;
		return resourceDir+"/"+relPath;
	}

	public function getRelPath(absPath: String) {
		if (absPath == null)
			return null;
		if (!haxe.io.Path.isAbsolute(absPath))
			return absPath;
		return StringTools.replace(absPath, resourceDir + "/", "");
	}

	public function getDirPath(path: String) {
		return path.substring(0, path.lastIndexOf("/"));
	}

	var lastDBContent = null;
	function loadDatabase( ?checkExists ) {
		var exists = fileExists(databaseFile);
		if( checkExists && !exists )
			return; // cancel load
		var loadedDatabase = new cdb.Database();
		if( !exists ) {
			database = loadedDatabase;
			return;
		}
		try {
			lastDBContent = getFileText(databaseFile);
			loadedDatabase.load(lastDBContent);
		} catch( e : Dynamic ) {
			error(e);
			return;
		}
		database = loadedDatabase;
		if( databaseDiff != null ) {
			originDataBase = new cdb.Database();
			lastDBContent = getFileText(databaseFile);
			originDataBase.load(lastDBContent);
			if( fileExists(databaseDiff) ) {
				var d = new cdb.DiffFile();
				d.apply(database,parseJSON(getFileText(databaseDiff)),config.project.get("cdb.view"));
			}
		}
		if( dbWatcher == null )
			dbWatcher = fileWatcher.register(databaseFile,function() {
				loadDatabase(true);
				#if js
				hide.comp.cdb.Editor.refreshAll(true);
				#end
			});
	}

	public function saveDatabase( ?forcePrefabs ) {
		var lastStats = fileStat(databaseFile);
		if( dbWatcher != null ) {
			var b = fileWatcher.isChangePending(dbWatcher);
			if( b ) {
				throw "Save when database is changed outside of Hide and is waiting for reload. Please reload Hide.";
			}
		}

		function checkBeforeWrite() {
			var stats = fileStat(databaseFile);
			if( stats == null || lastStats == null )
				return;
			if( stats.mtime.getTime() != lastStats.mtime.getTime() )
				throw "Save when database is changed outside of Hide. Please reload Hide.";
		}
		#if js
		hide.comp.cdb.DataFiles.save(function() {
			if( databaseDiff != null ) {
				checkBeforeWrite();
				sys.io.File.saveContent(getPath(databaseDiff), toJSON(new cdb.DiffFile().make(originDataBase,database)));
				if ( dbWatcher != null )
					fileWatcher.ignorePrevChange(dbWatcher);
			} else {
				if( !sys.FileSystem.exists(getPath(databaseFile)) && fileExists(databaseFile) ) {
					// was loaded from pak, cancel changes
					loadDatabase();
					hide.comp.cdb.Editor.refreshAll();
					return;
				}

				var backup = [];
				for (sheet in database.sheets) {
					// only perform cleanup on root sheets as the function is recursive
					if (sheet.parent == null) {
						hide.comp.cdb.Editor.cleanupOptionalLines(sheet.lines, sheet, backup);
					}
				}

				lastDBContent = database.save();
				checkBeforeWrite();
				sys.io.File.saveContent(getPath(databaseFile), lastDBContent);
				if ( dbWatcher != null )
					fileWatcher.ignorePrevChange(dbWatcher);

				hide.comp.cdb.Editor.restoreOptionals(backup);
			}
		}, forcePrefabs);
		#end
	}

	public function fileExists( path : String ) {
		if( sys.FileSystem.exists(getPath(path)) ) return true;
		if( pakFile != null && pakFile.exists(path) ) return true;
		return false;
	}

	public function fileStat( path : String ) : Null<sys.FileStat> {
		var fullPath = getPath(path);
		if( !sys.FileSystem.exists(fullPath) )
			return null;
		return sys.FileSystem.stat(fullPath);
	}

	public function getFile( path : String ) {
		var fullPath = getPath(path);
		try {
			return sys.io.File.getBytes(fullPath);
		} catch( e : Dynamic ) {
			if( pakFile != null )
				return pakFile.get(path).getBytes();
			throw e;
		}
	}

	public function getFileText( path : String ) {
		var fullPath = getPath(path);
		try {
			return sys.io.File.getContent(fullPath);
		} catch( e : Dynamic ) {
			if( pakFile != null )
				return pakFile.get(path).getText();
			throw e;
		}
	}

	public function parseJSON( str : String ) : Dynamic {
		// remove comments
		str = ~/^[ \t]+\/\/[^\n]*/gm.replace(str, "");
		return haxe.Json.parse(str);
	}

	public function toJSON( v : Dynamic ) {
		var str = haxe.Json.stringify(v, "\t");
		str = ~/,\n\t+"__id__": [0-9]+/g.replace(str, "");
		str = ~/\t+"__id__": [0-9]+,\n/g.replace(str, "");
		return str;
	}

	public function loadPrefab<T:hrt.prefab.Prefab>( file : String, ?cl : Class<T>, ?checkExists ) : T {
		if( file == null )
			return null;
		try {
			var path = getPath(file);
			if( checkExists && !sys.FileSystem.exists(path) )
				return null;
			var p = hrt.prefab.Prefab.createFromDynamic(parseJSON(sys.io.File.getContent(path)));
			p.shared.currentPath = file;
			if( cl == null )
				return cast p;
			return p.get(cl);
		} catch( e : Dynamic ) {
			error("Invalid prefab "+file+" ("+e+")");
			throw e;
		}
	}

	public function savePrefab( file : String, f : hrt.prefab.Prefab ) {
		@:privateAccess var content = f.serialize();
		sys.io.File.saveContent(getPath(file), toJSON(content));
	}

	public function applyDefaultValues() {
		var ideConfig = config.global.source.hide;
		for (field => value in defaultIdeConfig) {
			if (!Reflect.hasField(ideConfig, field))
				Reflect.setProperty(ideConfig, field, value);
		}
	}

	public function removeDefaultValues() {
		var ideConfig = config.global.source.hide;
		for (field => value in defaultIdeConfig) {
			if (Reflect.getProperty(ideConfig, field) == value)
				Reflect.deleteField(ideConfig, field);
		}
	}
}
