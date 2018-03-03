package hide.comp.cdb;

class SubTable extends Table {

	var insertedTR : Element;
	var slider : Element;
	public var cell : Cell;

	public function new(editor, sheet:cdb.Sheet, cell:Cell) {

		this.cell = cell;
		if( sheet.lines == null ) {
			@:privateAccess sheet.sheet.lines = [];
			Reflect.setField(cell.line.obj, cell.column.name, sheet.lines);
			// do not save for now
		}

		var line = cell.line;
		if( line.subTable != null ) throw "assert";
		line.subTable = this;

		insertedTR = new Element("<tr>").addClass("list");
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
		if( cell.column.opt && sheet.lines.length == 0 ) {
			Reflect.deleteField(cell.line.obj, cell.column.name);
			editor.save();
		}
		cell.refresh();
	}

}