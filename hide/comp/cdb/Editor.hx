package hide.comp.cdb;
import hxd.Key in K;

typedef UndoState = {
	var data : Any;
}

typedef EditorApi = {
	function load( data : Any ) : Void;
	function copy() : Any;
	function save() : Void;
	var ?undo : hide.ui.UndoHistory;
	var ?undoState : Array<UndoState>;
	var ?editor : Editor;
}

@:allow(hide.comp.cdb)
class Editor extends Component {

	var base : cdb.Database;
	var sheet : cdb.Sheet;
	var existsCache : Map<String,{ t : Float, r : Bool }> = new Map();
	var tables : Array<Table> = [];
	var searchBox : Element;
	var displayMode : Table.DisplayMode;
	var clipboard : {
		text : String,
		data : Array<{}>,
		schema : Array<cdb.Data.Column>,
	};
	var changesDepth : Int = 0;
	var currentValue : Any;
	var api : EditorApi;
	public var config : hide.Config;
	public var cursor : Cursor;
	public var keys : hide.ui.Keys;
	public var undo : hide.ui.UndoHistory;

	public function new(sheet,config,api,?parent) {
		super(parent,null);
		this.api = api;
		this.config = config;
		this.sheet = sheet;
		if( api.undoState == null ) api.undoState = [];
		if( api.editor == null ) api.editor = this;
		this.undo = api.undo == null ? new hide.ui.UndoHistory() : api.undo;
		api.undo = undo;
		init();
	}

