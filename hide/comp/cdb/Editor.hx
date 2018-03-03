package hide.comp.cdb;
import hxd.Key in K;

@:allow(hide.comp.cdb)
class Editor extends Component {

	var base : cdb.Database;
	var sheet : cdb.Sheet;
	var existsCache : Map<String,{ t : Float, r : Bool }> = new Map();
	var tables : Array<Table> = [];
	var keys : hide.ui.Keys;
	var searchBox : Element;
	var clipboard : {
		text : String,
		data : {},
		schema : Array<cdb.Data.Column>,
	};
	public var cursor : Cursor;

	public function new(root, sheet, keys) {
		super(root);
		this.sheet = sheet;
		this.keys = keys;
		keys.addListener(onKey);
		keys.register("search", function() {
			searchBox.show();
			searchBox.find("input").focus().select();
		});
		keys.register("copy", onCopy);
		base = sheet.base;
		cursor = new Cursor(this);
		refresh();
	}

	function onKey( e : js.jquery.Event ) {
		switch( e.keyCode ) {
		case K.LEFT:
			cursor.move( -1, 0, e.shiftKey, e.ctrlKey);
			return true;
		case K.RIGHT:
			cursor.move( 1, 0, e.shiftKey, e.ctrlKey);
			return true;
		case K.UP:
			cursor.move( 0, -1, e.shiftKey, e.ctrlKey);
			return true;
		case K.DOWN:
			cursor.move( 0, 1, e.shiftKey, e.ctrlKey);
			return true;
		case K.SPACE:
			e.preventDefault(); // prevent scroll
		}
		return false;
	}

	function searchFilter( filter : String ) {

		if( filter == "" ) filter = null;
		if( filter != null ) filter = filter.toLowerCase();

		var lines = root.find("table.cdb-sheet > tr").not(".head");
		lines.removeClass("filtered");
		if( filter != null ) {
			for( t in lines ) {
				if( t.textContent.toLowerCase().indexOf(filter) < 0 )
					t.classList.add("filtered");
			}
			while( lines.length > 0 ) {
				lines = lines.filter(".list").not(".filtered").prev();
				lines.removeClass("filtered");
			}
		}
	}

	function onCopy() {
		var sel = cursor.getSelection();
		if( sel == null )
			return;
		var data = [];
		for( y in sel.y1...sel.y2+1 ) {
			var obj = cursor.table.lines[y].obj;
			var out = {};
			for( x in sel.x1...sel.x2+1 ) {
				var c = cursor.table.sheet.columns[x];
				var v = Reflect.field(obj, c.name);
				if( v != null )
					Reflect.setField(out, c.name, v);
			}
			data.push(out);
		}
		clipboard = {
			data : data,
			text : Std.string([for( o in data ) cursor.table.sheet.objToString(o,true)]),
			schema : [for( x in sel.x1...sel.x2+1 ) cursor.table.sheet.columns[x]],
		};
		ide.setClipboard(clipboard.text);
	}

	function refresh() {

		root.html('');
		root.addClass('cdb');

		searchBox = new Element("<div>").addClass("searchBox").appendTo(root);
		new Element("<input type='text'>").appendTo(searchBox).keydown(function(e) {
			if( e.keyCode == 27 ) {
				searchBox.find("i").click();
				return;
			}
		}).keyup(function(e) {
			searchFilter(e.getThis().val());
		});
		new Element("<i>").addClass("fa fa-times-circle").appendTo(searchBox).click(function(_) {
			searchFilter(null);
			searchBox.toggle();
		});

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

	public function popupColumn( table : Table, col : cdb.Data.Column ) {
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

	public function makeSubSheet( cell : Cell ) {
		var sheet = cell.table.sheet;
		var c = cell.column;
		var index = cell.line.index;
		var key = sheet.getPath() + "@" + c.name + ":" + index;
		var psheet = sheet.getSub(c);
		return new cdb.Sheet(base,{
			columns : psheet.columns, // SHARE
			props : psheet.props, // SHARE
			name : psheet.name, // same
			lines : cell.value, // ref
			separators : [], // none
		},key, { sheet : sheet, column : cell.columnIndex, line : index });
	}

	public function close() {
		for( t in tables.copy() )
			t.dispose();
	}

	public dynamic function save() {
	}

}

