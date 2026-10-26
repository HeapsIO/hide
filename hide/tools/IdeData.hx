package hide.tools;

class IdeData {

	public var projectDir(get,never) : String;
	function get_projectDir() return currentProject.split("\\").join("/");

	public var resourceDir(get,never) : String;
	function get_resourceDir() return projectDir+"/res";

	public var appPath(get, null): String;
	public var userDataPath(get, null): String;
	public var database : cdb.Database = new cdb.Database();
	public var fileWatcher : hide.tools.FileWatcher;
	public var shaderLoader : hide.tools.ShaderLoader;

	public var userConfig(get, never) : Config; // Preferences of the user for all the projects
	function get_userConfig() return config.user;

	public var projectConfig(get, never) : Config; // Config of the project, shared by all its users
	function get_projectConfig() return config.project;

	public var projectUserConfig(get, never) : Config; // Preferences of the user for the current project
	function get_projectUserConfig() return config.projectUser;

	public var currentConfig(get, never) : Config.ReadOnlyConfig; // Value of the config that applies (all the layers merged). Writes must be done on a specific layer
	function get_currentConfig() return config.projectUser;

	// Editor states is basically editor UI state (camera position, last view opened, etc)
	public var globalState(default, null) : EditorState;
	public var projectState(default, null) : EditorState;

	public var currentProject(get, never) : String;
	function get_currentProject() : String return projectOverride ?? globalState.get("currentProject", "");
	/** Project dir forced from the command line, never saved as the current project **/
	var projectOverride : String;
	public var recentProjects(get, never) : Array<String>;
	function get_recentProjects() : Array<String> return globalState.get("recentProjects", []);

	/**
		Indicates that this ide shouldn't try
		to save configs (used by the thumbnail generator app)
	**/
	public var readOnlyConfig = false;

	/** Ignore user configs and states (only defaults and project config are loaded), implies readOnlyConfig **/
	public var defaultConfig(default, set) = false;
	function set_defaultConfig(v) {
		if( v ) readOnlyConfig = true;
		return defaultConfig = v;
	}

	/** Default values of the user preferences, set in the defaults layer of the configs **/
	public var defaultUserConfig : Map<String, Dynamic> = [
		"hide.enableDBFormulas" => true,
		"hide.closeSearchOnFileOpen" => false,
		"hide.typingDebounceThreshold" => 300,
		"hide.autoSavePrefab" => false,
		"hide.colorPickerEscUndo" => true,
		"hide.trackGpuAlloc" => false,
		"hide.textureStreaming" => true,
		"hide.svnShowVersionedFiles" => true,
		"hide.svnShowModifiedFiles" => true,
		"hide.unfocusCPUSavingMode" => true,
		"hide.screenCaptureResolution" => 4096,
		"hide.sceneEditorClickCycleObjects" => true,
		"hide.orientMeshOnDrag" => true,
		"hide.collisionOnDrag" => true,
		"hide.minDistFromCameraOnDrag" => 1,
		"hide.searchOnKeyPress" => true
	];

	static final dBReloadMaxRetries = 5;
	var databaseFile : String;
	var databaseDiff : String;
	var originDataBase : cdb.Database;
	var dbWatcher : hide.tools.FileWatcher.FileWatchEvent;

	var config : {
		user : Config,
		project : Config,
		projectUser : Config,
	};

	var pakFile : hxd.fmt.pak.FileSystem;

	public function new() {
	}

	public function getProjectDataPath( projectPath : String ) : String {
		return userDataPath + "/projects/" + projectPath.split("\\").join("/").split("/").join("_").split(":").join("_");
	}

	function initConfig( cwd : String ) {
		globalState = new EditorState(defaultConfig ? null : userDataPath + "/editorState.json");
		projectState = new EditorState();
		config = Config.loadForProject(cwd, cwd+"/res");
		fileWatcher = new hide.tools.FileWatcher();
	}

	public function isProjectValid() : Bool {
		return currentProject != "";
	}

