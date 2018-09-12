package hide.comp.cdb;

class ScriptTable extends SubTable {

	var edit : monaco.Editor;

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
		var deco = [];
		edit.addCommand(monaco.KeyCode.KEY_S | monaco.KeyMod.CtrlCmd, function() {
			var cur = edit.getValue({preserveBOM:true});
			@:privateAccess cell.setValue(cur);
		});
		edit.onDidChangeModelContent(function() {
			var cur = edit.getValue({preserveBOM:true});
			try {
				new hscript.Parser().parseString(cur);
				if( deco.length != 0 ) deco = edit.deltaDecorations(deco,[]);
			} catch( e : hscript.Expr.Error ) {
				var linePos = cur.substr(0,e.pmin).lastIndexOf("\n");
				//trace(e, e.pmin, e.pmax, cur.substr(e.pmin, e.pmax - e.pmin + 1), linePos);
				if( linePos < 0 ) linePos = 0 else linePos++;
				var range = new monaco.Range(e.line,e.pmin + 1 - linePos,e.line,e.pmax + 2 - linePos);
				deco = edit.deltaDecorations(deco,[
					{ range : range, options : { inlineClassName: "scriptErrorContentLine", isWholeLine : true } },
					{ range : range, options : { linesDecorationsClassName: "scriptErrorLine", inlineClassName: "scriptErrorContent" } }
				]);
			}
		});
		lines = [new Line(this,[],0,lineElement)];
		if( first ) haxe.Timer.delay(function() edit.focus(),0);
	}

}

