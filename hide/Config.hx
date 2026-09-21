package hide;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/** A static variable decorated with `@:config`, gathered by `Config.configMacro()` **/
typedef ConfigField = {
	var field : Field;
	var key : String;
	var type : Null<ComplexType>;
	var defaultValue : Null<Expr>;
}
#end

typedef HideGlobalConfig = {
	var autoSaveLayout : Null<Bool>;
	var useAlternateFont : Null<Bool>;

	var currentProject : String;
	var recentProjects : Array<String>;

	var windowPos : { x : Int, y : Int, w : Int, h : Int, max : Bool };

	@:optional var sceneEditorLayout : { colsVisible : Bool, colsCombined : Bool };

	// General
	var autoSavePrefab : Bool;
	var svnShowVersionedFiles : Bool;
	var svnShowModifiedFiles : Bool;
	var enableDBFormulas : Bool;
	var screenCaptureResolution : Int;
	var minDistFromCameraOnDrag : Float;
	var colorPickerEscUndo : Bool;


	// Search
	var closeSearchOnFileOpen : Bool;
	var closeSearchOnCDBSheetChange : Bool;
	var typingDebounceThreshold : Int;

	// Performance
	var trackGpuAlloc : Bool;
	var unfocusCPUSavingMode : Bool;

	// Scene Editor
	var orientMeshOnDrag : Bool;
	var collisionOnDrag : Bool;
	var sceneEditorClickCycleObjects : Bool;

	// hidehl
	var sceneEditorVerticalSidebar: Bool;

	// CDB
	var searchOnKeyPress : Bool;
	var highlightActiveLine : Bool;
	var highlightActiveLineHeader : Bool;
	var highlightActiveColumnHeader : Bool;

	// Filebrowser
	var filebrowserDebugIgnoreThumbnailCache : Bool;
	var filebrowserDebugServerCommands : Bool;
	var filebrowserDebugShowWindow : Bool;
	var filebrowserDebugShowMenu : Bool;
};

typedef ConfigDef = {
	var hide : {};
};

class Config {
#if !macro

	var ide : Ide;
	var parent : Config;
	public var path(default,null) : String;
	public var source(default, null) : ConfigDef = cast {};
	public var current : ConfigDef = cast {};

	var prevConfig: String = null;

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
			var newSer = ide.toJSON(source);

			if (prevConfig != newSer)
				sys.io.File.saveContent(fullPath, newSer);
			prevConfig = newSer;
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
				enableDBFormulas : true,
				layouts : null,
				recentProjects : [],
				currentProject : "",
				windowPos : null,
				renderer : null,
			};

		var perProject = loadConfig(new Config(userGlobals), resourcePath + "/props.json");

		var projectUserCustom = loadConfig(new Config(perProject), appDataPath + "/" + projectPath.split("\\").join("/").split("/").join("_").split(":").join("_") + ".json");
		var p = projectUserCustom;
		if( p.source.hide == null ) {
		#if js
			p.source.hide = ({ layouts : [], renderer : null, dbCategories: null, dbProofread: null } : HideProjectConfig);
		#else
			p.source.hide = ({ tabViews:
				{
					"left-panel": {
						tabIndex: 0,
						tabs: [{type: "fileBrowser"}]
					},
				}
			} : HideProjectConfig);
		#end
		}

		var current = new Config(projectUserCustom);

		return {
			global : userGlobals,
			project : perProject,
			user : projectUserCustom,
			current : current,
		};
	}

	public static function loadForFile( ide : hide.tools.IdeData, path : String ) {
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

#end

#if macro

	/**
		Build macro to be used as `@:build(hide.Config.configMacro())` on a class.

		Every static variable of that class decorated with `@:config` is meant to be
		persisted through `hide.Ide.inst.currentConfig.get/set` instead of being stored
		in the class itself.

		Keys are always prefixed so they can't collide with the ones of another class :
		the prefix is `prefix` when it is given to the macro (`@:build(hide.Config.configMacro("myPrefix"))`),
		the full dot path of the class otherwise.

		By default the key of a variable is `<prefix>.<variableName>`. A custom name can be
		given to the metadata (`@:config("myName")`), which gives `<prefix>.myName`. As an
		escape hatch, a name starting with a `#` is not prefixed at all : `@:config("#myKey")`
		uses `myKey` as the full key, which is useful to read a key that already exists
		somewhere else in the config.
	**/
	public static function configMacro( ?prefix : String ) : Array<Field> {
		var cl = Context.getLocalClass().get();
		var fields = Context.getBuildFields();

		var keyPrefix = prefix ?? cl.pack.concat([cl.name]).join(".");
		var configFields : Array<ConfigField> = [];

		for( f in fields ) {
			var meta = Lambda.find(f.meta, m -> m.name == ":config");
			if( meta == null ) continue;

			if( f.access == null || !f.access.contains(AStatic) ) {
				Context.error("@:config can only be used on a static variable", f.pos);
				continue;
			}

			switch( f.kind ) {
			case FVar(t, e):
				var key = keyPrefix + "." + f.name;
				if( meta.params != null && meta.params.length > 0 ) {
					switch( meta.params[0].expr ) {
					case EConst(CString(s)):
						key = StringTools.startsWith(s, "#") ? s.substr(1) : keyPrefix + "." + s;
					default: Context.error("@:config parameter must be a constant string", meta.params[0].pos);
					}
				}
				configFields.push({ field : f, key : key, type : t, defaultValue : e });
			default:
				Context.error("@:config can only be used on a variable", f.pos);
			}
		}

		for( c in configFields ) {
			var f = c.field;
			var name = f.name;

			if( c.type == null ) {
				Context.error("@:config variable must have an explicit type", f.pos);
				continue;
			}

			var t = c.type;
			var key = c.key;
			var defaultValue = c.defaultValue ?? macro null;

			// The value isn't stored in the class anymore, it only lives in the config
			f.kind = FProp("get", "set", t, null);

			fields.push({
				name : "get_" + name,
				access : [AStatic],
				pos : f.pos,
				kind : FFun({
					args : [],
					ret : t,
					expr : macro return hide.Ide.inst.currentConfig.get($v{key}, $defaultValue),
				}),
			});

			fields.push({
				name : "set_" + name,
				access : [AStatic],
				pos : f.pos,
				kind : FFun({
					args : [{ name : "value", type : t }],
					ret : t,
					expr : macro {
						hide.Ide.inst.currentConfig.set($v{key}, value);
						return value;
					},
				}),
			});
		}

		return fields;
	}

#end
}