	function setProject( dir : String ) {
		fileWatcher.dispose();
		dbWatcher = null;
		dir = dir.split("\\").join("/");
		if( dir != projectDir ) {
			projectOverride = null;
			var recents = [dir];
			for( p in recentProjects ) {
				p = p.split("\\").join("/");
				if( recents.indexOf(p) < 0 ) recents.push(p);
			}
			if( recents.length > 10 ) recents.pop();
			globalState.set("recentProjects", recents);
			globalState.set("currentProject", dir);
		}
		#if js
		if( isProjectValid() ) fileWatcher.rootDir = resourceDir;
		#end
		projectState = isProjectValid() && !defaultConfig ? new EditorState(getProjectDataPath(projectDir) + "/editorState.json") : new EditorState();
		config = Config.loadForProject(projectDir, resourceDir);
		databaseFile = currentConfig.get("cdb.databaseFile") ?? "data.cdb";
		databaseDiff = currentConfig.get("cdb.databaseDiff");

		var pak = currentConfig.get("pak.dataFile");
		pakFile = null;
		if( pak != null ) {
			pakFile = new hxd.fmt.pak.FileSystem();
			try {
				pakFile.loadPak(getPath(pak));
			} catch( e : Dynamic ) {
				error(""+e);
			}
		}

		shaderLoader = new hide.tools.ShaderLoader();
	}

	public function listMatLibraries(path : String) {
		var config = hide.Config.loadForFile(this, path);

		var matLibs : Array<Dynamic> = config.get("materialLibraries");
		if( matLibs == null ) matLibs = [];

		if (matLibs.length > 0) {
			for (idx in 0...matLibs.length) {
				var m = Std.isOfType(matLibs[idx], String) ? cast (matLibs[idx]) : null;
				if (m == null)
					continue;
				matLibs[idx] = { name : m.substring(m.lastIndexOf("/") + 1), path : m };
			}
		}

		return matLibs;
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
		#if js
		if( !sys.FileSystem.exists(hidePath + "/package.json") ) {
			var prevPath = new haxe.io.Path(hidePath).dir;
			if( sys.FileSystem.exists(prevPath + "/hide.js") )
				return prevPath;
			// packaged electron
			if( sys.FileSystem.exists(hidePath + "/resources/app/hide.js") )
				return hidePath + "/resources/app";
			// nwjs launch
			var path = Sys.getCwd().split("\\").join("/");
			if( sys.FileSystem.exists(path+"/hide.js") )
				return path;
			return null;
		}
		#end
		return hidePath;
	}

