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

	public function getChangeRef() : cdb.Database.ChangeRef {
		var mainLine = this;
		while( true ) {
			var sub = Std.instance(mainLine.table, SubTable);
			if( sub == null ) break;
			mainLine = sub.cell.line;
		}
		return { mainSheet : mainLine.table.sheet, mainObj : mainLine.obj, obj : obj, sheet : table.sheet };
	}

	inline function get_obj() return table.sheet.lines[index];

}
