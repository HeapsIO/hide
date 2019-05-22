package hide.comp.cdb;
import hxd.Key in K;

typedef UndoState = {
	var data : Any;
	var cursor : { sheet : String, x : Int, y : Int, select : Null<{ x : Int, y : Int }> };
	var tables : Array<{ sheet : String, parent : { sheet : String, line : Int, column : Int } }>;
}

typedef EditorApi = {
	function load( data : Any ) : Void;
	function copy() : Any;
	function save() : Void;
	var ?currentValue : Any;
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
		if( api.currentValue == null ) api.currentValue = api.copy();
		this.undo = api.undo == null ? new hide.ui.UndoHistory() : api.undo;
		api.undo = undo;
		init();
	}

	function init() {
		element.attr("tabindex", 0);
		element.on("focus", function(_) onFocus());
		element.on("blur", function(_) cursor.hide());
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
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
		keys.register("cdb.insertLine", function() { insertLine(cursor.table,cursor.y); cursor.move(0,1,false,false); });
		for( k in ["cdb.editCell","rename"] )
			keys.register(k, function() {
				var c = cursor.getCell();
				if( c != null ) c.edit();
			});
		keys.register("cdb.closeList", function() {
			var c = cursor.getCell();
			var sub = Std.instance(c == null ? cursor.table : c.table, SubTable);
			if( sub != null ) {
				sub.cell.element.click();
				return;
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

		var lines = element.find("table.cdb-sheet > tbody > tr");
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
				line.table.sheet.deleteLine(line.index);
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
		if( changesDepth == 0 )
			api.undoState.unshift(getState());
		changesDepth++;
	}

	function getState() : UndoState {
		return {
			data : api.currentValue,
			cursor : cursor.table == null ? null : {
				sheet : cursor.table.sheet.name,
				x : cursor.x,
				y : cursor.y,
				select : cursor.select == null ? null : { x : cursor.select.x, y : cursor.select.y }
			},
			tables : [for( i in 1...tables.length ) {
				var t = tables[i];
				var tp = t.sheet.parent;
				{ sheet : t.sheet.name, parent : { sheet : tp.sheet.name, line : tp.line, column : tp.column } }
			}],
		};
	}

	function setState( state : UndoState ) {
		var cur = state.cursor;
		for( t in state.tables ) {
			var tparent = null;
			for( tp in tables )
				if( tp.sheet.name == t.parent.sheet ) {
					tparent = tp;
					break;
				}
			if( tparent != null )
				tparent.lines[t.parent.line].cells[t.parent.column].open(true);
		}

		if( cur != null ) {
			var table = null;
			for( t in tables )
				if( t.sheet.name == cur.sheet ) {
					table = t;
					break;
				}
			if( table != null )
				focus();
			cursor.set(table, cur.x, cur.y, cur.select == null ? null : { x : cur.select.x, y : cur.select.y } );
		} else
			cursor.set();
	}

	/**
		Call when changes are done, after endChanges.
	**/
	public function endChanges() {
		changesDepth--;
		if( changesDepth == 0 ) {
			var f = makeCustom(api);
			if( f != null ) undo.change(Custom(f));
		}
	}

	// do not reference "this" editor in undo state !
	static function makeCustom( api : EditorApi ) {
		var newValue = api.copy();
		if( newValue == api.currentValue )
			return null;
		var state = api.undoState[0];
		api.currentValue = newValue;
		api.save();
		return function(undo) api.editor.handleUndo(state, newValue, undo);
	}

	function handleUndo( state : UndoState, newValue : Any, undo : Bool ) {
		if( undo ) {
			api.undoState.shift();
			api.currentValue = state.data;
		} else {
			api.undoState.unshift(state);
			api.currentValue = newValue;
		}
		api.load(api.currentValue);
		refreshAll(state);
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

	public function syncSheet( ?base ) {
		if( base == null ) base = this.base;
		this.base = base;

		// swap sheet if it was modified
		for( s in base.sheets )
			if( s.name == this.sheet.name ) {
				this.sheet = s;
				break;
			}
	}

	function refreshAll( ?state : UndoState ) {
		api.editor.refresh(state);
	}

	public function refresh( ?state : UndoState ) {

		if( state == null )
			state = getState();

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

		if( state != null )
			setState(state);

		if( cursor.table != null ) {
			for( t in tables )
				if( t.sheet.name == cursor.table.sheet.name )
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

	public function newColumn( sheet : cdb.Sheet, ?index : Int ) {
		var modal = new hide.comp.cdb.ModalColumnForm(base, null, element);
		modal.setCallback(function() {
			var c = modal.getColumn(base, sheet, null);
			if (c == null) {
				return;
			}
			var err = newColumn_save(sheet, c, index + 1);
			if (err != null) {
				modal.error(err);
			} else {
				modal.closeModal();
			}
		});
	}

	function newColumn_save( sheet : cdb.Sheet, c : cdb.Data.Column, ?index : Int ) {
		beginChanges();
		var err = sheet.addColumn(c, index);
		endChanges();
		if (err != null) {
			return err;
		}
		for( t in tables )
			if( t.sheet == sheet )
				t.refresh();
		return null;
	}

	public function editColumn( sheet : cdb.Sheet, col : cdb.Data.Column ) {
		var modal = new hide.comp.cdb.ModalColumnForm(base, col, element);
		modal.setCallback(function() {
			var c = modal.getColumn(base, sheet, col);
			if (c == null) {
				return;
			}
			var err = editColumn_save(base, sheet, col, c);
			if (err != null) {
				modal.error(err);
			} else {
				modal.closeModal();
			}
		});
	}

	function editColumn_save( base : cdb.Database, sheet : cdb.Sheet, colOld : cdb.Data.Column, colNew : cdb.Data.Column ) {
		beginChanges();
		var err = base.updateColumn(sheet, colOld, colNew);
		endChanges();
		for( t in tables )
			if( t.sheet == sheet )
				t.refresh();
		if (err != null) {
			return err;
		}
		return null;
	}

	public function deleteColumn( sheet : cdb.Sheet, cname : String ) {
		beginChanges();
		sheet.deleteColumn(cname);
		endChanges();
	}

	public function moveColumnLeft( sheet : cdb.Sheet, index : Int ) {
		beginChanges();
		var c = sheet.columns[index];
		if( index > 0 ) {
			sheet.columns.remove(c);
			sheet.columns.insert(index - 1, c);
		}
		endChanges();
	}

	public function moveColumnRight( sheet : cdb.Sheet, index : Int ) {
		beginChanges();
		var c = sheet.columns[index];
		if( index > 0 ) {
			sheet.columns.remove(c);
			sheet.columns.insert(index + 1, c);
		}
		endChanges();
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
		var indexColumn = 0;
		for (c in table.sheet.columns) {
			if (c == col) {
				break;
			}
			indexColumn++;
		}
		var menu : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
		if( col.type == TString && col.kind == Script )
			menu.push({ label : "Edit all", click : function() editScripts(table,col) });

		menu.push({ label : "Edit", click : function () {
				editColumn(table.sheet, col);
			}
		});

		menu.push({ label : "Add Column", click : function () {
				newColumn(table.sheet, indexColumn);
			}
		});

		menu.push({ label: "sep", isSeparator: true });
		menu.push({ label : "Move Left", enabled:  (indexColumn > 0), click : function () {
				moveColumnLeft(table.sheet, indexColumn);
				table.refresh();
			}
		});
		menu.push({ label : "Move Right", enabled: (indexColumn < table.sheet.columns.length - 1), click : function () {
				moveColumnRight(table.sheet, indexColumn);
				table.refresh();
			}
		});
		menu.push({ label: "sep", isSeparator: true });

		menu.push({ label : "Delete", click : function () {
				deleteColumn(table.sheet, col.name);
				table.refresh();
			}
		});
		new hide.comp.ContextMenu(menu);
	}

	function editScripts( table : Table, col : cdb.Data.Column ) {
	}

	function moveLine( line : Line, delta : Int ) {
		beginChanges();
		var index = sheet.moveLine(line.index, delta);
		if( index != null ) {
			cursor.set(cursor.table, -1, index);
			refresh();
		}
		endChanges();
	}

	public function popupLine( line : Line ) {
		var sheet = line.table.sheet;
		var sepIndex = sheet.separators.indexOf(line.index);
		new hide.comp.ContextMenu([
			{ label : "Move Up", click : moveLine.bind(line,-1) },
			{ label : "Move Down", click : moveLine.bind(line,1) },
			{ label : "Insert", click : function() {
				insertLine(line.table,line.index);
				cursor.move(0,1,false,false);
			} },
			{ label : "Delete", click : function() {
				beginChanges();
				sheet.deleteLine(line.index);
				endChanges();
				refreshAll();
			} },
			{ label : "Separator", enabled : !sheet.props.hide, checked : sepIndex >= 0, click : function() {
				beginChanges();
				if( sepIndex >= 0 ) {
					sheet.separators.splice(sepIndex, 1);
					if( sheet.props.separatorTitles != null ) sheet.props.separatorTitles.splice(sepIndex, 1);
				} else {
					sepIndex = sheet.separators.length;
					for( i in 0...sheet.separators.length )
						if( sheet.separators[i] > line.index ) {
							sepIndex = i;
							break;
						}
					sheet.separators.insert(sepIndex, line.index);
					if( sheet.props.separatorTitles != null && sheet.props.separatorTitles.length > sepIndex )
						sheet.props.separatorTitles.insert(sepIndex, null);
				}
				endChanges();
				refresh();
			} }
		]);
	}

	public function close() {
		for( t in tables.copy() )
			t.dispose();
	}

	public function focus() {
		if( element.is(":focus") ) return;
		element.focus();
		onFocus();
	}

	public dynamic function onFocus() {
	}

}

