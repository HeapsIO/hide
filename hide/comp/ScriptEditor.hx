package hide.comp;

typedef GlobalsDef = haxe.DynamicAccess<{
	var globals : haxe.DynamicAccess<String>;
	var context : String;
	var events : String;
	var evalTo : String;
	var cdbEnums : Array<String>;
}>;

class ScriptChecker {

	static var TYPES_SAVE = new Map();
	static var ERROR_SAVE = new Map();
	var ide : hide.Ide;
	var apiFiles : Array<String>;
	var config : hide.Config;
	var documentName : String;
	var constants : Map<String,Dynamic>;
	var evalTo : String;
	public var checker(default,null) : hscript.Checker;

	public function new( config : hide.Config, documentName : String, ?constants : Map<String,Dynamic> ) {
		this.config = config;
		this.documentName = documentName;
		this.constants = constants == null ? new Map() : constants;
		ide = hide.Ide.inst;
		apiFiles = config.get("script.api.files");
		reload();
	}

	public function reload() {
		checker = new hscript.Checker();
		checker.allowAsync = true;

		if( apiFiles != null && apiFiles.length >= 0 ) {
			var types = TYPES_SAVE.get(apiFiles.join(";"));
			if( types == null ) {
				types = new hscript.Checker.CheckerTypes();
				for( f in apiFiles ) {
					var content = try sys.io.File.getContent(ide.getPath(f)) catch( e : Dynamic ) { error(""+e); continue; };
					types.addXmlApi(Xml.parse(content).firstElement());
				}
				TYPES_SAVE.set(apiFiles.join(";"), types);
			}
			checker.types = types;
		}

		var parts = documentName.split(".");
		var apis = [];
		while( parts.length > 0 ) {
			var path = parts.join(".");
			parts.pop();
			var config = config.get("script.api");
			if( config == null ) continue;
			var api = (config : GlobalsDef).get(path);
			if( api == null ) continue;
			apis.unshift(api);
		}

		var cdbPack : String = config.get("script.cdbPackage");
		var context = null;
		for( api in apis ) {
			for( f in api.globals.keys() ) {
				var tname = api.globals.get(f);
				if( tname == null ) {
					checker.removeGlobal(f);
					continue;
				}
				var t = checker.types.resolve(tname);
				if( t == null ) {
					var path = tname.split(".");
					var fields = [];
					while( path.length > 0 ) {
						var name = path.join(".");
						if( constants.exists(name) ) {
							var value : Dynamic = constants.get(name);
							for( f in fields )
								value = Reflect.field(value, f);
							t = typeFromValue(value);
							if( t == null ) t = TAnon([]);
						}
						fields.unshift(path.pop());
					}
				}
				if( t == null ) {
					error('Global type $tname not found in $apiFiles ($f)');
					continue;
				}
				checker.setGlobal(f, t);
			}

			if( api.context != null )
				context = api.context;

			if( api.events != null ) {
				for( f in getFields(api.events) )
					checker.setEvent(f.name, f.t);
			}

			if( api.cdbEnums != null ) {
				for( c in api.cdbEnums ) {
					for( s in ide.database.sheets ) {
						if( s.name != c ) continue;
						var name = s.name.charAt(0).toUpperCase() + s.name.substr(1);
						var kname = name+"Kind";
						if( cdbPack != "" ) kname = cdbPack + "." + kname;
						var kind = checker.types.resolve(kname);
						if( kind == null )
							kind = TEnum({ name : kname, params : [], constructors : new Map() },[]);
						var cl : hscript.Checker.CClass = {
							name : name,
							params : [],
							fields : new Map(),
							statics : new Map()
						};
						for( o in s.all ) {
							var id = o.id;
							if( id == null || id == "" ) continue;
							cl.fields.set(id, { name : id, params : [], t : kind, isPublic: true, complete : true });
						}
						checker.setGlobal(name, TInst(cl,[]));
					}
				}
			}

			if( api.evalTo != null )
				this.evalTo = api.evalTo;
		}
		if( context != null ) {
			var fields = getFields(context);
			for( f in fields )
				checker.setGlobal(f.name, f.t);
		}
	}

	function getFields( tpath : String ) {
		var t = checker.types.resolve(tpath);
		if( t == null )
			error("Missing type "+tpath);
		var fl = checker.getFields(t);
		if( fl == null )
			error(tpath+" context is not a class");
		return fl;
	}

	function error( msg : String ) {
		if( !ERROR_SAVE.exists(msg) ) {
			ERROR_SAVE.set(msg,true);
			ide.error(msg);
		}
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
			return checker.types.resolve(Type.getClassName(c),[]);
		case TEnum(e):
			return checker.types.resolve(Type.getEnumName(e),[]);
		case TFunction, TUnknown:
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

class ScriptEditor extends CodeEditor {

	static var INIT_DONE = false;
	var checker : ScriptChecker;
	var checkTypes : Bool;

	public function new( script : String, ?checker : ScriptChecker, ?parent : Element, ?root : Element, ?lang ) {
		if( !INIT_DONE ) {
			INIT_DONE = true;
			(monaco.Languages : Dynamic).typescript.javascriptDefaults.setCompilerOptions({ noLib: true, allowNonTsExtensions: true }); // disable js stdlib completion
			monaco.Languages.registerCompletionItemProvider("javascript", {
				triggerCharacters : ["."],
				provideCompletionItems : function(model,position,_,_) {
					var comp : ScriptEditor = (model : Dynamic).__comp__;
			        var code = model.getValueInRange({startLineNumber: 1, startColumn: 1, endLineNumber: position.lineNumber, endColumn: position.column});
					return comp.getCompletion(code.length);
				}
			});
		}
		super(script, lang, parent,root);
		if( checker == null ) {
			checker = new ScriptChecker(new hide.Config(),"");
			checkTypes = false;
		} else {
			var files = @:privateAccess checker.apiFiles;
			if( files != null ) {
				for( f in files )
					ide.fileWatcher.register(f, function() {
						@:privateAccess ScriptChecker.TYPES_SAVE = [];
						haxe.Timer.delay(function() { checker.reload(); doCheckScript(); }, 100);
					}, root);
			}
		}
		this.checker = checker;
		onChanged = doCheckScript;
		haxe.Timer.delay(function() doCheckScript(), 0);
	}

	function getCompletion( position : Int ) : Array<monaco.Languages.CompletionItem> {
		var script = code.substr(0,position);
		var vars = checker.checker.getGlobals();
		if( script.charCodeAt(script.length-1) == ".".code ) {
			vars = [];
			var t = checker.getCompletion(script);
			if( t != null ) {
				switch( checker.checker.follow(t) ) {
				case TInst(c,args):
					for( f in c.fields ) {
						if( !f.isPublic || !f.complete ) continue;
						var name = f.name;
						var t = f.t;
						if( StringTools.startsWith(name,"a_") ) {
							t = checker.checker.unasync(t);
							name = name.substr(2);
						}
						vars.set(name, t);
					}
				case TAnon(fields):
					for( f in fields )
						vars.set(f.name, f.t);
				default:
				}
			}
		}
		var checker = checker.checker;
		return [for( k in vars.keys() ) {
			var t = vars.get(k);
			if( StringTools.startsWith(k,"a_") ) {
				t = checker.unasync(t);
				k = k.substr(2);
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

}
