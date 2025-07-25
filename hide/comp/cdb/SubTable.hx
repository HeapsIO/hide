package hide.comp.cdb;

class SubTable extends Table {

	var insertedTR : Element;
	var slider : Element;
	public var cell : Cell;

	public function new(editor, cell:Cell) {
		this.editor = editor;
		this.cell = cell;
		parent = cell.table;

		var sheet = makeSubSheet();
		var line = cell.line;
		if( line.subTable != null ) throw "assert";
		line.subTable = this;

		var mode : Table.DisplayMode = switch( cell.column.type ) {
			case TProperties: Properties;
			default: Table;
		};

		insertedTR = new Element("<tr>").addClass(cell.column.type == TProperties ? "props" : "list");
		var group;
		if( editor.displayMode == AllProperties && cell.table.parent == null ) {
			group = new Element("<td>").attr("colspan","2").appendTo(insertedTR);
		} else if( mode == Properties ) {
			if (parent.displayMode == Properties) {
				new Element("<td>")
					.appendTo(insertedTR)
					.toggleClass("sublist-pad-" + parent.nestedIndex);
			}

			var count = cell.columnIndex + 1;
			if (count < 3 && cell.table.columns.length >= 8)
				count += 2; // fix when a lot of columns but the subproperty is on the left
			group = new Element("<td>").attr("colspan",""+(count+1)).appendTo(insertedTR);
			var remain = cell.table.columns.length - count;
			if( remain > 0 )
				new Element("<td>").attr("colspan", "" + remain).appendTo(insertedTR);
		} else {
			new Element("<td>")
				.appendTo(insertedTR)
				.toggleClass("sublist-pad-" + parent.nestedIndex);
			group = new Element("<td>").attr("colspan",""+cell.table.columns.length).appendTo(insertedTR);
		}
		slider = new Element("<div>").appendTo(group);
		slider.hide();
		var root = new Element("<table>");
		root.appendTo(slider);
		root.addClass("cdb-sub-sheet");

		insertedTR.data("parent-cell", cell);
		insertedTR.data("parent-tr", cell.line.element);

		insertedTR.insertAfter(cell.line.element);
		cell.elementHtml.textContent = "...";
		cell.elementHtml.classList.add("parent-sub-table");

		super(editor, sheet, root, mode);

		this.nestedIndex = parent.nestedIndex + 1;
	}

	override function getRealSheet() {
		return cell.table.sheet.getSub(cell.column);
	}

	override function refresh() {
		super.refresh();

		checkIntegrity();
	}

	function checkIntegrity() {
		var v = Reflect.field(cell.line.obj, cell.column.name);
		switch(cell.column.type) {
			case TList:
				if (v != sheet.lines) {
					hide.Ide.inst.error("Editor integrity compromised, please refresh the editor and contact someone in the tool team");
				}
			case TProperties:
				if (v != sheet.lines[0]) {
					hide.Ide.inst.error("Editor integrity compromised, please refresh the editor and contact someone in the tool team");
				}
			default:
		}
		var parSub = Std.downcast(parent, SubTable);
		if (parSub != null) {
			parSub.checkIntegrity();
		}
	}

	function makeSubSheet() {
		var sheet = cell.table.sheet;
		var c = cell.column;
		var index = cell.line.index;
		var key = sheet.getPath() + "@" + c.name + ":" + index;
		var psheet = sheet.getSub(c);
		var value : Dynamic = Reflect.field(cell.line.obj, cell.column.name);
		var lines = switch( cell.column.type ) {
		case TList:
			if( value == null ) {
				value = [];
				Reflect.setField(cell.line.obj, cell.column.name, value);
				// do not save for now
			}
			value;
		case TProperties:
			if( value == null ) {
				value = {};
				Reflect.setField(cell.line.obj, cell.column.name, value);
				// do not save for now
			}
			var lines = [for( f in psheet.columns ) value];
			if( lines.length == 0 ) lines.push(value);
			lines;
		default:
			throw "assert";
		}
		return new cdb.Sheet(editor.base,{
			columns : psheet.columns, // SHARE
			props : psheet.props, // SHARE
			name : psheet.name, // same
			lines : lines, // ref
			separators : [], // none
		},key, { sheet : sheet, column : cell.table.sheet.columns.indexOf(c), line : index });
	}

	public function show( ?immediate ) {
		if( immediate )
			slider.show();
		else
			slider.slideDown(100);
	}

	override public function close() {
		if( cell.line.subTable == this ) cell.line.subTable = null;
		if( slider != null ) {
			slider.slideUp(100, function() { slider = null; close(); });
			return;
		}
		cell.elementHtml.classList.remove("parent-sub-table");
		super.close();
	}

	public function immediateClose() {
		if( cell.line.subTable == this ) cell.line.subTable = null;
		cell.elementHtml.classList.remove("parent-sub-table");
		super.close();
	}

	override function dispose() {
		super.dispose();
		insertedTR.remove();
		cell.refresh();
	}

}