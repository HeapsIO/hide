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
		element[0].classList.remove("hidden");
		var id: String = null;
		for( c in columns ) {
			var e = js.Browser.document.createTableCellElement();
			e.classList.add("c");
			this.element[0].appendChild(e);
			var cell = new Cell(e, this, c);
			if( c.type == TId ) {
				id = cell.value;
				if( view != null && view.forbid != null && view.forbid.indexOf(cell.value) >= 0 )
					element[0].classList.add("hidden");
			}
		}

		var sheetsToCount: Array<String> = ide.currentConfig.get("cdb.indicateRefs");
		var countRefs = sheetsToCount.contains(table.sheet.name);
		if( countRefs && id != null ) {
			var refCount = table.editor.getReferences(id, false, table.sheet).length;
			element[0].classList.toggle("has-ref", refCount > 0);
			element[0].classList.toggle("no-ref", refCount == 0);
			element[0].classList.add("ref-count-" + refCount);
		}
		syncClasses();
	}

	public function syncClasses() {
		var obj = obj;
		element[0].classList.toggle("locIgnored", Reflect.hasField(obj,cdb.Lang.IGNORE_EXPORT_FIELD));
	}

	public function getGroupID() {
		var t = table;
		var line = this;
		while( t.parent != null ) {
			line = Std.downcast(t, SubTable).cell.line;
			t = t.parent;
		}
		for( i in 0...t.sheet.separators.length ) {
			var sep = t.sheet.separators[t.sheet.separators.length - 1 - i];
			if( sep.index <= line.index ) {
				if( sep.path != null )
					return sep.path;
				if( sep.title != null )
					return sep.title;
			}
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
