package hide;

typedef LayoutState = {
	var content : Any;
	var fullScreen : { name : String, state : Any };
}

typedef HideGlobalConfig = {
	var autoSaveLayout : Null<Bool>;
	var useAlternateFont : Null<Bool>;

	var currentProject : String;
	var recentProjects : Array<String>;

	var windowPos : { x : Int, y : Int, w : Int, h : Int, max : Bool };

	@:optional var sceneEditorLayout : { colsVisible : Bool, colsCombined : Bool };

	// General
	var autoSavePrefab : Bool;

	// Search
	var closeSearchOnFileOpen : Bool;
	var typingDebounceThreshold : Int;

	// Performance
	var trackGpuAlloc : Bool;
	var cullingDistanceFactor : Float;
};

typedef HideProjectConfig = {
	var layouts : Array<{ name : String, state : LayoutState }>;
	var renderer : String;
	var dbCategories : Array<String>;
	var dbProofread : Null<Bool>;
};

typedef ConfigDef = {
	var hide : {};
};

class Config {

	var ide : Ide;
	var parent : Config;
	public var path(default,null) : String;
	public var source(default, null) : ConfigDef = cast {};
	public var current : ConfigDef = cast {};

	public function new( ?parent : Config ) {
		ide = Ide.inst;
		this.parent = parent;
		sync();
	}

	public function isLocal() {
		if( path == null && parent != null ) return parent.isLocal();
		return path == null || StringTools.startsWith(path, ide.projectDir);
	}

	public function load( path : String ) {
		this.path = path;
		var fullPath = ide.getPath(path);
		if( sys.FileSystem.exists(fullPath) )
			source = try ide.parseJSON(sys.io.File.getContent(fullPath)) catch( e : Dynamic ) throw e+" (in "+fullPath+")";
		else
			source = cast {};
		sync();
	}

	public function save() {
		ide.removeDefaultValues();
		sync();
		if( path == null ) throw "Cannot save properties (unknown path)";
		var fullPath = ide.getPath(path);
		if( Reflect.fields(source).length == 0 )
			try sys.FileSystem.deleteFile(fullPath) catch( e : Dynamic ) {};
		else {
			var directory = haxe.io.Path.directory(fullPath);
			if( !sys.FileSystem.exists(directory) ) {
				sys.FileSystem.createDirectory(directory);
			}
			sys.io.File.saveContent(fullPath, ide.toJSON(source));
		}
	}

	public function sync() {
		if( parent != null ) parent.sync();
		current = cast {};
		if( parent != null ) merge(parent.current);
		if( source != null ) merge(source);
	}

	function merge( value : Dynamic ) {
		mergeRec(current, value);
	}

	function mergeRec( dst : Dynamic, src : Dynamic ) {
		for( f in Reflect.fields(src) ) {
			var append = false;

			var v : Dynamic = Reflect.field(src,f);
			if (StringTools.endsWith(f, "+")) {
				append = true;
				f = f.substr(0, f.length-1);
			}

			var t : Dynamic = Reflect.field(dst, f);
			if( Type.typeof(v) == TObject ) {
				if( t == null ) {
					t = {};
					Reflect.setField(dst, f, t);
				}
				mergeRec(t, v);
			} else if( v == null )
				Reflect.deleteField(dst, f);
			else {
				if (append && Type.typeof(v).match(TClass(Array))) {
					var arr : Array<Dynamic> = cast t ?? [];
					arr = arr.concat(cast v);
					Reflect.setField(dst, f, arr);

				} else {
					Reflect.setField(dst,f,v);
				}
			}
		}
	}

	public function get( key : String, ?defaultVal : Dynamic ) : Dynamic {
		var val = Reflect.field(current,key);
		if(val != null) return val;
		return defaultVal;
	}

	public function getLocal( key : String, ?defaultVal : Dynamic ) : Dynamic {
		var v = get(key);
		if( v == null ) return defaultVal;
		if( isLocal() ) return v;
		if( parent == null ) return defaultVal;
		return parent.getLocal(key,defaultVal);
	}

	public function set( key : String, val : Dynamic ) {
		if( val == null )
			Reflect.deleteField(source, key);
		else
			Reflect.setField(source, key, val);
		save();
	}

	static function alert(msg) {
		#if js
		js.Browser.window.alert(msg);
		#else
		throw msg;
		#end
	}

	public static function loadConfig(config : Config, path : String) : Config {
		try {
			config.load(path);
		} catch(err) {
			alert('Couldn\'t load config file ${path}. Reverting to default config.\n${err}.');
		}
		return config;
	}

	public static function loadForProject( projectPath : String, resourcePath : String, appDataPath : String ) {
		var hidePath = Ide.inst.appPath;

		var defaults = new Config();
		try {
			defaults.load(hidePath + "/defaultProps.json");
		}
		catch (err) {
			alert('Fatal error : Couldn\'t load ${hidePath}/defaultProps.json. Please check your hide installation.\n$err');
			Sys.exit(-1);
		}

		var userGlobals = loadConfig(new Config(defaults), Ide.inst.userStatePath + "/props.json");

		if( userGlobals.source.hide == null )
			userGlobals.source.hide = {
				autoSaveLayout : true,
				layouts : null,
				recentProjects : [],
				currentProject : "",
				windowPos : null,
				renderer : null,
			};

		var perProject = loadConfig(new Config(userGlobals), resourcePath + "/props.json");

		var projectUserCustom = loadConfig(new Config(perProject), appDataPath + "/" + projectPath.split("\\").join("/").split("/").join("_").split(":").join("_") + ".json");
		var p = projectUserCustom;
		if( p.source.hide == null )
			p.source.hide = ({ layouts : [], renderer : null, dbCategories: null, dbProofread: null } : HideProjectConfig);

		var current = new Config(projectUserCustom);

		return {
			global : userGlobals,
			project : perProject,
			user : projectUserCustom,
			current : current,
		};
	}

	public static function loadForFile( ide : hide.Ide, path : String ) {
		var parts = path.split("/");
		var propFiles = [];
		var first = true, allowSave = false;
		while( true ) {
			var pfile = ide.getPath(parts.join("/") + "/props.json");
			if( sys.FileSystem.exists(pfile) ) {
				propFiles.unshift(pfile);
				if( first ) allowSave = true;
			}
			if( parts.length == 0 ) break;
			first = false;
			parts.pop();
		}
		var parent = ide.currentConfig;
		for( p in propFiles ) {
			parent = new Config(parent);
			parent.load(p);
		}
		return allowSave ? parent : new Config(parent);
	}

}
