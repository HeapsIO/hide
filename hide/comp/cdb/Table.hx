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

	public var columns : Array<cdb.Data.Column>;
	public var view : ConfigView.SheetView;

	public function new(editor, sheet, root, mode) {
		super(null,root);
		this.displayMode = mode;
		this.editor = editor;
		this.sheet = sheet;
		@:privateAccess for( t in editor.tables )
			if( t.sheet.path == sheet.path )
				trace("Dup CDB table!");

		@:privateAccess editor.tables.push(this);
		root.addClass("cdb-sheet");
		if( editor.view != null ) {
			var cname = parent == null ? null : sheet.parent.sheet.columns[sheet.parent.column].name;
			if( parent == null )
				view = editor.view.get(sheet.name);
			else if( parent.view.sub != null )
				view = parent.view.sub.get(cname);
			if( view == null ) {
				if( parent != null && parent.canEditColumn(cname) )
					view = { insert : true, edit : [for( c in sheet.columns ) c.name], sub : {} };
				else
					view = { insert : false, edit : [], sub : {} };
			}
		}
		refresh();
	}

	public function getRealSheet() {
		return sheet;
	}

	public function canInsert() {
		return view == null || view.insert;
	}

	public function canEditColumn( name : String ) {
		return view == null || (view.edit != null && view.edit.indexOf(name) >= 0);
	}

	public function close() {
		for( t in @:privateAccess editor.tables.copy() )
			if( t.parent == this )
				t.close();
		element.remove();
		dispose();
	}

	public function dispose() {
		editor.tables.remove(this);
	}

	public function refresh() {
		element.empty();
		columns = view == null || view.show == null ? sheet.columns : [for( c in sheet.columns ) if( view.show.indexOf(c.name) >= 0 ) c];
		switch( displayMode ) {
		case Table:
			refreshTable();
		case Properties, AllProperties:
			refreshProperties();
		}
	}

	function cloneTableHead() {
		var target = element.find('thead').first().find('.head');
		if (target.length == 0)
			return;
		var target_children = target.children();

		J(".floating-thead").remove();

		var clone = J("<div>").addClass("floating-thead");

		for (i in 0...target_children.length) {
			var targetElt = target_children.eq(i);
			var elt = targetElt.clone(true); // clone with events
			elt.width(targetElt.width());
			elt.css("max-width", targetElt.width());

			var txt = elt[0].innerHTML;
			elt.empty();
			J("<span>" + txt + "</span>").appendTo(elt);

			clone.append(elt);
		}

		J('.cdb').prepend(clone);
	}

	function refreshTable() {
		var cols = J("<thead>").addClass("head");
		J("<th>").addClass("start").appendTo(cols);
		lines = [for( index in 0...sheet.lines.length ) {
			var l = J("<tr>");
			var head = J("<td>").addClass("start").text("" + index);
			head.appendTo(l);
			var line = new Line(this, columns, index, l);
			head.mousedown(function(e) {
				if( e.which == 3 ) {
					editor.popupLine(line);
					e.preventDefault();
					return;
				}
			});
			l.click(function(e) {
				if( e.which == 3 ) {
					e.preventDefault();
					return;
				}
				editor.cursor.clickLine(line, e.shiftKey);
			});
			line;
		}];

		var colCount = columns.length;
		for( c in columns ) {
			var col = J("<th>");
			col.text(c.name);
			col.addClass( "t_"+c.type.getName().substr(1).toLowerCase() );
			if( c.documentation != null )
				col.attr("title", c.documentation);
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
				if( editor.view == null ) editor.editColumn(getRealSheet(), c);
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
			}
		}

		element.append(cols);

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

		if( colCount == 0 ) {
			var l = J('<tr><td><input type="button" value="Add a column"/></td></tr>').find("input").click(function(_) {
				editor.newColumn(sheet);
			});
			element.append(l);
		} else if( sheet.lines.length == 0 && canInsert() ) {
			var l = J('<tr><td colspan="${columns.length + 1}"><input type="button" value="Insert Line"/></td></tr>');
			l.find("input").click(function(_) {
				editor.insertLine(this);
				editor.cursor.set(this);
			});
			element.append(l);
		}

		if( sheet.parent == null ) {
			cols.ready(cloneTableHead);
			cols.on("resize", cloneTableHead);
		}
	}

	function makeSeparator( sindex : Int, colCount : Int ) {
		var sep = J("<tr>").addClass("separator").append('<td colspan="${colCount+1}">');
		var content = sep.find("td");
		var title = if( sheet.props.separatorTitles != null ) sheet.props.separatorTitles[sindex] else null;
		if( title != null ) content.text(title);
		sep.dblclick(function(e) {
			if( !canInsert() ) return;
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
		var isLarge = false;
		for( c in columns ) {

			if( c.type.match(TList | TProperties) ) isLarge = true;

			if( c.opt && props != null && !Reflect.hasField(props,c.name) && displayMode != AllProperties ) {
				available.push(c);
				continue;
			}

			var v = Reflect.field(props, c.name);
			var l = new Element("<tr>").appendTo(element);
			var th = new Element("<th>").text(c.name).appendTo(l);
			var td = new Element("<td>").addClass("c").appendTo(l);

			if( c.documentation != null )
				th.attr("title", c.documentation);

			var line = new Line(this, [c], lines.length, l);
			var cell = new Cell(td, line, c);
			lines.push(line);

			td.click(function(e) {
				editor.cursor.clickCell(cell, e.shiftKey);
				e.stopPropagation();
			});

			th.mousedown(function(e) {
				if( e.which == 3 ) {
					editor.popupColumn(this, c, cell);
					editor.cursor.clickCell(cell, false);
					e.preventDefault();
					return;
				}
			});
		}

		if( isLarge )
			element.parent().addClass("cdb-large");

		// add/edit properties
		var end = new Element("<tr>").appendTo(element);
		end = new Element("<td>").attr("colspan", "2").appendTo(end);
		var sel = new Element("<select class='insertField'>").appendTo(end);
		new Element("<option>").attr("value", "").text("--- Choose ---").appendTo(sel);
		var canInsert = false;
		for( c in available )
			if( canEditColumn(c.name) ) {
				var opt = J("<option>").attr("value",c.name).text(c.name).appendTo(sel);
				if( c.documentation != null ) opt.attr("title", c.documentation);
				canInsert = true;
			}
		if( editor.view == null )
			J("<option>").attr("value","$new").text("New property...").appendTo(sel);
		else if( !canInsert )
			end.remove();
		sel.change(function(e) {
			var v = sel.val();
			if( v == "" )
				return;
			sel.val("");
			editor.element.focus();
			if( v == "$new" ) {
				editor.newColumn(sheet, null, function(c) {
					if( c.opt ) insertProperty(c.name);
				});
				return;
			}
			insertProperty(v);
		});
	}

	public function insertProperty( p : String ) {
		var props = sheet.lines[0];
		for( c in sheet.columns )
			if( c.name == p ) {
				var val = editor.base.getDefault(c, true, sheet);
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