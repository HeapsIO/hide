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
		}
	}

	public function getGroupID() {
		var t = table;
		var line = this;
		while( t.parent != null ) {
			line = Std.downcast(t, SubTable).cell.line;
			t = t.parent;
		}
		var seps = t.sheet.separators;
		var i = seps.length - 1;
		while( i >= 0 ) {
			if( seps[i] < line.index ) {
				var t = t.sheet.props.separatorTitles[i];
				if( t != null ) return t;
			}
			i--;
		}
		return null;
	}

	public function evaluate() {
		for( c in cells )
			@:privateAccess c.evaluate();
	}

	public function hide() {
		if( subTable != null ) {
			subTable.close();
			subTable = null;
		}
		cells = [];
		element.children('td.c').remove();
		element.addClass("hidden");
	}

}
