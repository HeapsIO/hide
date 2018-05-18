package hide.comp.cdb;
import js.jquery.Helper.*;

enum DisplayMode {
	Table;
	Properties;
	AllProperties;
}

class Table extends Component {

	public var editor : Editor;
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
		var cols = J("<tr>").addClass("head");
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
				editor.newColumn(sheet, c);
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
						e.stopPropagation();
						toggleList(cell);
					});
				default:
					cell.element.dblclick(function(_) cell.edit());
				}
			}
		}

		element.append(cols);

		var snext = 0;
		for( i in 0...lines.length ) {
			while( sheet.separators[snext] == i ) {
				var sep = J("<tr>").addClass("separator").append('<td colspan="${colCount+1}">').appendTo(element);
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

						var old = sheet.props.separatorTitles;
						var titles = sheet.props.separatorTitles;
						if( titles == null ) titles = [] else titles = titles.copy();
						while( titles.length < pos )
							titles.push(null);
						titles[pos] = title == "" ? null : title;
						while( titles[titles.length - 1] == null && titles.length > 0 )
							titles.pop();
						if( titles.length == 0 ) titles = null;
						sheet.props.separatorTitles = titles;
						editor.undo.change(Field(sheet.props,"separatorTitles",old));
						editor.save();

					}).keypress(function(e) {
						e.stopPropagation();
					}).keydown(function(e) {
						if( e.keyCode == 13 ) { JTHIS.blur(); e.preventDefault(); } else if( e.keyCode == 27 ) content.text(title);
						e.stopPropagation();
					});
				});
				snext++;
			}
			element.append(lines[i].element);
		}

		if( sheet.lines.length == 0 ) {
			var l = J('<tr><td colspan="${sheet.columns.length + 1}"><a href="javascript:_.insertLine()">Insert Line</a></td></tr>');
			l.find("a").click(function(_) {
				editor.insertLine(this);
				editor.cursor.set(this);
			});
			element.append(l);
		}
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
		var sel = new Element("<select>").appendTo(end);
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
			for( c in available )
				if( c.name == v ) {
					var val = editor.base.getDefault(c, true);
					Reflect.setField(props, c.name, val);
					editor.undo.change(Custom(function(undo) {
						if( undo )
							Reflect.deleteField(props, c.name);
						else
							Reflect.setField(props,c.name, val);
					}));
					refresh();
					return;
				}
		});
	}

	function toggleList( cell : Cell ) {
		var line = cell.line;
		var cur = line.subTable;
		if( cur != null ) {
			cur.close();
			line.subTable = null;
			if( cur.cell == cell ) return; // toggle
		}
		var sub = new SubTable(editor, cell);
		sub.show();
		if( sub.lines.length > 0 ) editor.cursor.set(sub);
	}

}