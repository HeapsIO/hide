package hide.comp.cdb;

class Line extends Component {

	public var index : Int;
	public var table : Table;
	public var obj(get, never) : Dynamic;
	public var cells : Array<Cell>;

	public function new(table, index, root) {
		super(root);
		this.table = table;
		this.index = index;
		cells = [];
	}

	inline function get_obj() return table.sheet.lines[index];

}
