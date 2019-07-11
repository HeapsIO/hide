package hide.comp;

typedef GlobalsDef = haxe.DynamicAccess<{
	var globals : haxe.DynamicAccess<String>;
	var context : String;
	var events : String;
	var cdbEnums : Array<String>;
}>;

class ScriptChecker {

	static var TYPES_SAVE = new Map();
	static var ERROR_SAVE = new Map();
	var ide : hide.Ide;
	public var checker : hscript.Checker;

	public function new( config : hide.Config, documentName : String, ?constants : Map<String,Dynamic> ) {

		checker = new hscript.Checker();
		ide = hide.Ide.inst;

		var files : Array<String> = config.get("script.api.files");
		if( files != null && files.length >= 0 ) {
			var types = TYPES_SAVE.get(files.join(";"));
			if( types == null ) {
				types = new hscript.Checker.CheckerTypes();
				for( f in files ) {
					// TODO : reload + recheck script when modified
					var content = try sys.io.File.getContent(ide.getPath(f)) catch( e : Dynamic ) { error(""+e); continue; };
					types.addXmlApi(Xml.parse(content).firstElement());
				}
				TYPES_SAVE.set(files.join(";"), types);
			}
			checker.types = types;
		}

		var parts = documentName.split(".");
		var cdbPack : String = config.get("script.cdbPackage");
		while( parts.length > 0 ) {
			var path = parts.join(".");
			parts.pop();
			var config = config.get("script.api");
			if( config == null ) continue;
			var api = (config : GlobalsDef).get(path);
			if( api == null ) continue;

			for( f in api.globals.keys() ) {
				var tname = api.globals.get(f);
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
					error('Global type $tname not found in $files ($f)');
					continue;
				}
				checker.setGlobal(f, t);
			}

			if( api.context != null ) {
				var fields = getFields(api.context);
				for( f in fields )
					checker.setGlobal(f.name, f.t);
			}

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
							cl.fields.set(id, { name : id, params : [], t : kind, isPublic: true });
						}
						checker.setGlobal(name, TInst(cl,[]));
					}
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

	public function check( script : String, checkTypes = true ) {
		var parser = new hscript.Parser();
		parser.allowMetadata = true;
		parser.allowTypes = true;
		parser.allowJSON = true;
		try {
			var expr = parser.parseString(script, "");
			if( checkTypes ) {
				checker.allowAsync = true;
				checker.check(expr);
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
				provideCompletionItems : function(model,position,_,_) {
					var comp : ScriptEditor = (model : Dynamic).__comp__;
					return comp.getCompletion(position);
				}
			});
		}
		super(script, lang, parent,root);
		if( checker == null ) {
			checker = new ScriptChecker(new hide.Config(),"");
			checkTypes = false;
		}
		this.checker = checker;
		onChanged = doCheckScript;
		haxe.Timer.delay(function() doCheckScript(), 0);
	}

	function getCompletion( position : monaco.Position ) : Array<monaco.Languages.CompletionItem> {
		var checker = checker.checker;
		var globals = checker.getGlobals();
		return [for( k in globals.keys() ) {
			var t = globals.get(k);
			if( StringTools.startsWith(k,"a_") ) {
				t = checker.unasync(t);
				k = k.substr(2);
			}
			var isFun = checker.follow(t).match(TFun(_));
			if( isFun ) {
				{
					kind : Field,
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
