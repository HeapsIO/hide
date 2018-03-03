package hide.comp.cdb;

@:allow(hide.comp.cdb)
class Editor extends Component {

	var base : cdb.Database;
	var sheet : cdb.Sheet;
	var existsCache : Map<String,{ t : Float, r : Bool }> = new Map();
	var tables : Array<Table> = [];
	public var cursor : Cursor;

	public function new(root, sheet) {
		super(root);
		this.sheet = sheet;
		base = sheet.base;
		cursor = new Cursor(this);
		refresh();
	}

	function refresh() {

		root.html('');
		root.addClass('cdb');

		if( sheet.columns.length == 0 ) {
			new Element("<a>Add a column</a>").appendTo(root).click(function(_) {
				newColumn(sheet);
			});
			return;
		}

		var content = new Element("<table>");
		tables = [];
		new Table(this, sheet, content);
		content.appendTo(root);
	}

	function quickExists(path) {
		var c = existsCache.get(path);
		if( c == null ) {
			c = { t : -1e9, r : false };
			existsCache.set(path, c);
		}
		var t = haxe.Timer.stamp();
		if( c.t < t - 10 ) { // cache result for 10s
			c.r = sys.FileSystem.exists(path);
			c.t = t;
		}
		return c.r;
	}

	function getLine( sheet : cdb.Sheet, index : Int ) {
		for( t in tables )
			if( t.sheet == sheet )
				return t.lines[index];
		return null;
	}

	public function newColumn( sheet : cdb.Sheet, ?after ) {
	}

	public function insertLine( table : Table, index = 0 ) {
	}

	function moveLine( line : Line, delta : Int ) {
		/*
		// remove opened list
		getLine(sheet, index).next("tr.list").change();
		var index = sheet.moveLine(index, delta);
		if( index != null ) {
			setCursor(sheet, -1, index, false);
			refresh();
			save();
		}
		*/
	}

	public function popupLine( line : Line ) {
	}

	public dynamic function save() {
	}

}

