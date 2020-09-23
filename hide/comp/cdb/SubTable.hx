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
			var count = cell.columnIndex + 1;
			if (count < 3 && cell.table.columns.length >= 8)
				count += 2; // fix when a lot of columns but the subproperty is on the left
			group = new Element("<td>").attr("colspan",""+(count+1)).appendTo(insertedTR);
			var remain = cell.table.columns.length - count;
			if( remain > 0 )
				new Element("<td>").attr("colspan", "" + remain).appendTo(insertedTR);
		} else {
			new Element("<td>").appendTo(insertedTR);
			group = new Element("<td>").attr("colspan",""+cell.table.columns.length).appendTo(insertedTR);
		}
		slider = new Element("<div>").appendTo(group);
		slider.hide();
		var root = new Element("<table>");
		root.appendTo(slider);
		root.addClass("cdb-sub-sheet");

		insertedTR.insertAfter(cell.line.element);
		cell.element.text("...");
		cell.element.addClass("parent-sub-table");

		super(editor, sheet, root, mode);
	}

	override function getRealSheet() {
		return cell.table.sheet.getSub(cell.column);
	}

	function makeSubSheet() {
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
				Reflect.setField(cell.line.obj, cell.column.name, value);
				// do not save for now
			}
			value;
		case TProperties:
			var value = cell.value;
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
		cell.element.removeClass("parent-sub-table");
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
				// not a change to really undo, perform direct change
				Reflect.deleteField(cell.line.obj, cell.column.name);
				editor.save();
			}
		}
		cell.refresh();
	}

}