	function init() {
		element.attr("tabindex", 0);
		element.on("blur", function(_) cursor.set());
		element.on("keypress", function(e) {
			if( e.target.nodeName == "INPUT" )
				return;
			var cell = cursor.getCell();
			if( cell != null && cell.isTextInput() && !e.ctrlKey )
				cell.edit();
		});
		keys = new hide.ui.Keys(element);
		keys.addListener(onKey);
		keys.register("search", function() {
			searchBox.show();
			searchBox.find("input").focus().select();
		});
		keys.register("copy", onCopy);
		keys.register("paste", onPaste);
		keys.register("delete", onDelete);
		keys.register("cdb.showReferences", showReferences);
		keys.register("undo", function() if( undo.undo() ) refresh());
		keys.register("redo", function() if( undo.redo() ) refresh());
		keys.register("cdb.insertLine", function() { insertLine(cursor.table,cursor.y); cursor.move(0,1,false,false); });
		for( k in ["cdb.editCell","rename"] )
			keys.register(k, function() {
				var c = cursor.getCell();
				if( c != null ) c.edit();
			});
		keys.register("cdb.closeList", function() {
			var c = cursor.getCell();
			if( c != null ) {
				var sub = Std.instance(c.table, SubTable);
				if( sub != null ) {
					sub.cell.element.click();
					return;
				}
			}
			if( cursor.select != null ) {
				cursor.select = null;
				cursor.update();
			}
		});
		keys.register("cdb.gotoReference", gotoReference);
		base = sheet.base;
		cursor = new Cursor(this);
		if( displayMode == null ) displayMode = Table;
		currentValue = api.copy();
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
		case K.TAB:
			cursor.move( e.shiftKey ? -1 : 1, 0, false, false);
			return true;
		case K.SPACE:
			e.preventDefault(); // prevent scroll
		}
		return false;
	}

	function searchFilter( filter : String ) {
		if( filter == "" ) filter = null;
		if( filter != null ) filter = filter.toLowerCase();

		var lines = element.find("table.cdb-sheet > tr").not(".head");
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

	function onPaste() {
		var text = ide.getClipboard();
		if( clipboard == null || text != clipboard.text ) {
			// TODO : edit and copy text
			return;
		}
		beginChanges();
		var sheet = cursor.table.sheet;
		var posX = cursor.x < 0 ? 0 : cursor.x;
		var posY = cursor.y < 0 ? 0 : cursor.y;
		for( obj1 in clipboard.data ) {
			if( posY == sheet.lines.length )
				sheet.newLine();
			var obj2 = sheet.lines[posY];
			for( cid in 0...clipboard.schema.length ) {
				var c1 = clipboard.schema[cid];
				var c2 = sheet.columns[cid + posX];
				if( c2 == null ) continue;
				var f = base.getConvFunction(c1.type, c2.type);
				var v : Dynamic = Reflect.field(obj1, c1.name);
				if( f == null )
					v = base.getDefault(c2);
				else {
					// make a deep copy to erase references
					if( v != null ) v = haxe.Json.parse(haxe.Json.stringify(v));
					if( f.f != null )
						v = f.f(v);
				}
				if( v == null && !c2.opt )
					v = base.getDefault(c2);
				if( v == null )
					Reflect.deleteField(obj2, c2.name);
				else
					Reflect.setField(obj2, c2.name, v);
			}
			posY++;
		}
		endChanges();
		sheet.sync();
		refreshAll();
	}

	function onDelete() {
		var sel = cursor.getSelection();
		if( sel == null )
			return;
		var hasChanges = false;
		beginChanges();
		if( cursor.x < 0 ) {
			// delete lines
			var y = sel.y2;
			while( y >= sel.y1 ) {
				var line = cursor.table.lines[y];
				line.table.sheet.lines.splice(line.index, 1);
				hasChanges = true;
				y--;
			}
			cursor.set(cursor.table, -1, sel.y1, null, false);
		} else {
			// delete cells
			for( y in sel.y1...sel.y2+1 ) {
				var line = cursor.table.lines[y];
				for( x in sel.x1...sel.x2+1 ) {
					var c = line.columns[x];
					var old = Reflect.field(line.obj, c.name);
					var def = base.getDefault(c,false);
					if( old == def )
						continue;
					changeObject(line,c,def);
					hasChanges = true;
				}
			}
		}
		endChanges();
		if( hasChanges )
			refreshAll();
	}

	public function changeObject( line : Line, column : cdb.Data.Column, value : Dynamic ) {
		beginChanges();
		var prev = Reflect.field(line.obj, column.name);
		if( value == null )
			Reflect.deleteField(line.obj, column.name);
		else
			Reflect.setField(line.obj, column.name, value);
		line.table.sheet.updateValue(column, line.index, prev);
		endChanges();
	}

	/**
		Call before modifying the database, allow to group several changes together.
		Allow recursion, only last endChanges() will trigger db save and undo point creation.
	**/
	public function beginChanges() {
		if( changesDepth == 0 ) {
			api.undoState.push({
				data : currentValue,
			});
		}
		changesDepth++;
	}

	/**
		Call when changes are done, after endChanges.
	**/
	public function endChanges() {
		changesDepth--;
		if( changesDepth == 0 )
			undo.change(Custom(makeCustom(api)));
	}

	// do not reference "this" editor in undo state !
	static function makeCustom( api : EditorApi ) {
		var state = api.undoState[0];
		var newValue = api.copy();
		api.editor.currentValue = newValue;
		api.save();
		return function(undo) api.editor.handleUndo(state, newValue, undo);
	}

	function handleUndo( state : UndoState, newValue : Any, undo : Bool ) {
		if( undo ) {
			api.undoState.shift();
			currentValue = state.data;
		} else {
			api.undoState.unshift(state);
			currentValue = newValue;
		}
		api.load(currentValue);
		refresh();
		api.save();
	}

	function showReferences() {
		if( cursor.table == null ) return;
		// todo : port from old cdb
	}

	function gotoReference() {
		var c = cursor.getCell();
		if( c == null || c.value == null ) return;
		switch( c.column.type ) {
		case TRef(s):
			var sd = base.getSheet(s);
			if( sd == null ) return;
			var k = sd.index.get(c.value);
			if( k == null ) return;
			var index = sd.lines.indexOf(k.obj);
			if( index >= 0 ) openReference(sd, index, 0);
		default:
		}
	}

	function openReference( s : cdb.Sheet, line : Int, column : Int ) {
		ide.open("hide.view.CdbTable", { path : s.name }, function(view) @:privateAccess Std.instance(view,hide.view.CdbTable).editor.cursor.setDefault(line,column));
	}

	function syncSheet() {
		// swap sheet if it was modified
		for( s in base.sheets )
			if( s.name == this.sheet.name ) {
				this.sheet = s;
				break;
			}
	}

	function refreshAll() {
		api.editor.refresh();
	}

	function refresh() {

		base.sync();

		element.empty();
		element.addClass('cdb');

		searchBox = new Element("<div>").addClass("searchBox").appendTo(element);
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
			new Element("<a>Add a column</a>").appendTo(element).click(function(_) {
				newColumn(sheet);
			});
			return;
		}

		var content = new Element("<table>");
		tables = [];
		new Table(this, sheet, content, displayMode);
		content.appendTo(element);

		if( cursor.table != null ) {
			for( t in tables )
				if( t.sheet == cursor.table.sheet )
					cursor.table = t;
			cursor.update();
		}
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
		if( table.displayMode == Properties ) {
			var ins = table.element.find("select.insertField");
			var options = [for( o in ins.find("option").elements() ) o.val()];
			ins.attr("size", options.length);
			options.shift();
			ins.focus();
			var index = 0;
			ins.val(options[0]);
			ins.off();
			ins.blur(function(_) table.refresh());
			ins.keydown(function(e) {
				switch( e.keyCode ) {
				case K.ESCAPE:
					element.focus();
				case K.UP if( index > 0 ):
					ins.val(options[--index]);
				case K.DOWN if( index < options.length - 1 ):
					ins.val(options[++index]);
				case K.ENTER:
					table.insertProperty(ins.val());
				default:
				}
				e.stopPropagation();
				e.preventDefault();
			});
			return;
		}
		beginChanges();
		table.sheet.newLine(index);
		endChanges();
		table.refresh();
	}

	public function popupColumn( table : Table, col : cdb.Data.Column ) {
		var menu : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
		if( col.type == TString && col.kind == Script )
			menu.push({ label : "Edit all", click : function() editScripts(table,col) });
		new hide.comp.ContextMenu(menu);
	}

	function editScripts( table : Table, col : cdb.Data.Column ) {
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

	public function close() {
		for( t in tables.copy() )
			t.dispose();
	}

	public function focus() {
		element.focus();
	}

}