	function get_userDataPath() {
		if( userDataPath != null )
			return userDataPath;
		var name = #if hl "hide-hl" #else "hide" #end;
		var dir = switch( Sys.systemName() ) {
			case "Windows": Sys.getEnv("LOCALAPPDATA") + "/" + name;
			case "Mac": Sys.getEnv("HOME") + "/Library/Application Support/" + name;
			default: (Sys.getEnv("XDG_STATE_HOME") ?? Sys.getEnv("HOME") + "/.local/state") + "/" + name;
		}
		return userDataPath = dir.split("\\").join("/");
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
	var lastStats: Null<sys.FileStat> = null;
	function loadDatabase( ?checkExists, retries: Int = 0) {


		var exists = fileExists(databaseFile);
		if( checkExists && !exists )
			return; // cancel load
		var loadedDatabase = new cdb.Database();
		if( !exists ) {
			database = loadedDatabase;
			return;
		}
		var prevLoadedDatabase = lastDBContent;
		var prevStats = lastStats;
		try {
			lastDBContent = getFileText(databaseFile);
			lastStats = fileStat(databaseFile);
			loadedDatabase.load(lastDBContent);
		} catch( e : Dynamic ) {
			lastDBContent = prevLoadedDatabase;
			lastStats = prevStats;

			// Sometimes, loading the database can fail because getFileText returns an empty string
			// this seems to happen when another program tries to write to to the file when we are trying to read it. In that
			// case, we schedule another loadDatabase call in the future
			if (retries < dBReloadMaxRetries) {
				haxe.Timer.delay(function() {
					loadDatabase(checkExists, retries + 1);
					// the editors were refreshed with the previous database
					#if js
					hide.comp.cdb.Editor.refreshAll(true);
					#end
				}, 100);
			} else {
				error("Can't load " + databaseFile + " (SVN conflict?), it will not be saved until it is fixed : " + e);
			}
			return;
		}
		database = loadedDatabase;
		if( databaseDiff != null ) {
			originDataBase = new cdb.Database();
			lastDBContent = getFileText(databaseFile);
			originDataBase.load(lastDBContent);
			if( fileExists(databaseDiff) ) {
				var d = new cdb.DiffFile();
				d.apply(database,parseJSON(getFileText(databaseDiff)),currentConfig.get("cdb.view"));
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

	public static function openExternalFile(filePath: String) {
		if(!haxe.io.Path.isAbsolute(filePath)) {
			filePath = Ide.inst.getPath(filePath);
		}

		switch(Sys.systemName()) {
			case "Windows":
				// note : the "" is not a typo but a quirk in the way start use the first quoted argument as the
				// window title when spawning a command, which we don't want
				filePath = StringTools.replace(filePath, "/", "\\");
				new sys.io.Process('start "" "$filePath"',null, true);
			case "Mac":
				new sys.io.Process('open "$filePath"', null, true);
			case "Linux":
				new sys.io.Process('xdg-open "$filePath"', null, true);
			default: throw "OpenExternalFile not implemented on this platform";
		}
	}

	public static function showFileInExplorer(path : String) {
		if(!haxe.io.Path.isAbsolute(path)) {
			path = Ide.inst.getPath(path);
		}

		switch(Sys.systemName()) {
			case "Windows": {
				var cmd = "explorer.exe /select," + '"' + StringTools.replace(path, "/", "\\") + '"';
				Sys.command(cmd);
			};
			case "Mac":	Sys.command("open " + haxe.io.Path.directory(path));
			case "Linux":
				Sys.command('dbus-send --session --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:"$path" string:""');
			default: throw "Exploration not implemented on this platform";
		}
	}


	// the file is not the one loaded or saved last (SVN update, conflict...) : writing it would revert these changes
	function databaseHasExternChanges() : Bool {
		if( lastDBContent == null )
			return false;
		var stats = fileStat(databaseFile);
		if( stats == null )
			return false;
		if( lastStats != null && stats.mtime.getTime() == lastStats.mtime.getTime() && stats.size == lastStats.size )
			return false;
		return getFileText(databaseFile) != lastDBContent;
	}

	var externReload : haxe.Timer;
	function onDatabaseExternChanges() {
		if( externReload != null )
			return;
		error(databaseFile + " was modified outside of HIDE (SVN update?) : the last change is not saved to keep these modifications, the database is reloaded.");
		externReload = haxe.Timer.delay(function() {
			externReload = null;
			loadDatabase(true);
			#if js
			hide.comp.cdb.Editor.refreshAll(true);
			#end
		}, 0);
	}

	public function saveDatabase( ?forcePrefabs ) {
		if (readOnlyConfig)
			return;
		#if js
		if (Ide.inst.thumbnailMode == true)
			throw "Thumbnail generator can't save the cdb database";
		#end

		if( (dbWatcher != null && fileWatcher.isChangePending(dbWatcher)) || databaseHasExternChanges() ) {
			onDatabaseExternChanges();
			return;
		}

		#if js
		hide.comp.cdb.DataFiles.save(function() {
			if( databaseDiff != null ) {
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
				sys.io.File.saveContent(getPath(databaseFile), lastDBContent);
				lastStats = fileStat(databaseFile);
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
		var replaceFn =
		#if( js_es == 5 )
			// filter out `__id__` keys that are added when the objects are used as key in Maps (haxe -> js ECMA 5.0 behavior)
			(key, value) -> key == "__id__" ? js.Lib.undefined : value;
		#else
			null;
		#end

		return haxe.Json.stringify(v, replaceFn, "\t");
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
}
