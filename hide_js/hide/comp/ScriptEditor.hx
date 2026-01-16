package hide.comp;
import hscript.Checker;

typedef GlobalsDef = haxe.DynamicAccess<{
	var globals : haxe.DynamicAccess<String>;
	var context : String;
	var contexts : Array<String>;
	var events : String;
	var evalTo : String;
	var allowGlobalsDefine : Null<Bool>;
	var cdbEnums : Array<String>;
	var publicFields : Bool;
	var parentScripts : Array<String>;
}>;

class ScriptCache {

	var content : Map<String,Bool> = [];
	var configSign : String;
	public var files : Array<String>;
	public var apiHash : String;
	public var types : hscript.Checker.CheckerTypes;

	public function new() {
	}

	public function loadConfig( sign : String ) {
		this.configSign = sign;
		var key = hide.Ide.inst.localStorage.getItem("script_cache_key");
		if( key == configSign ) {
			var values = hide.Ide.inst.localStorage.getItem("script_cache_val").split(";");
			for( v in values )
				content.set(v,true);
		}
	}

	public function loadFiles( files : Array<String> ) {
		var hash = getFilesHash(files);
		if( hash == apiHash ) return;
		apiHash = hash;
		this.files = files;
		types = new hscript.Checker.CheckerTypes();
		if( files != null ) {
			var ide = hide.Ide.inst;
			for( f in files ) {
				var path = ide.getPath(f);
				var content = try sys.io.File.getContent(path) catch( e : Dynamic ) { @:privateAccess ScriptChecker.error(""+e); continue; };
				types.addXmlApi(Xml.parse(content).firstElement());
				ide.fileWatcher.register(f, function() {
					haxe.Timer.delay(() -> {
						onApiFileChange();
						loadFiles(files);
					}, 100);
				});
			}
		}
	}

	public function getResult( hash : String ) {
		return content.get(hash);
	}

	public function setResult( hash : String, b : Bool ) {
		if( content.get(hash) == b ) return;
		content.set(hash, b);
		var all = [];
		for( key => b in content ) {
			if( b )
				all.push(key);
		}
		hide.Ide.inst.localStorage.setItem("script_cache_key", configSign);
		hide.Ide.inst.localStorage.setItem("script_cache_val", all.join(";"));
	}

	static var CONFIG_HASH = null;
	static var LAST_API = null;
	static var LAST_FILES = null;
	static var CHECK_CACHE : ScriptCache;

	static function hashString( str : String ) {
		return haxe.crypto.Md5.encode(str);
	}

	static function getFilesHash( files : Array<String> ) {
		var ide = hide.Ide.inst;
		var hashes = [];
		for( f in files ) {
			var path = ide.getPath(f);
			hashes.push(path+":"+sys.FileSystem.stat(path).mtime.getTime());
		}
		return hashString(hashes.join(","));
	}

	static function onApiFileChange() {
		CONFIG_HASH = null;
		LAST_API = null;
		LAST_FILES = null;
		LAST_API_FILES = null;
		LAST_API_TYPES = null;
	}

	static function loadCache( config : hide.Config ) {
		var api = config.get("script.api");
		var apiFiles : Array<String> = config.get("script.api.files");
		if( api != LAST_API || apiFiles != LAST_FILES || CHECK_CACHE == null ) {
			LAST_API = api;
			LAST_FILES = apiFiles;
			var hash = hashString(getFilesHash(apiFiles) + haxe.Json.stringify(api));
			if( hash != CONFIG_HASH ) {
				// CDB has a single configuration
				CONFIG_HASH = hash;
				CHECK_CACHE = new ScriptCache();
				CHECK_CACHE.loadConfig(hash);
			}
		}
		return CHECK_CACHE;
	}

	public static function getCachedResult( config : hide.Config, documentName : String, constants : Map<String,Dynamic>, code : String ) : Bool {
		var cache = loadCache(config);
		var signature = hashString(code+":"+documentName+":"+haxe.Json.stringify(constants));
		var error : Null<Bool> = cache.getResult(signature);
		if( error == null ) {
			var chk = new ScriptChecker(config, documentName, constants);
			error = chk.check(code) != null;
			cache.setResult(signature, error);
		}
		return error;
	}

