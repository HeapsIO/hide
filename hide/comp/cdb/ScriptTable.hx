package hide.comp.cdb;

typedef GlobalsDef = haxe.DynamicAccess<{
	var globals : haxe.DynamicAccess<String>;
	var context : String;
	var cdbEnums : Bool;
}>;

class ScriptTable extends SubTable {

	var edit : monaco.Editor;
	var check : hscript.Checker;
	var errorMessage : Element;
	var currrentDecos : Array<String> = [];

	public function new(editor:Editor,cell) {
		super(editor,cell);
		var files : Array<String> = editor.props.get("script.api.files");
		if( files.length >= 0 ) {
			check = new hscript.Checker();
			check.allowAsync = true;
			for( f in files ) {
				var content = try sys.io.File.getContent(ide.getPath(f)) catch( e : Dynamic ) { ide.error(e); continue; };
				check.addXmlApi(Xml.parse(content).firstElement());
			}
			var key = cell.table.sheet.name+"."+cell.column.name;
			var api = (editor.props.get("script.api") : GlobalsDef).get(key);
			if( api != null ) {
				for( f in api.globals.keys() )	{
					var tname = api.globals.get(f);
					var t = check.resolveType(tname);
					if( t == null ) ide.error('Global type $tname not found in $files ($f)');
					check.setGlobal(f, t);
				}
				if( api.context != null ) {
					var t = check.resolveType(api.context);
					if( t == null ) ide.error("Missing context type "+api.context);
					while( t != null )
						switch (t) {
						case TInst(c, args):
							for( fname in c.fields.keys() ) {
								var f = c.fields.get(fname);
								check.setGlobal(f.name, f.t);
							}
							t = c.superClass;
						default:
							ide.error(api.context+" context is not a class");
						}
				}
			}
		}
	}

	override function makeSubSheet():cdb.Sheet {
		var sheet = cell.table.sheet;
		var c = cell.column;
		var index = cell.line.index;
		var key = sheet.getPath() + "@" + c.name + ":" + index;
		this.lines = [];
		return new cdb.Sheet(editor.base, {
			columns : [c],
			props : {},
			name : key,
			lines : [cell.line.obj],
			separators: [],
		}, key, { sheet : sheet, column : cell.columnIndex, line : index });
	}

	function checkScript() {
		var cur = edit.getValue({preserveBOM:true});
		try {
			var expr = new hscript.Parser().parseString(cur, "");
			if( check != null ) check.check(expr);
			if( currrentDecos.length != 0 ) currrentDecos = edit.deltaDecorations(currrentDecos,[]);
			errorMessage.hide();
		} catch( e : hscript.Expr.Error ) {
			var linePos = cur.substr(0,e.pmin).lastIndexOf("\n");
			//trace(e, e.pmin, e.pmax, cur.substr(e.pmin, e.pmax - e.pmin + 1), linePos);
			if( linePos < 0 ) linePos = 0 else linePos++;
			var range = new monaco.Range(e.line,e.pmin + 1 - linePos,e.line,e.pmax + 2 - linePos);
			currrentDecos = edit.deltaDecorations(currrentDecos,[
				{ range : range, options : { inlineClassName: "scriptErrorContentLine", isWholeLine : true } },
				{ range : range, options : { linesDecorationsClassName: "scriptErrorLine", inlineClassName: "scriptErrorContent" } }
			]);
			errorMessage.text(hscript.Printer.errorToString(e));
			errorMessage.show();
		}
	}

	override function refresh() {
		var first = edit == null;
		element.html("<div class='cdb-script'></div>");
		element.off();
		var lineElement = element.find(".cdb-script");
		element.on("keydown", function(e) e.stopPropagation());
		edit = monaco.Editor.create(lineElement[0],{
			value : cell.value == null ? "" : cell.value,
			language : "javascript",
			automaticLayout : true,
			wordWrap : true,
			theme : "vs-dark",
		});
		errorMessage = new Element('<div class="scriptErrorMessage"></div>').appendTo(lineElement).hide();
		edit.addCommand(monaco.KeyCode.KEY_S | monaco.KeyMod.CtrlCmd, function() {
			var cur = edit.getValue({preserveBOM:true});
			@:privateAccess cell.setValue(cur);
		});
		edit.onDidChangeModelContent(function() checkScript());
		lines = [new Line(this,[],0,lineElement)];
		if( first ) haxe.Timer.delay(function() {
			edit.focus();
			checkScript();
		},0);
	}

}

