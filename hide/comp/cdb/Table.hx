package hide.comp.cdb;
import js.jquery.Helper.*;

enum DisplayMode {
	Table;
	Properties;
	AllProperties;
}

class Table extends Component {

	public var editor : Editor;
	public var parent : Table;
	public var sheet : cdb.Sheet;
	public var lines : Array<Line>;
	public var displayMode(default,null) : DisplayMode;

	public function new(editor, sheet, root, mode) {
		super(null,root);
		this.displayMode = mode;
		this.editor = editor;
		this.sheet = sheet;
		@:privateAccess editor.tables.push(this);
		root.addClass("cdb-sheet");
		refresh();
	}

	public function close() {
		element.remove();
		dispose();
	}

	public function dispose() {
		editor.tables.remove(this);
	}

	public function refresh() {
		element.empty();
		switch( displayMode ) {
		case Table:
			refreshTable();
		case Properties, AllProperties:
			refreshProperties();
		}
	}

	function refreshTable() {
		var cols = J("<tr>").addClass("head").wrap("<thead>");
		J("<th>").addClass("start").appendTo(cols);
		lines = [for( index in 0...sheet.lines.length ) {
			var l = J("<tr>");
			var head = J("<td>").addClass("start").text("" + index);
			head.appendTo(l);
			var line = new Line(this, sheet.columns, index, l);
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
				editor.editColumn(sheet, c);
			});
			cols.append(col);

			for( index in 0...sheet.lines.length ) {
				var v = J("<td>").addClass("c");
				var line = lines[index];
				v.appendTo(line.element);
				var cell = new Cell(v, line, c);

				v.click(function(e) {
					editor.cursor.clickCell(cell, e.shiftKey);
					e.stopPropagation();
				});

				switch( c.type ) {
				case TList, TProperties:
					cell.element.click(function(e) {
						if( e.shiftKey ) return;
						e.stopPropagation();
						toggleList(cell);
					});
				default:
					cell.element.dblclick(function(_) cell.edit());
				}
			}
		}

		element.append( cols.parent() );

		var tbody = J("<tbody>");

		var snext = 0;
		for( i in 0...lines.length+1 ) {
			while( sheet.separators[snext] == i ) {
				makeSeparator(snext, colCount).appendTo(tbody);
				snext++;
			}
			if( i == lines.length ) break;
			tbody.append(lines[i].element);
		}
		element.append(tbody);

		if( sheet.lines.length == 0 ) {
			var l = J('<tr><td colspan="${sheet.columns.length + 1}"><a>Insert Line</a></td></tr>');
			l.find("a").click(function(_) {
				editor.insertLine(this);
				editor.cursor.set(this);
			});
			element.append(l);
		}
	}

	function makeSeparator( sindex : Int, colCount : Int ) {
		var sep = J("<tr>").addClass("separator").append('<td colspan="${colCount+1}">');
		var content = sep.find("td");
		var title = if( sheet.props.separatorTitles != null ) sheet.props.separatorTitles[sindex] else null;
		if( title != null ) content.text(title);
		sep.dblclick(function(e) {
			content.empty();
			J("<input>").appendTo(content).focus().val(title == null ? "" : title).blur(function(_) {
				title = JTHIS.val();
				JTHIS.remove();
				content.text(title);

				var old = sheet.props.separatorTitles;
				var titles = sheet.props.separatorTitles;
				if( titles == null ) titles = [] else titles = titles.copy();
				while( titles.length < sindex )
					titles.push(null);
				titles[sindex] = title == "" ? null : title;
				while( titles[titles.length - 1] == null && titles.length > 0 )
					titles.pop();
				if( titles.length == 0 ) titles = null;
				editor.beginChanges();
				sheet.props.separatorTitles = titles;
				editor.endChanges();

			}).keypress(function(e) {
				e.stopPropagation();
			}).keydown(function(e) {
				if( e.keyCode == 13 ) { JTHIS.blur(); e.preventDefault(); } else if( e.keyCode == 27 ) content.text(title);
				e.stopPropagation();
			});
		});
		return sep;
	}

	function refreshProperties() {
		lines = [];

		var available = [];
		var props = sheet.lines[0];
		for( c in sheet.columns ) {

			if( c.opt && !Reflect.hasField(props,c.name) && displayMode != AllProperties ) {
				available.push(c);
				continue;
			}

			var v = Reflect.field(props, c.name);
			var l = new Element("<tr>").appendTo(element);
			var th = new Element("<th>").text(c.name).appendTo(l);
			var td = new Element("<td>").addClass("c").appendTo(l);

			var line = new Line(this, [c], lines.length, l);
			var cell = new Cell(td, line, c);
			lines.push(line);

			td.click(function(e) {
				editor.cursor.clickCell(cell, e.shiftKey);
				e.stopPropagation();
			});

			th.mousedown(function(e) {
				if( e.which == 3 ) {
					editor.popupColumn(this, c);
					editor.cursor.clickCell(cell, false);
					e.preventDefault();
					return;
				}
			});

			cell.element.dblclick(function(_) cell.edit());
		}

		// add/edit properties
		var end = new Element("<tr>").appendTo(element);
		end = new Element("<td>").attr("colspan", "2").appendTo(end);
		var sel = new Element("<select class='insertField'>").appendTo(end);
		new Element("<option>").attr("value", "").text("--- Choose ---").appendTo(sel);
		for( c in available )
			J("<option>").attr("value",c.name).text(c.name).appendTo(sel);
		J("<option>").attr("value","$new").text("New property...").appendTo(sel);
		sel.change(function(e) {
			var v = sel.val();
			if( v == "" )
				return;
			sel.val("");
			editor.element.focus();
			if( v == "$new" ) {
				editor.newColumn(sheet);
				return;
			}
			insertProperty(v);
		});
	}

	public function insertProperty( p : String ) {
		var props = sheet.lines[0];
		for( c in sheet.columns )
			if( c.name == p ) {
				var val = editor.base.getDefault(c, true);
				editor.beginChanges();
				Reflect.setField(props, c.name, val);
				editor.endChanges();
				refresh();
				return true;
			}
		return false;
	}

	function toggleList( cell : Cell, ?immediate : Bool, ?make : Void -> SubTable ) {
		var line = cell.line;
		var cur = line.subTable;
		if( cur != null ) {
			cur.close();
			if( cur.cell == cell ) return; // toggle
		}
		var sub = make == null ? new SubTable(editor, cell) : make();
		sub.show(immediate);
		editor.cursor.set(sub);
	}

	function toString() {
		return "Table#"+sheet.name;
	}

}