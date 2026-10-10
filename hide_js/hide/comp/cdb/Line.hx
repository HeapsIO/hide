package hide.comp.cdb;

class Line extends Component {

	public var index : Int;
	public var table : Table;
	public var obj(get, never) : Dynamic;
	public var cells : Array<Cell>;
	public var columns : Array<cdb.Data.Column>;
	public var subTable : SubTable;
	public var status : Formulas.ValidationResult;
	public var filtered : Bool = false;
	// the group of the line (null if none)
	public var separator : Separator;
	// the line is in the rows of its table : not filtered, not in a collapsed group, not forbidden
	public var displayed : Bool = true;
	public var row(default, null) : Table.Row;
	// the cells are created (the line can be out of the DOM, see Table.render)
	public var created(default, null) : Bool = false;
	var headCreated = false;
	var searchText : String;

	public function new(table, columns, index, root) {
		super(null,root);
		this.table = table;
		this.index = index;
		this.columns = columns;
		cells = [];
		row = new Table.Row(this, null);
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

	public function isForbidden() {
		var forbid = table.view?.forbid;
		if( forbid == null )
			return false;
		for( c in columns )
			if( c.type == TId )
				return forbid.indexOf(Reflect.field(obj, c.name)) >= 0;
		return false;
	}

	/**
		Creates the cells of the line, if they are not created yet (only for the lines of a table in Table mode).
	**/
	public function create() {
		if( created || @:privateAccess table.tbody == null || table.displayMode != Table ) return;
		created = true;
		if( !headCreated ) {
			headCreated = true;
			@:privateAccess table.createLineHead(this);
		}
		@:privateAccess table.onLineCreated(this);
		var id: String = null;
		for( c in columns ) {
			var e = #if hl ide.createElement("td") #else js.Browser.document.createTableCellElement() #end;
			e.classList.add("c");
			this.element.get(0).appendChild(e);
			var cell = new Cell(e, this, c);
			if( c.type == TId )
				id = cell.value;
		}

		var sheetsToCount: Array<String> = ide.currentConfig.get("cdb.indicateRefs");
		var countRefs = sheetsToCount.contains(table.sheet.name);
		if( countRefs && id != null ) {
			var refCount = table.editor.getReferences(id, false, table.sheet).length;
			element.get(0).classList.toggle("has-ref", refCount > 0);
			element.get(0).classList.toggle("no-ref", refCount == 0);
			element.get(0).classList.add("ref-count-" + refCount);
		}
		syncLocClass();
		applyStatus();
	}

	/**
		Removes the cells of the line, keeping its element.
	**/
	public function removeCells() {
		if( !created ) return;
		created = false;
		cells = [];
		element.children('td.c').remove();
		@:privateAccess table.materialized.remove(this);
	}

	/**
		Removes the line from the DOM and its cells : it is out of the view, or no longer displayed.
	**/
	public function unrender() {
		if( subTable != null )
			subTable.immediateClose();
		var e = element.get(0);
		#if js
		if( e.contains(js.Browser.document.activeElement) )
			table.editor.focus();
		#end
		removeCells();
		if( e.parentNode != null )
			e.parentNode.removeChild(e);
		row.attached = false;
	}

	/**
		The text of the line, as displayed, for the search.
	**/
	public function getSearchText() : String {
		if( searchText == null ) {
			var wasCreated = created;
			create();
			searchText = element.get(0).textContent;
			if( !wasCreated && !row.attached )
				removeCells();
		}
		return searchText;
	}

	public function syncClasses() {
		syncLocClass();
		validate();
	}

	function syncLocClass() {
		element.get(0).classList.toggle("locIgnored", Reflect.hasField(obj,cdb.Lang.IGNORE_EXPORT_FIELD));
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

	public function validate() {
		updateStatus();
		applyStatus();
		table.refreshLinesStatus();
	}

	/**
		Validates the line and updates the error and warning counts of its table, without touching the DOM.
	**/
	public function updateStatus() {
		if (table.errors.get(this) != null) {
			table.errors.remove(this);
			table.errorCount--;
		}
		if (table.warnings.get(this) != null) {
			table.warnings.remove(this);
			table.warningCount--;
		}

		status = table.editor.formulas.validateLine(table.getRealSheet(), index);
		switch( status ) {
			case null:
			case Error(_):
				table.errorCount++;
				table.errors.set(this, true);
			case Warning(_):
				table.warningCount++;
				table.warnings.set(this, true);
			default:
		}
	}

	function applyStatus() {
		element.removeClass("validation-error");
		element.removeClass("validation-warning");
		element.attr("title", null);
		switch( status ) {
			case null:
			case Error(msg):
				element.addClass("validation-error");
				element.attr("title", "Error: " + msg);
			case Warning(msg):
				element.addClass("validation-warning");
				element.attr("title", "Warning: " + msg);
			default:
		}
	}
}