	static var TYPES_SAVE = new Map();
	static var LAST_API_FILES = null;
	static var LAST_API_TYPES = null;

	public static function loadApiFiles( config : hide.Config ) {
		var files = config.get("script.api.files");
		if( files != null && (files != LAST_API_FILES || LAST_API_TYPES == null) ) {
			var key = files.join(";");
			var types = TYPES_SAVE.get(key);
			if( types == null ) {
				types = new ScriptCache();
				types.loadFiles(files);
				TYPES_SAVE.set(key,types);
			}
			LAST_API_FILES = files;
			LAST_API_TYPES = types;
		}
		return LAST_API_TYPES;
	}

}

class ScriptChecker {

	static var ERROR_SAVE = new Map();
	static var TYPE_CHECK_HOOKS : Array<ScriptChecker->Void> = [];
	var ide : hide.Ide;
	var api : ScriptCache;
	var checkEvents : Bool;
	public var config : hide.Config;
	public var documentName : String;
	public var constants : Map<String,Dynamic>;
	public var evalTo : String;
	public var checker(default,null) : hscript.Checker;
	public var cdbEnums : Array<String>;
	public var defaultPublicFields : Bool = false;
	var initDone = false;
	var apiHash : String;

	public function new( config : hide.Config, documentName : String, ?constants : Map<String,Dynamic> ) {
		this.config = config;
		this.documentName = documentName;
		this.constants = constants == null ? new Map() : constants;
		ide = hide.Ide.inst;
		api = ScriptCache.loadApiFiles(config);
		initTypes();
	}

	function initTypes() {
		if( api == null || apiHash == api.apiHash )
			return false;
		apiHash = api.apiHash;
		checker = new hscript.Checker();
		checker.allowAsync = true;
		checker.types = api.types;
		initDone = false;

		var mfields = new Map<String, CField>();
		inline function field(name,t,r,?r2) {
			mfields.set(name, {
				name : name,
				t : r2 == null ? TFun([{ name : "v", t : t, opt : false }], r) : TFun([{ name : "v1", t: t, opt : false },{ name : "v2", t : r, opt : false }],r2),
				isPublic : true,
				complete : true,
				canWrite : false,
				params : [],
			});
		}
		field("ceil",TFloat,TInt);
		field("floor",TFloat,TInt);
		field("round",TFloat,TInt);
		field("sqrt",TFloat,TInt);
		field("abs",TFloat,TFloat);
		field("pow",TFloat,TFloat,TFloat);
		@:privateAccess checker.setGlobal("Math", TInst({
			name : "Math",
			fields : mfields,
			statics : [],
			params : [],
		},[]));

		var tstring = checker.types.resolve("String");
		if( tstring == null ) {
			var cstring = checker.types.defineClass("String");
			tstring = TInst(cstring,[]);
		}
		var _tarray = checker.types.resolve("Array");
		if( _tarray == null ) {
			var carray = checker.types.defineClass("Array");
			_tarray = TInst(carray,[]);
		}
		var carray = switch( _tarray ) { case TInst(c,_): c; default: throw "assert"; }
		function tarray(t) return TInst(carray,[t]);
		function mkType(name,t) return TType({name:name,params:[],t:t},[]);

		var skind = new Map();
		for( s in ide.database.sheets ) {
			if( s.idCol != null )
				skind.set(s.name, addCDBEnum(s.name.split("@").join(".")));
		}

		var cdefs = new Map();
		for( s in ide.database.sheets ) {
			var cdef : CClass = {
				name : hide.comp.cdb.Formulas.getTypeName(s),
				fields : [],
				statics : [],
				params : [],
			};
			cdefs.set(s.name, cdef);
			if( s.getParent() != null )
				continue;
			var afields = [
				{
					name : "all",
					t : tarray(TInst(cdef,[])),
					opt : false,
				}
			];
			if( s.idCol != null ) {
				var tkind = skind.get(s.name);
				afields.push({
					name : "resolve",
					t : TFun([{t:tstring,name:"id",opt:false}],TInst(cdef,[])),
					opt : false,
				});
				for( v in s.getLines() ) {
					var id = Reflect.field(v, s.idCol.name);
					if( id != null && id != "" )
						afields.push({ name : id, t : tkind, opt : false });
				}
			}
			var t = mkType("#"+cdef.name,TAnon(afields));
			checker.setGlobal(cdef.name, t);
		}

		function defineEnum(name,values:Array<String>) {
			values = [for( v in values ) hide.comp.cdb.Formulas.toIdent(v)];
			var t = TEnum({ name : name, params : [], constructors : [for( v in values ) {name:v}] },[]);
			var tvalues = [for( v in values ) {name:v,t:t,opt:false}];
			checker.setGlobal(name,mkType("#"+name,TAnon(tvalues)));
			return t;
		}

		for( s in ide.database.sheets ) {
			var cdef = cdefs.get(s.name);
			inline function addField(name,t) {
				cdef.fields.set(name, { t : t, name : name, isPublic : true, complete : true, canWrite : false, params : [] });
			}
			for( c in s.columns ) {
				var t = switch( c.type ) {
				case TId: skind.get(s.name);
				case TInt, TColor: TInt;
				case TEnum(values):
					defineEnum(cdef.name+"_"+c.name, values);
				case TFlags(flags):
					TAnon([for(f in flags) { name : f, t : TBool, opt : true }]);
				case TFloat: TFloat;
				case TBool: TBool;
				case TDynamic: TDynamic;
				case TRef(other): TInst(cdefs.get(other),[]);
				case TCustom(_), TImage, TLayer(_), TTileLayer, TTilePos, TGradient, TCurve: null;
				case TList, TProperties, TPolymorph:
					var t = TInst(cdefs.get(s.name+"@"+c.name),[]);
					c.type == TList ? @:privateAccess checker.types.getType("Array",[t]) : t;
				case TString, TFile, TGuid:
					tstring;
				}
				if( t == null ) continue;
				addField(c.name,t);
			}
			if( s.props.hasGroup ) {
				var groups = [];
				for( s in s.separators ) {
					if( s.level == null && s.title != null ) {
						if( s.index != 0 && groups.length == 0 ) groups.push("None");
						groups.push(s.title);
					}
				}
				var t = defineEnum(cdef.name+"_group",groups);
				addField("group",t);
			}
			if( s.props.hasIndex )
				addField("index",TInt);
			checker.types.defineClass(cdef.name, cdef);
		}

		onInitTypes();

		return true;
	}

