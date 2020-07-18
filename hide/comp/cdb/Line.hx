package hide.comp.cdb;

class Line extends Component {

	public var index : Int;
	public var table : Table;
	public var obj(get, never) : Dynamic;
	public var cells : Array<Cell>;
	public var columns : Array<cdb.Data.Column>;
	public var subTable : SubTable;

	public function new(table, columns, index, root) {
		super(null,root);
		this.table = table;
		this.index = index;
		this.columns = columns;
		cells = [];
	}

	inline function get_obj() return table.sheet.lines[index];

	public function create() {
		var view = table.view;
		element.removeClass("hidden");
		for( c in columns ) {
			var v = new Element("<td>").addClass("c");
			v.appendTo(this.element);
			var cell = new Cell(v, this, c);
			if( c.type == TId && view != null && view.forbid != null && view.forbid.indexOf(cell.value) >= 0 )
				element.addClass("hidden");
			v.click(function(e) {
				table.editor.cursor.clickCell(cell, e.shiftKey);
				e.stopPropagation();
			});
		}
	}

	public function hide() {
		cells = [];
		element.children('td.c').remove();
		element.addClass("hidden");
	}

}
