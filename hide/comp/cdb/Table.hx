package hide.comp.cdb;
import js.jquery.Helper.*;

class Table extends Component {

	public var editor : Editor;
	public var sheet : cdb.Sheet;
	public var lines : Array<Line>;

	public function new(editor, sheet, root) {
		super(root);
		this.editor = editor;
		this.sheet = sheet;
		@:privateAccess editor.tables.push(this);
		root.addClass("cdb-sheet");
		refresh();
	}

	public function close() {
		root.remove();
		dispose();
	}

	public function dispose() {
		editor.tables.remove(this);
	}

	public function refresh() {

		var cols = J("<tr>").addClass("head");
		J("<th>").addClass("start").appendTo(cols);
		lines = [for( index in 0...sheet.lines.length ) {
			var l = J("<tr>");
			var head = J("<td>").addClass("start").text("" + index);
			head.appendTo(l);
			var line = new Line(this, index, l);
			l.mousedown(function(e) {
				if( e.which == 3 ) {
					head.click();
					editor.popupLine(line);
					e.preventDefault();
					return;
				}
			}).click(function(e) {
				editor.cursor.clickLine(line, e.shiftKey);
			});
			line;
		}];


		var colCount = sheet.columns.length;
		var todo = [];
		var inTodo = false;
		for( cindex in 0...sheet.columns.length ) {
			var c = sheet.columns[cindex];
			var col = J("<th>");
			col.text(c.name);
			col.addClass( "t_"+c.type.getName().substr(1).toLowerCase() );
			if( sheet.props.displayColumn == c.name )
				col.addClass("display");
			col.mousedown(function(e) {
				if( e.which == 3 ) {
					editor.popupColumn(this, c);
					e.preventDefault();
					return;
				}
			});
			col.dblclick(function(_) {
				editor.newColumn(sheet, c);
			});
			cols.append(col);

			for( index in 0...sheet.lines.length ) {
				var v = J("<td>").addClass("c");
				var line = lines[index];
				v.appendTo(line.root);
				var cell = new Cell(v, line, c);

				v.click(function(e) {
					editor.cursor.clickCell(cell, e.shiftKey);
					e.stopPropagation();
				});

				switch( c.type ) {
				case TList:
					var key = sheet.getPath() + "@" + c.name + ":" + index;
					cell.root.click(function(e) {
						e.stopPropagation();
						toggleList(cell);
					});
				default:
				}
			}
		}

		root.empty();
		root.append(cols);

		var snext = 0;
		for( i in 0...lines.length ) {
			while( sheet.separators[snext] == i ) {
				var sep = J("<tr>").addClass("separator").append('<td colspan="${colCount+1}">').appendTo(root);
				var content = sep.find("td");
				var title = if( sheet.props.separatorTitles != null ) sheet.props.separatorTitles[snext] else null;
				if( title != null ) content.text(title);
				var pos = snext;
				sep.dblclick(function(e) {
					content.empty();
					J("<input>").appendTo(content).focus().val(title == null ? "" : title).blur(function(_) {
						title = JTHIS.val();
						JTHIS.remove();
						content.text(title);
						/*
						var titles = sheet.props.separatorTitles;
						if( titles == null ) titles = [];
						while( titles.length < pos )
							titles.push(null);
						titles[pos] = title == "" ? null : title;
						while( titles[titles.length - 1] == null && titles.length > 0 )
							titles.pop();
						if( titles.length == 0 ) titles = null;
						sheet.props.separatorTitles = titles;
						save();*/
					}).keypress(function(e) {
						e.stopPropagation();
					}).keydown(function(e) {
						if( e.keyCode == 13 ) { JTHIS.blur(); e.preventDefault(); } else if( e.keyCode == 27 ) content.text(title);
						e.stopPropagation();
					});
				});
				snext++;
			}
			root.append(lines[i].root);
		}

		if( sheet.lines.length == 0 ) {
			var l = J('<tr><td colspan="${sheet.columns.length + 1}"><a href="javascript:_.insertLine()">Insert Line</a></td></tr>');
			l.find("a").click(function(_) {
				editor.insertLine(this);
				editor.cursor.set(this);
			});
			root.append(l);
		}

		inTodo = true;
		for( t in todo ) t();
		inTodo = false;
	}

	function toggleList( cell : Cell ) {
		var line = cell.line;
		var cur = line.subTable;
		if( cur != null ) {
			cur.close();
			line.subTable = null;
			if( cur.cell == cell ) return; // toggle
		}
		var sheet = editor.makeSubSheet(cell);
		var sub = new SubTable(editor, sheet, cell);
		sub.show();
		editor.cursor.set(sub);
	}

}