	public dynamic function onInitTypes() {}

	function resolveApis( path : String ) {
		var config : GlobalsDef = config.get("script.api");
		if( config == null ) return [];
		var arr = [];
		var obj = constants.get(path);
		for( f in config.keys() ) {
			var pattern = f;
			if( !StringTools.startsWith(pattern, path) )
				continue;
			var r = ~/\[([A-Za-z0-9_\.]+)=([^\]]+?)\]$/;
			var ok = true;
			while( r.match(pattern) ) {
				var req = r.matched(2);
				var val : Dynamic = obj;
				var fields = r.matched(1);
				for( f in fields.split(".") )
					val = Reflect.field(val, f);
				if( fields == "group" )
					val = constants.get("cdb.groupID");
				if( Std.string(val) != req ) {
					pattern = null;
					break;
				}
				pattern = r.matchedLeft();
			}
			if( pattern == path )
				arr.push(config.get(f));
		}
		return arr;
	}

	static var NO_VALUE : Dynamic = [];

	function resolveConstantValue( name : String, ?constants ) : Dynamic {

		if( constants == null )
			constants = this.constants;

		var parts = name.split("+");
		if( parts.length > 1 ) {
			var cur : Dynamic = NO_VALUE;
			for( p in parts ) {
				var v : Dynamic = resolveConstantValue(p);
				if( v == NO_VALUE ) continue;
				if( cur == NO_VALUE || cur == null ) {
					cur = Std.isOfType(v,Array) ? (v:Array<Dynamic>).copy() : Reflect.isObject(v) ? Reflect.copy(v) : v;
					continue;
				}
				if( Std.isOfType(cur,Array) && Std.isOfType(v,Array) ) {
					for( val in (v:Array<Dynamic>) )
						(cur:Array<Dynamic>).push(val);
				} else if( Reflect.isObject(cur) && Reflect.isObject(v) ) {
					for( f in Reflect.fields(v) )
						Reflect.setField(cur,f,Reflect.field(v,f));
				}
			}
			return cur;
		}

		var extra = name.indexOf("@");
		if( extra > 0 ) {
			var path = name.substr(extra+1);
			name = name.substr(0, extra);
			var value : Dynamic = resolveConstantValue(name,constants);
			if( value == null || value == NO_VALUE )
				return value;
			var sheet = ide.database.getSheet(name.split(".")[1]);
			if( sheet == null || sheet.idCol == null )
				return NO_VALUE;
			var obj = null;
			for( line in sheet.getLines() ) {
				if( Reflect.field(line,sheet.idCol.name) == value ) {
					obj = line;
					break;
				}
			}
			if( obj == null )
				return null;
			var constants = new Map();
			var prefix = "cdb."+sheet.name;
			constants.set(prefix, obj);
			return resolveConstantValue(prefix+"."+path, constants);
		}

		var path = name.split(".");
		var fields = [];
		while( path.length > 0 ) {
			var name = path.join(".");
			if( constants.exists(name) ) {
				var value : Dynamic = constants.get(name);
				for( f in fields )
					value = Reflect.field(value, f);
				return value;
			}
			fields.unshift(path.pop());
		}
		return NO_VALUE;
	}

	function init() {
		initTypes();
		if( initDone ) return;
		initDone = true;

		var parts = documentName.split(".");
		var apis = [];
		while( parts.length > 0 ) {
			var path = parts.join(".");
			parts.pop();
			for( a in resolveApis(path) )
				apis.unshift(a);
		}

		var cdbPack : String = config.get("script.cdbPackage");
		var contexts = [];
		var publicFields = defaultPublicFields;
		var allowGlobalsDefine = false;
		var parentScripts = null;
		checkEvents = false;
		cdbEnums = [];

		for( api in apis ) {
			for( f in api.globals.keys() ) {
				var tname = api.globals.get(f);
				if( tname == null ) {
					checker.removeGlobal(f);
					continue;
				}
				var isClass = tname.charCodeAt(0) == '#'.code;
				if( isClass ) tname = tname.substr(1);
				var t = checker.types.resolve(tname);
				if( t == null ) {
					var value : Dynamic = resolveConstantValue(tname);
					if( value != NO_VALUE ) {
						t = typeFromValue(value);
						if( t == null ) t = TAnon([]);
					}
				}
				if( t == null ) {
					error('Global type $tname not found in ${this.api.files} ($f)');
					continue;
				}
				if( isClass ) {
					switch( t ) {
					case TEnum(e,_):
						t = TAnon([for( c in e.constructors ) { name : c.name, opt : false, t : c.args == null ? t : TFun(c.args,t) }]);
					case TInst(c,[]):
						t = TAnon([for( f in c.statics ) if( f.isPublic || (api.publicFields != true && f.t.match(TFun(_))) ) { name : f.name, opt : false, t : f.t }]);
					default:
						error('Cannot process class type $tname');
					}
				}
				checker.setGlobal(f, t);
			}

			if( api.context != null ) {
				contexts = [api.context];
				publicFields = api.publicFields;
			}

			if( api.contexts != null ) {
				contexts = api.contexts;
				publicFields = api.publicFields;
			}

			if( api.allowGlobalsDefine != null )
				allowGlobalsDefine = api.allowGlobalsDefine;

			if( api.events != null ) {
				for( f in getFields(api.events) )
					checker.setEvent(f.name, f.t);
				checkEvents = true;
			}

			if( api.cdbEnums != null ) {
				for( c in api.cdbEnums )
					addCDBEnum(c, cdbPack);
			}

			if( api.parentScripts != null )
				parentScripts = api.parentScripts;

			if( api.evalTo != null )
				this.evalTo = api.evalTo;
		}
		for( context in contexts ) {
			var ctx = checker.types.resolve(context);
			if( ctx == null )
				error(context+" is not defined");
			else {
				switch( ctx ) {
				case TInst(c,_):
					var cc = c;
					while( true ) {
						if( !publicFields ) {
							for( f in cc.fields ) if( f.t.match(TFun(_)) ) f.isPublic = true; // allow access to private methods
						}
						if( cc.superClass == null ) break;
						cc = switch( cc.superClass ) {
						case TInst(c,_): c;
						default: throw "assert";
						}
					}
					checker.setGlobals(c);
				default: error(context+" is not a class");
				}
			}
		}
		checker.allowUntypedMeta = true;
		checker.allowGlobalsDefine = allowGlobalsDefine;
		for( c in TYPE_CHECK_HOOKS )
			c(this);
		if( parentScripts != null ) {
			for( script in parentScripts ) {
				var value : Dynamic = resolveConstantValue(script);
				if( value == NO_VALUE || value == null )
					continue;
				try {
					var parser = makeParser();
					var expr = parser.parseString(value,"");
					checker.check(expr);
					for( v => t in @:privateAccess checker.locals )
						checker.setGlobal(v, t);
				} catch( e : Dynamic ) {
					// ignore parent script errors
				}
			}
		}
	}

	function getFields( tpath : String ) {
		var t = checker.types.resolve(tpath);
		if( t == null )
			error("Missing type "+tpath);
		var fl = checker.getFields(t);
		if( fl == null )
			error(tpath+" is not a class");
		return fl;
	}

	static function error( msg : String ) {
		if( !ERROR_SAVE.exists(msg) ) {
			ERROR_SAVE.set(msg,true);
			hide.Ide.inst.error(msg);
		}
	}

	static var buf = new StringBuf();
	public function addCDBEnum( name : String, ?cdbPack : String ) {
		var path = name.split(".");
		var sname = path.join("@");
		var objPath = null;
		var isOtherSheet = false;
		if( path.length > 1 ) { // might be a scoped id
			var objID = this.constants.get("cdb.objID");
			objPath = objID == null ? [] : objID.split(":");
			isOtherSheet = this.constants.get("cdb."+path[0]) == null;
		}

		var s = ide.database.getSheet(sname);
		if (s != null) {
			var name = path[path.length - 1];
			name = name.charAt(0).toUpperCase() + name.substr(1);
			var kname = path.join("_")+"Kind";
			kname = kname.charAt(0).toUpperCase() + kname.substr(1);
			if( cdbPack != null && cdbPack.length > 0 )
				kname = cdbPack + "." + kname;
			var kind = checker.types.resolve(kname);
			if( kind == null )
				kind = TEnum({ name : kname, params : [], constructors : [] },[]);
			var cl : hscript.Checker.CClass = {
				name : name,
				params : [],
				fields : new Map(),
				statics : new Map()
			};
			var refPath = s.idCol.scope == null ? null : objPath.slice(0, s.idCol.scope).join(":")+":";
			for( o in s.all ) {
				var id = o.id;
				if( id == null || id.length == 0 ) continue;
				if( refPath != null ) {
					#if haxe5
						buf.clear();
					#else
						@:privateAccess buf.b = "";
					#end
					if( isOtherSheet ) {
						buf.addSub(id, id.lastIndexOf(':') + 1);
					}
					else {
						if( !StringTools.startsWith(id, refPath) ) continue;
						buf.addSub(id, refPath.length);
					}
					id = buf.toString();
				}
				cl.fields.set(id, { name : id, params : [], canWrite : false, t : kind, isPublic: true, complete : true });
			}
			checker.setGlobal(name, TInst(cl,[]));
			if (cdbEnums == null)
				cdbEnums = [];
			cdbEnums.push(name);
			return kind;
		}

		return null;
	}

	function typeFromValue( value : Dynamic ) : hscript.Checker.TType {
		switch( std.Type.typeof(value) ) {
		case TNull:
			return null;
		case TInt:
			return TInt;
		case TFloat:
			return TFloat;
		case TBool:
			return TBool;
		case TObject:
			var fields = [];
			for( f in Reflect.fields(value) ) {
				var t = typeFromValue(Reflect.field(value,f));
				if( t == null ) continue;
				fields.push({ name : f, t : t, opt : false });
			}
			return TAnon(fields);
		case TClass(c):
			var name = Type.getClassName(c);
			var params = [];
			if( name == "Array" ) {
				var t = typeFromValue((cast value : Array<Dynamic>)[0]);
				if( t == null ) t = TMono({ r : null });
				params = [t];
			}
			return checker.types.resolve(name,params);
		case TEnum(e):
			return checker.types.resolve(Type.getEnumName(e),[]);
		default:
		}
		return null;
	}

	public function makeParser() {
		var parser = new hscript.Parser();
		parser.allowMetadata = true;
		parser.allowTypes = true;
		parser.allowJSON = true;
		return parser;
	}

	public function getCompletion( script : String ) {
		var parser = makeParser();
		parser.resumeErrors = true;
		var expr = parser.parseString(script,""); // should not error
		try {
			init();
			var et = checker.check(expr,null,true);
			return null;
		} catch( e : hscript.Checker.Completion ) {
			// ignore
			return e.t;
		}
	}

	public function check( script : String, checkTypes = true ) {
		var parser = makeParser();
		try {
		var expr = parser.parseString(script, "");

			if( checkTypes )
				init();

			if( checkEvents ) {
				function checkRec(e:hscript.Expr) {
					switch( e.e ) {
					case EFunction(_,_,name,_):
						if( name != null && StringTools.startsWith(name,"on") && name.charCodeAt(2) > 'A'.code && name.charCodeAt(2) < 'Z'.code && @:privateAccess !checker.events.exists(name) )
							@:privateAccess checker.error('Unknown event $name', e);
					default:
						hscript.Tools.iter(e, checkRec);
					}
				}
				checkRec(expr);
			}

			if( checkTypes ) {
				var et = checker.check(expr);
				if( evalTo != null ) {
					var t = checker.types.resolve(evalTo);
					if( t == null ) {
						error('EvalTo type $evalTo not found');
						return null;
					}
					checker.unify(et, t, expr);
				}
			}
			return null;
		} catch( e : hscript.Expr.Error ) {
			return e;
		}
	}

}

