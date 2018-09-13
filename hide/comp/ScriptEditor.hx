package hide.comp;

typedef GlobalsDef = haxe.DynamicAccess<{
	var globals : haxe.DynamicAccess<String>;
	var context : String;
	var cdbEnums : Bool;
}>;

class ScriptEditor extends Component {

	static var INIT_DONE = false;

	var editor : monaco.Editor;
	var errorMessage : Element;
	var checker : hscript.Checker;
	var currrentDecos : Array<String> = [];
	var props : hide.ui.Props;
	public var documentName : String;
	public var script(get,never) : String;

	public var checkScript : Bool = false;
	public var checkAsync : Bool = true;

	public function new( documentName : String, script : String, props : hide.ui.Props, ?parent : Element, ?root : Element ) {
		super(parent,root);
		this.props = props;
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
			theme : "vs-dark",
		});
		(editor.getModel() : Dynamic).__comp__ = this;
		editor.onDidChangeModelContent(doCheckScript);
		editor.addCommand(monaco.KeyCode.KEY_S | monaco.KeyMod.CtrlCmd, function() onSave());
		errorMessage = new Element('<div class="scriptErrorMessage"></div>').appendTo(root).hide();

		checker = new hscript.Checker();

		var files : Array<String> = props.get("script.api.files");
		if( files.length >= 0 ) {
			for( f in files ) {
				// TODO : reload + recheck script when modified
				var content = try sys.io.File.getContent(ide.getPath(f)) catch( e : Dynamic ) { ide.error(e); continue; };
				checker.addXmlApi(Xml.parse(content).firstElement());
			}
		}

		var parts = documentName.split("/");
		var cdbMod : String = props.get("script.cdbModule");
		while( parts.length > 0 ) {
			var path = parts.join("/");
			parts.pop();
			var api = (props.get("script.api") : GlobalsDef).get(path);
			if( api == null ) continue;

			for( f in api.globals.keys() ) {
				var tname = api.globals.get(f);
				var t = checker.resolveType(tname);
				if( t == null ) ide.error('Global type $tname not found in $files ($f)');
				checker.setGlobal(f, t);
			}

			if( api.context != null ) {
				var t = checker.resolveType(api.context);
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
							var kname = cdbMod+"."+name+"Kind";
							var kind = checker.resolveType(kname);
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

		haxe.Timer.delay(function() doCheckScript(), 0);
	}

	function get_script() {
		return editor.getValue({preserveBOM:true});
	}

	var rnd = Std.random(1000);

	function getCompletion( position : monaco.Position ) : Array<monaco.Languages.CompletionItem> {
		var globals = checker.getGlobals();
		return [for( k in globals.keys() ) {
			var t = globals.get(k);
			if( checkAsync && StringTools.startsWith(k,"a_") ) {
				t = checker.unasync(t);
				k = k.substr(2);
			}
			var isFun = checker.follow(t).match(TFun(_));
			if( isFun ) {
				{
					kind : Field,
					label : k,
					detail : checker.typeStr(t),
					commitCharacters: ["("],
				}
			} else {
				{
					kind : Field,
					label : k,
					detail : checker.typeStr(t),
				}
			}
		}];
	}

	function doCheckScript() {
		var script = script;
		try {
			var expr = new hscript.Parser().parseString(script, "");
			if( checkScript ) {
				checker.allowAsync = checkAsync;
				checker.check(expr);
			}
			if( currrentDecos.length != 0 )
				currrentDecos = editor.deltaDecorations(currrentDecos,[]);
			errorMessage.hide();
		} catch( e : hscript.Expr.Error ) {
			var linePos = script.substr(0,e.pmin).lastIndexOf("\n");
			//trace(e, e.pmin, e.pmax, cur.substr(e.pmin, e.pmax - e.pmin + 1), linePos);
			if( linePos < 0 ) linePos = 0 else linePos++;
			var range = new monaco.Range(e.line,e.pmin + 1 - linePos,e.line,e.pmax + 2 - linePos);
			currrentDecos = editor.deltaDecorations(currrentDecos,[
				{ range : range, options : { inlineClassName: "scriptErrorContentLine", isWholeLine : true } },
				{ range : range, options : { linesDecorationsClassName: "scriptErrorLine", inlineClassName: "scriptErrorContent" } }
			]);
			errorMessage.text(hscript.Printer.errorToString(e));
			errorMessage.show();
		}
	}

	public function focus() {
		editor.focus();
	}

	public dynamic function onSave() {
	}

}
