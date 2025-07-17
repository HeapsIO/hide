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


	public function getId(): String {
		var columns = table.displayMode == Table ? columns : table.sheet.columns;
		var obj = obj;
		for( c in columns ) {
			if( c.type == TId )
				return Reflect.field(obj, c.name);
		}
		return null;
	}

	public function create() {
		var view = table.view;
		element.get(0).classList.remove("hidden");
		var id: String = null;
		for( c in columns ) {
			var e = #if hl ide.createElement("td") #else js.Browser.document.createTableCellElement() #end;
			e.classList.add("c");
			this.element.get(0).appendChild(e);
			var cell = new Cell(e, this, c);
			if( c.type == TId ) {
				id = cell.value;
				if( view != null && view.forbid != null && view.forbid.indexOf(cell.value) >= 0 )
					element.get(0).classList.add("hidden");
			}
		}

		var sheetsToCount: Array<String> = ide.currentConfig.get("cdb.indicateRefs");
		var countRefs = sheetsToCount.contains(table.sheet.name);
		if( countRefs && id != null ) {
			var refCount = table.editor.getReferences(id, false, table.sheet).length;
			element.get(0).classList.toggle("has-ref", refCount > 0);
			element.get(0).classList.toggle("no-ref", refCount == 0);
			element.get(0).classList.add("ref-count-" + refCount);
		}
		syncClasses();
	}

	public function syncClasses() {
		var obj = obj;
		element.get(0).classList.toggle("locIgnored", Reflect.hasField(obj,cdb.Lang.IGNORE_EXPORT_FIELD));
		validate();
	}

	public function getGroupID() {
		var line = getRootLine();
		var t = line.table;
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

	public function getRootLine() {
		var line = this;
		var t = table;
		while( t.parent != null ) {
			line = Std.downcast(t, SubTable).cell.line;
			t = t.parent;
		}
		return line;
	}

	public function getConstants( objId ) {
		var consts = [
			"cdb.objID" => objId,
			"cdb.groupID" => getGroupID(),
		];
		var t = table;
		var line = this;
		while( t != null ) {
			consts.set("cdb."+t.sheet.name.split("@").join("."), line.obj);
			line = Std.downcast(t, SubTable)?.cell?.line;
			t = t.parent;
		}
		return consts;
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

	public function validate() {
        var result = table.editor.formulas.validateLine(table.getRealSheet(), index);
		if(result == null) return;

        element.removeClass("validation-error");
		element.attr("title", null);
        
		switch(result) {
			case Error(msg):
				element.addClass("validation-error");
				element.attr("title", msg);
			default:
		}
    }
}