#if !hl
class ScriptEditor extends CodeEditor {

	public var checker(default,null) : ScriptChecker;
	var checkTypes : Bool;

	public function new( script : String, ?checker : ScriptChecker, ?parent : Element, ?root : Element, ?lang = "javascript" ) {
		super(script, lang, parent,root);
		if( checker == null ) {
			checker = new ScriptChecker(new hide.Config(),"");
			checkTypes = false;
		} else {
			var files = @:privateAccess checker.api.files;
			if( files != null ) {
				for( f in files )
					ide.fileWatcher.register(f, function() haxe.Timer.delay(doCheckScript,100), root);
			}
		}
		this.checker = checker;
		onChanged = doCheckScript;
		initCompletion(["."]);
		haxe.Timer.delay(function() doCheckScript(), 0);
	}

	override function getCompletion( position : Int ) : Array<monaco.Languages.CompletionItem> {
		var script = code.substr(0,position);
		var vars : Map<String,TType>;
		if( script.charCodeAt(script.length-1) == ".".code ) {
			vars = [];
			var t = checker.getCompletion(script);
			if( t != null ) {
				var fields = checker.checker.getFields(t);
				for( f in fields )
					vars.set(f.name, f.t);
			}
		} else {
			vars = checker.checker.getGlobals();
			for( ev => t in @:privateAccess checker.checker.events ) {
				vars.set(ev,t);
				switch( t ) {
				case TFun(args,_):
					vars.set("function "+ev+"("+[for( a in args ) a.name].join(",")+") {\n}", t);
				default:
				}
			}
		}
		var checker = checker.checker;
		return [for( k in vars.keys() ) {
			var t = vars.get(k);
			if( StringTools.startsWith(k,"a_") ) {
				var t2 = checker.unasync(t);
				if( t2 != null ) {
					t = t2;
					k = k.substr(2);
				}
			}
			var isFun = checker.follow(t).match(TFun(_));
			if( isFun ) {
				{
					kind : Method,
					label : k,
					detail : hscript.Checker.typeStr(t),
					commitCharacters: ["("],
				}
			} else {
				{
					kind : Field,
					label : k,
					detail : hscript.Checker.typeStr(t),
				}
			}
		}];
	}

	public function doCheckScript() {
		var script = code;
		var error = checker.check(script, checkTypes);
		if( error == null )
			clearError();
		else
			setError(hscript.Printer.errorToString(error), error.line, error.pmin, error.pmax);
	}

	public static function register( cl : Class<Dynamic> ) : Bool {
		@:privateAccess ScriptChecker.TYPE_CHECK_HOOKS.push(function(checker) {
			Type.createInstance(cl,[checker]);
		});
		return true;
	}

}
#end