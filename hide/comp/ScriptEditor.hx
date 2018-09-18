package hide.comp;

typedef GlobalsDef = haxe.DynamicAccess<{
	var globals : haxe.DynamicAccess<String>;
	var context : String;
	var cdbEnums : Bool;
}>;

class ScriptChecker {

	static var TYPES_SAVE = new Map();
	public var checker : hscript.Checker;

	public function new( config : hide.Config, documentName : String ) {

		checker = new hscript.Checker();

		var ide = hide.Ide.inst;
		var files : Array<String> = config.get("script.api.files");
		if( files.length >= 0 ) {
			var types = TYPES_SAVE.get(files.join(";"));
			if( types == null ) {
				types = new hscript.Checker.CheckerTypes();
				for( f in files ) {
					// TODO : reload + recheck script when modified
					var content = try sys.io.File.getContent(ide.getPath(f)) catch( e : Dynamic ) { ide.error(e); continue; };
					types.addXmlApi(Xml.parse(content).firstElement());
				}
				TYPES_SAVE.set(files.join(";"), types);
			}
			checker.types = types;
		}

		var parts = documentName.split("/");
		var cdbPack : String = config.get("script.cdbPackage");
		while( parts.length > 0 ) {
			var path = parts.join("/");
			parts.pop();
			var api = (config.get("script.api") : GlobalsDef).get(path);
			if( api == null ) continue;

			for( f in api.globals.keys() ) {
				var tname = api.globals.get(f);
				var t = checker.types.resolve(tname);
				if( t == null ) ide.error('Global type $tname not found in $files ($f)');
				checker.setGlobal(f, t);
			}

			if( api.context != null ) {
				var t = checker.types.resolve(api.context);
				if( t == null ) ide.error("Missing context type "+api.context);
				while( t != null )
					switch (t) {
					case TInst(c, args):
						for( fname in c.fields.keys() ) {
							var f = c.fields.get(fname);
							checker.setGlobal(f.name, f.t);
						}
						t = c.superClass;
					default:
						ide.error(api.context+" context is not a class");
					}
			}

			if( api.cdbEnums ) {
				for( s in ide.database.sheets ) {
					if( s.props.hide ) continue;
					for( c in s.columns )
						if( c.type == TId ) {
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
							for( o in s.getLines() ) {
								var id = Reflect.field(o, c.name);
								if( id == null || id == "" ) continue;
								cl.fields.set(id, { name : id, params : [], t : kind, isPublic: true });
							}
							checker.setGlobal(name, TInst(cl,[]));
						}
				}
			}
		}
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

class ScriptEditor extends Component {

	static var INIT_DONE = false;

	var editor : monaco.Editor;
	var errorMessage : Element;
	var checker : ScriptChecker;
	var currrentDecos : Array<String> = [];
	var config : hide.Config;
	public var documentName : String;
	public var script(get,never) : String;
	public var checkTypes : Bool = false;

	public function new( documentName : String, script : String, config, ?parent : Element, ?root : Element ) {
		super(parent,root);
		this.config = config;
		this.documentName = documentName;

		if( !INIT_DONE ) {
			INIT_DONE = true;
			monaco.Languages.registerCompletionItemProvider("javascript", {
				provideCompletionItems : function(model,position,_,_) {
					var comp : ScriptEditor = (model : Dynamic).__comp__;
					return comp.getCompletion(position);
				}
			});
		}

		var root = element;
		root.addClass("scripteditor");
		root.on("keydown", function(e) e.stopPropagation());

		editor = monaco.Editor.create(root[0],{
			value : script,
			language : "javascript",
			automaticLayout : true,
			wordWrap : true,
			minimap : { enabled : false },
			theme : "vs-dark",
		});
		var model = editor.getModel();
		(model : Dynamic).__comp__ = this;
		model.updateOptions({ insertSpaces:false, trimAutoWhitespace:true });
		editor.onDidChangeModelContent(doCheckScript);
		editor.addCommand(monaco.KeyCode.KEY_S | monaco.KeyMod.CtrlCmd, function() { clearSpaces(); onSave(); });
		errorMessage = new Element('<div class="scriptErrorMessage"></div>').appendTo(root).hide();
		checker = new ScriptChecker(config, documentName);
		haxe.Timer.delay(function() doCheckScript(), 0);
	}

	function clearSpaces() {
		var script = script;
		var newScript = [for( l in StringTools.trim(script).split("\n") ) StringTools.rtrim(l)].join("\n");
		if( newScript != script ) {
			var p = editor.getPosition();
			setScript(newScript);
			editor.setPosition(p);
		}
	}

	function get_script() {
		return editor.getValue({preserveBOM:true});
	}

	public function setScript( script : String ) {
		editor.setValue(script);
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

	function doCheckScript() {
		var script = script;
		var error = checker.check(script, checkTypes);
		if( error == null ) {
			if( currrentDecos.length != 0 )
				currrentDecos = editor.deltaDecorations(currrentDecos,[]);
			errorMessage.hide();
		} else {
			var linePos = script.substr(0,error.pmin).lastIndexOf("\n");
			//trace(e, e.pmin, e.pmax, cur.substr(e.pmin, e.pmax - e.pmin + 1), linePos);
			if( linePos < 0 ) linePos = 0 else linePos++;
			var range = new monaco.Range(error.line,error.pmin + 1 - linePos,error.line,error.pmax + 2 - linePos);
			currrentDecos = editor.deltaDecorations(currrentDecos,[
				{ range : range, options : { inlineClassName: "scriptErrorContentLine", isWholeLine : true } },
				{ range : range, options : { linesDecorationsClassName: "scriptErrorLine", inlineClassName: "scriptErrorContent" } }
			]);
			errorMessage.text(hscript.Printer.errorToString(error));
			errorMessage.show();
		}
	}

	public function focus() {
		editor.focus();
	}

	public dynamic function onSave() {
	}

}
