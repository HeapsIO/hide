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

#if !macro
@:forward(get)
abstract ReadOnlyConfig(Config) from Config {}
#end

class Config {
#if !macro

	var ide : Ide;
	var parent : Config;
	public var path(default,null) : String;
	public var source(default, null) : Dynamic = {};
	public var current : Dynamic = {};

	var prevConfig: String = null;

	static var changeCount = 0;
	var syncedChangeCount = -1;

	public function new( ?parent : Config ) {
		ide = Ide.inst;
		this.parent = parent;
		sync();
	}

	public function load( path : String ) {
		this.path = path;
		var fullPath = ide.getPath(path);
		if( sys.FileSystem.exists(fullPath) )
			source = try ide.parseJSON(sys.io.File.getContent(fullPath)) catch( e : Dynamic ) throw e+" (in "+fullPath+")";
		else
			source = {};
		changeCount++;
		sync();
	}

	public function save() {
		sync();
		saveToDisk();
	}

	function saveToDisk() {
		if( ide.readOnlyConfig ) return;
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

	#if editor_hl

	static final SAVE_DELAY = 5.0;
	static var pendingSaves : Array<Config> = [];

	var saveDelay : Float = 0.0;

	/**
		Same as `save()`, but the write to disk is delayed until `SAVE_DELAY` seconds have
		passed without any new call, or until the editor closes. Changing a lot of values in
		a row then only rewrites the file once instead of once per value.
	**/
	public function queueSave() {
		sync();
		saveDelay = SAVE_DELAY;
		if( !pendingSaves.contains(this) )
			pendingSaves.push(this);
	}

	/** Ticks the delay of every config waiting to be written, called by `Ide.update` **/
	public static function updatePendingSaves( dt : Float ) {
		var i = pendingSaves.length;
		while( i-- > 0 ) {
			var config = pendingSaves[i];
			config.saveDelay -= dt;
			if( config.saveDelay <= 0 ) {
				pendingSaves.splice(i, 1);
				config.saveToDisk();
			}
		}
	}

	/** Immediately writes every config waiting to be written, called when the editor closes **/
	public static function flushPendingSaves() {
		var configs = pendingSaves;
		pendingSaves = [];
		for( config in configs )
			config.saveToDisk();
	}

	#end

	public function sync() {
		if( parent != null ) parent.sync();
		current = {};
		if( parent != null ) merge(parent.current);
		if( source != null ) merge(source);
		syncedChangeCount = changeCount;
	}

	inline function syncIfChanged() {
		if( syncedChangeCount != changeCount )
			sync();
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
		syncIfChanged();
		var val = Reflect.field(current,key);
		if(val != null) return val;
		return defaultVal;
	}

	public function set( key : String, val : Dynamic ) {
		syncIfChanged();
		if (val == Reflect.field(current, key))
			return;
		if( val == null )
			Reflect.deleteField(source, key);
		else
			Reflect.setField(source, key, val);
		changeCount++;
		#if editor_hl
		queueSave();
		#else
		save();
		#end
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

	/**
		Load the config layers of a project, each one being the parent of the next :
		defaults (hide installation) < user (all projects) < project (shared, res/props.json) < project user
	**/
	public static function loadForProject( projectPath : String, resourcePath : String ) {
		var ide = Ide.inst;
		var hidePath = ide.appPath;

		var defaults = new Config();
		try {
			defaults.load(hidePath + "/defaultProps.json");
		}
		catch (err) {
			alert('Fatal error : Couldn\'t load ${hidePath}/defaultProps.json. Please check your hide installation.\n$err');
			Sys.exit(-1);
		}
		for( key => value in ide.defaultUserConfig )
			if( !Reflect.hasField(defaults.source, key) )
				Reflect.setField(defaults.source, key, value);
		defaults.sync();

		var user = new Config(defaults);
		if( !ide.defaultConfig )
			loadConfig(user, ide.userDataPath + "/preferences.json");
		var project = loadConfig(new Config(user), resourcePath + "/props.json");
		var projectUser = new Config(project);
		if( !ide.defaultConfig )
			loadConfig(projectUser, ide.getProjectDataPath(projectPath) + "/preferences.json");

		return {
			user : user,
			project : project,
			projectUser : projectUser,
		};
	}

	public static function loadForFile( ide : hide.tools.IdeData, path : String ) {
		var relPath = ide.makeRelative(path);
		var inResources = !haxe.io.Path.isAbsolute(relPath) && !StringTools.startsWith(relPath, "..");
		var parts = inResources ? [for( p in relPath.split("/") ) if( p != "" ) p] : [];
		var propFiles = [];
		var first = true, allowSave = false;
		while( parts.length > 0 ) {
			var pfile = ide.getPath(parts.join("/") + "/props.json");
			if( sys.FileSystem.exists(pfile) ) {
				propFiles.unshift(pfile);
				if( first ) allowSave = true;
			}
			first = false;
			parts.pop();
		}
		var parent = ide.projectUserConfig;
		for( p in propFiles ) {
			parent = new Config(parent);
			parent.load(p);
		}
		return allowSave ? parent : new Config(parent);
	}

#end

#if macro

	/** Maps every key declared with `@:config` to the `pack.Class.field` that declared it, to detect duplicates **/
	static var registeredKeys : Map<String, String> = [];

	/**
		Build macro to be used as `@:build(hide.Config.configMacro())` on a class.

		Every static variable of that class decorated with `@:config` is meant to be
		read through `hide.Ide.inst.currentConfig.get` and written in `projectUserConfig` instead of being stored
		in the class itself.

		Keys are always prefixed so they can't collide with the ones of another class :
		the prefix is `prefix` when it is given to the macro (`@:build(hide.Config.configMacro("myPrefix"))`),
		the full dot path of the class otherwise.

		By default the key of a variable is `<prefix>.<variableName>`. A custom name can be
		given to the metadata (`@:config("myName")`), which gives `<prefix>.myName`. As an
		escape hatch, a name starting with a `#` is not prefixed at all : `@:config("#myKey")`
		uses `myKey` as the full key, which is useful to read a key that already exists
		somewhere else in the config.

		Every key is checked to be unique across the whole project : two `@:config` variables
		resolving to the same key is a compilation error, because they would silently share
		their value while each declaring its own default. The check only knows about the
		variables declared through this macro, so a `#` key can still point at a raw key that
		is read with `currentConfig.get` somewhere else.
	**/
	public static function configMacro( ?prefix : String ) : Array<Field> {
		var cl = Context.getLocalClass().get();
		var fields = Context.getBuildFields();

		var classPath = cl.pack.concat([cl.name]).join(".");
		var keyPrefix = prefix ?? classPath;
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
				var owner = classPath + "." + f.name;
				var prev = registeredKeys.get(key);
				if( prev != null && prev != owner )
					Context.error('The config key "' + key + '" is already declared by ' + prev, f.pos);
				registeredKeys.set(key, owner);

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
						hide.Ide.inst.projectUserConfig.set($v{key}, value != $defaultValue ? value : null);
						return value;
					},
				}),
			});
		}

		return fields;
	}

#end
}
