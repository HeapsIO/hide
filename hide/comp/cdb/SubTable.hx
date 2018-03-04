package hide.comp.cdb;

class SubTable extends Table {

	var insertedTR : Element;
	var slider : Element;
	public var cell : Cell;

	public function new(editor, cell:Cell) {

		this.editor = editor;
		this.cell = cell;

		var sheet = makeSubSheet();
		var line = cell.line;
		if( line.subTable != null ) throw "assert";
		line.subTable = this;

		insertedTR = new Element("<tr>").addClass(cell.column.type == TProperties ? "props" : "list");
		new Element("<td>").appendTo(insertedTR);
		var group = new Element("<td>").attr("colspan", "" + cell.table.sheet.columns.length).appendTo(insertedTR);
		slider = new Element("<div>").appendTo(group);
		slider.hide();
		var root = new Element("<table>");
		root.appendTo(slider);

		insertedTR.insertAfter(cell.line.root);
		cell.root.text("...");

		super(editor, sheet, root);
	}

	public function makeSubSheet() {
		var sheet = cell.table.sheet;
		var c = cell.column;
		var index = cell.line.index;
		var key = sheet.getPath() + "@" + c.name + ":" + index;
		var psheet = sheet.getSub(c);
		var lines = switch( cell.column.type ) {
		case TList:
			var value = cell.value;
			if( value == null ) {
				value = [];
				Reflect.setField(cell.line.obj, cell.column.name, sheet.lines);
				// do not save for now
			}
			value;
		case TProperties:
			var value = cell.value;
			if( value == null ) {
				value = {};
				Reflect.setField(cell.line.obj, cell.column.name, sheet.lines);
				// do not save for now
			}
			[for( c in sheet.columns ) cell.value];
		default:
			throw "assert";
		}
		return new cdb.Sheet(editor.base,{
			columns : psheet.columns, // SHARE
			props : psheet.props, // SHARE
			name : psheet.name, // same
			lines : lines, // ref
			separators : [], // none
		},key, { sheet : sheet, column : cell.columnIndex, line : index });
	}

	public function show() {
		slider.slideDown(100);
	}

	override public function close() {
		if( slider != null ) {
			slider.slideUp(100, function() { slider = null; close(); });
			return;
		}
		super.close();
	}

	override function dispose() {
		super.dispose();
		insertedTR.remove();
		if( cell.column.opt ) {
			var isEmpty = switch( cell.column.type ) {
			case TList: sheet.lines.length == 0;
			case TProperties: Reflect.fields(sheet.lines[0]).length == 0;
			default: false;
			}
			if( isEmpty ) {
				Reflect.deleteField(cell.line.obj, cell.column.name);
				editor.save();
			}
		}
		cell.refresh();
	}

	override function refresh() {
		switch( cell.column.type ) {
		case TProperties:
			refreshProperties();
		default:
			super.refresh();
		}
	}

	function refreshProperties() {
		root.empty();

		lines = [];

		var available = [];
		var props = sheet.lines[0];
		for( c in sheet.columns ) {
			if( c.opt && !Reflect.hasField(props,c.name) ) {
				available.push(c);
				continue;
			}

			var v = Reflect.field(props, c.name);
			var l = new Element("<tr>").appendTo(root);
			var th = new Element("<th>").text(c.name).appendTo(l);
			var td = new Element("<td>").addClass("c").appendTo(l);

			var line = new Line(this, lines.length, l);
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
		}

		/*
		var end = J("<tr>").appendTo(content);
		end = J("<td>").attr("colspan", "2").appendTo(end);
		var sel = J("<select>").appendTo(end);
		J("<option>").attr("value", "").text("--- Choose ---").appendTo(sel);
		for( c in available )
			J("<option>").attr("value",c.name).text(c.name).appendTo(sel);
		J("<option>").attr("value","new").text("New property...").appendTo(sel);
		sel.change(function(e) {
			e.stopPropagation();
			var v = sel.val();
			if( v == "" )
				return;
			sel.val("");
			if( v == "new" ) {
				newColumn(sheet.name);
				return;
			}
			for( c in available )
				if( c.name == v ) {
					Reflect.setField(props, c.name, base.getDefault(c, true));
					save();
					refresh();
					return;
				}
		});*/

	}

}