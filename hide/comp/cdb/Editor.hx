package hide.comp.cdb;
import hxd.Key in K;


enum Direction {
	Left;
	Right;
}
typedef UndoSheet = {
	var sheet : String;
	var parent : { sheet : UndoSheet, line : Int, column : Int };
}

typedef UndoState = {
	var data : Any;
	var sheet : String;
	var cursor : Cursor.CursorState;
	var tables : Array<UndoSheet>;
}

typedef EditorApi = {
	function load( data : Any ) : Void;
	function copy() : Any;
	function save() : Void;
}

typedef EditorColumnProps = {
	var ?formula : String;
	var ?ignoreExport : Bool;
	var ?categories : Array<String>;
}

typedef EditorSheetProps = {
	var ?categories : Array<String>;
}

@:allow(hide.comp.cdb)
class Editor extends Component {

	var base : cdb.Database;
	var currentSheet : cdb.Sheet;
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
	var currentFilter : String;
	var api : EditorApi;
	var undoState : Array<UndoState> = [];
	var currentValue : Any;
	var cdbTable : hide.view.CdbTable;
	public var view : cdb.DiffFile.ConfigView;
	public var config : hide.Config;
	public var cursor : Cursor;
	public var keys : hide.ui.Keys;
	public var undo : hide.ui.UndoHistory;
	public var cursorStates : Array<UndoState> = [];
	public var cursorIndex : Int = 0;
	public var formulas : Formulas;

	public function new(config, api, ?cdbTable) {
		super(null,null);
		this.api = api;
		this.config = config;
		this.cdbTable = cdbTable;
		view = cast this.config.get("cdb.view");
		undo = new hide.ui.UndoHistory();
	}

	public function getCurrentSheet() {
		return currentSheet == null ? null : currentSheet.name;
	}

	public function show( sheet, ?parent : Element ) {
		if( element != null ) element.remove();
		element = new Element('<div>');
		if( parent != null )
			parent.append(element);
		currentSheet = sheet;
		element.attr("tabindex", 0);
		element.addClass("is-cdb-editor");
		element.data("cdb", this);
		element.on("blur", function(_) cursor.hide());
		element.on("keypress", function(e) {
			if( e.target.nodeName == "INPUT" )
				return;
			var cell = cursor.getCell();
			if( cell != null && cell.isTextInput() && !e.ctrlKey )
				cell.edit();
		});
		element.contextmenu(function(e) e.preventDefault());

		if( cdbTable == null )
			element.mousedown(onMouseDown);
		else {
			cdbTable.element.off("mousedown", onMouseDown);
			cdbTable.element.mousedown(onMouseDown);
		}

		keys = new hide.ui.Keys(element);
		keys.addListener(onKey);
		keys.register("search", function() {
			searchBox.show();
			searchBox.find("input").val("").focus().select();
		});
		keys.register("copy", onCopy);
		keys.register("paste", onPaste);
		keys.register("delete", onDelete);
		keys.register("cdb.showReferences", showReferences);
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
		keys.register("cdb.moveBack", () -> cursorJump(true));
		keys.register("cdb.moveAhead", () -> cursorJump(false));
		keys.register("cdb.insertLine", function() { insertLine(cursor.table,cursor.y); cursor.move(0,1,false,false); });
		for( k in ["cdb.editCell","rename"] )
			keys.register(k, function() {
				var c = cursor.getCell();
				if( c != null ) c.edit();
			});
		keys.register("cdb.closeList", function() {
			var c = cursor.getCell();
			var sub = Std.downcast(c == null ? cursor.table : c.table, SubTable);
			if( sub != null ) {
				sub.cell.element.click();
				return;
			}
			if( cursor.select != null ) {
				cursor.select = null;
				cursor.update();
			}
		});
		keys.register("cdb.gotoReference", () -> gotoReference(cursor.getCell()));
		base = sheet.base;
		if( cursor == null )
			cursor = new Cursor(this);
		else if ( !tables.contains(cursor.table) )
			cursor.set();
		if( displayMode == null ) displayMode = Table;
		DataFiles.load();
		if( currentValue == null ) currentValue = api.copy();
		refresh();
	}

	function onMouseDown( e : js.jquery.Event ) {
		switch ( e.which ) {
		case 4:
			cursorJump(true);
			return false;
		case 5:
			cursorJump(false);
			return false;
		}
		return true;
	}

	function onKey( e : js.jquery.Event ) {
		if( e.altKey )
			return false;
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
		case K.PGUP:
			cursor.move(0, -10, e.shiftKey, e.ctrlKey);
			return true;
		case K.PGDOWN:
			cursor.move(0, 10, e.shiftKey, e.ctrlKey);
			return true;
		case K.SPACE:
			e.preventDefault(); // prevent scroll
		case K.ESCAPE:
			if( currentFilter != null ) {
				searchFilter(null);
				searchBox.hide();
			}
		}
		return false;
	}

	public function updateFilter() {
		searchFilter(currentFilter);
	}

	public function setFilter( f : String ) {
		if( searchBox != null ) {
			if( f == null )
				searchBox.hide();
			else {
				searchBox.show();
				searchBox.find("input").val(f);
			}
		}
		searchFilter(f);
	}

	function searchFilter( filter : String ) {
		if( filter == "" ) filter = null;
		if( filter != null ) filter = filter.toLowerCase();

		var all = element.find("table.cdb-sheet > tbody > tr").not(".head");
		var seps = all.filter(".separator");
		var lines = all.not(".separator");
		all.removeClass("filtered");
		if( filter != null ) {
			for( t in lines ) {
				if( t.textContent.toLowerCase().indexOf(filter) < 0 )
					t.classList.add("filtered");
			}
			while( lines.length > 0 ) {
				lines = lines.filter(".list").not(".filtered").prev();
				lines.removeClass("filtered");
			}
			all = all.not(".filtered").not(".hidden");
			for( s in seps.elements() ) {
				var idx = all.index(s);
				if( idx == all.length - 1 || new Element(all.get(idx+1)).hasClass("separator") ) {
					s.addClass("filtered");
				}
			}
		}
		currentFilter = filter;
		cursor.update();
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
				var c = cursor.table.columns[x];
				var form = @:privateAccess formulas.getFormulaNameFromValue(obj, c);
				if( form != null ) {
					Reflect.setField(out, c.name+"__f", form);
					continue;
				}
				var v = Reflect.field(obj, c.name);
				if( v != null )
					Reflect.setField(out, c.name, v);
			}
			data.push(out);
		}
		clipboard = {
			data : data,
			text : Std.string([for( o in data ) cursor.table.sheet.objToString(o,true)]),
			schema : [for( x in sel.x1...sel.x2+1 ) cursor.table.columns[x]],
		};
		ide.setClipboard(clipboard.text);
	}

	function onPaste() {
		var text = ide.getClipboard();
		var columns = cursor.table.columns;
		var sheet = cursor.table.sheet;
		var realSheet = cursor.table.getRealSheet();
		var allLines = cursor.table.lines;

		var fullRefresh = false;
		var toRefresh : Array<Cell> = [];

		var isProps = (cursor.table.displayMode != Table);
		var x1 = cursor.x;
		var y1 = cursor.y;
		var x2 = cursor.select == null ? x1 : cursor.select.x;
		var y2 = cursor.select == null ? y1 : cursor.select.y;
		if( x1 > x2 ) {
			var tmp = x1;
			x1 = x2;
			x2 = tmp;
		}
		if( y1 > y2 ) {
			var tmp = y1;
			y1 = y2;
			y2 = tmp;
		}

		if( clipboard == null || text != clipboard.text ) {
			if( cursor.x < 0 || cursor.y < 0 ) return;
			function parseText(text, type : cdb.Data.ColumnType) : Dynamic {
				switch( type ) {
				case TId:
					if( ~/^[A-Za-z0-9_]+$/.match(text) )
						return text;
				case TString:
					return text;
				case TFile:
					return ide.makeRelative(text);
				case TInt:
					text = text.split(",").join("").split(" ").join("");
					return Std.parseInt(text);
				case TFloat:
					text = text.split(",").join("").split(" ").join("");
					var value = Std.parseFloat(text);
					if( Math.isNaN(value) )
						return null;
					return value;
				default:
				}
				return null;
			}
			if( isProps ) {
				var line = cursor.getLine();
				toRefresh.push(cursor.getCell());
				var col = line.columns[x1];

				if( !cursor.table.canEditColumn(col.name) )
					return;

				var value = parseText(text, col.type);
				if( value == null )
					return;
				beginChanges();
				var obj = line.obj;
				formulas.removeFromValue(obj, col);
				Reflect.setField(obj, col.name, value);
			} else {
				beginChanges();
				for( x in x1...x2+1 ) {
					var col = columns[x];
					if( !cursor.table.canEditColumn(col.name) )
						continue;
					var lines = y1 == y2 ? [text] : text.split("\n");
					for( y in y1...y2+1 ) {
						var text = lines[y - y1];
						if( text == null ) text = lines[lines.length - 1];
						var value = parseText(text, col.type);
						if( value == null ) continue;
						var obj = sheet.lines[y];
						formulas.removeFromValue(obj, col);
						Reflect.setField(obj, col.name, value);
						toRefresh.push(allLines[y].cells[x]);
					}
				}
			}
			formulas.evaluateAll(realSheet);
			endChanges();
			realSheet.sync();
			for( c in toRefresh ) {
				c.refresh(true);
			}
			refreshRefs();
			return;
		}

		function setValue(cliObj, destObj, clipSchema : cdb.Data.Column, destCol : cdb.Data.Column) {
			var form = Reflect.field(cliObj, clipSchema.name+"__f");

			if( form != null && destCol.type.equals(clipSchema.type) ) {
				formulas.setForValue(destObj, sheet, destCol, form);
				return;
			}

			var f = base.getConvFunction(clipSchema.type, destCol.type);
			var v : Dynamic = Reflect.field(cliObj, clipSchema.name);
			if( f == null )
				v = base.getDefault(destCol, sheet);
			else {
				// make a deep copy to erase references
				if( v != null ) v = haxe.Json.parse(haxe.Json.stringify(v));
				if( f.f != null )
					v = f.f(v);
			}
			if( v == null && !destCol.opt )
				v = base.getDefault(destCol, sheet);
			if( v == null )
				Reflect.deleteField(destObj, destCol.name);
			else
				Reflect.setField(destObj, destCol.name, v);
		}

		var posX = cursor.x < 0 ? 0 : cursor.x;
		var posY = cursor.y < 0 ? 0 : cursor.y;
		var data = clipboard.data;
		if( data.length == 0 )
			return;

		if( isProps ) {
			var obj1 = data[0];
			var line = cursor.getLine();
			var destCol = line.columns[posX];
			var obj2 = line.obj;
			var clipSchema = clipboard.schema[0];
			if( clipSchema == null || destCol == null)
				return;
			if( !cursor.table.canEditColumn(destCol.name) )
				return;
			toRefresh.push(cursor.getCell());
			beginChanges();
			setValue(obj1, obj2, clipSchema, destCol);
		} else {
			beginChanges();
			if( data.length == 1 && y1 != y2 )
				data = [for( i in y1...y2+1 ) data[0]];
			for( obj1 in data ) {
				if( posY == sheet.lines.length ) {
					if( !cursor.table.canInsert() ) break;
					sheet.newLine();
					fullRefresh = true;
				}
				var obj2 = sheet.lines[posY];
				for( cid in 0...clipboard.schema.length ) {
					var c1 = clipboard.schema[cid];
					var c2 = columns[cid + posX];
					if( c2 == null ) continue;

					if( !cursor.table.canEditColumn(c2.name) )
						continue;

					setValue(obj1, obj2, c1, c2);
					if( c2.type == TList || c2.type == TProperties )
						fullRefresh = true;
					if( !fullRefresh )
						toRefresh.push(allLines[posY].cells[cid + posX]);
				}
				posY++;
			}
		}
		formulas.evaluateAll(realSheet);
		endChanges();
		realSheet.sync();
		if( fullRefresh )
			refreshAll();
		else {
			for( c in toRefresh ) {
				c.refresh(true);
			}
			refreshRefs();
		}
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
			if( !cursor.table.canInsert() ) {
				endChanges();
				return;
			}
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
					if( !line.cells[x].canEdit() )
						continue;
					var old = Reflect.field(line.obj, c.name);
					var def = base.getDefault(c,false,cursor.table.sheet);
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
		if( value == null ) {
			formulas.setForValue(line.obj, line.table.sheet, column, null);
		} else {
			Reflect.setField(line.obj, column.name, value);
			formulas.removeFromValue(line.obj, column);
		}
		line.table.getRealSheet().updateValue(column, line.index, prev);
		line.evaluate(); // propagate
		endChanges();
	}

	/**
		Call before modifying the database, allow to group several changes together.
		Allow recursion, only last endChanges() will trigger db save and undo point creation.
	**/
	public function beginChanges( ?structure : Bool ) {
		if( changesDepth == 0 )
			undoState.unshift(getState());
		changesDepth++;
	}

	function getState() : UndoState {
		return {
			data : currentValue,
			sheet : getCurrentSheet(),
			cursor : cursor.getState(),
			tables : [for( i in 1...tables.length ) {
				function makeParent(t:Table) : UndoSheet {
					var tp = t.parent;
					return { sheet : t.sheet.name, parent : tp == null ? null : {
						sheet : makeParent(tp),
						line : t.sheet.parent.line,
						column : tp.columns.indexOf(tp.sheet.columns[t.sheet.parent.column]),
					} };
				}
				makeParent(tables[i]);
			}],
		};
	}

	function setState( state : UndoState, doFocus : Bool ) {
		var cur = state.cursor;
		for( t in state.tables ) {
			function openRec(s:UndoSheet) : Table {
				if( s.parent != null ) {
					var t = openRec(s.parent.sheet);
					if( t != null ) {
						var cell = t.lines[s.parent.line].cells[t.displayMode == Properties || t.displayMode == AllProperties ? 0 : s.parent.column];
						if( cell.line.subTable == null && (cell.column.type == TList || cell.column.type == TProperties) )
							cell.open(true);
						return cell.line.subTable;
					}
				} else {
					for( tp in tables )
						if( tp.sheet.name == s.sheet )
							return tp;
				}
				return null;
			}
			openRec(t);
		}

		if( cur != null ) {
			var table = null;
			for( t in tables ) {
				if( t.sheet.getPath() == cur.sheet ) {
					table = t;
					break;
				}
			}
			if( table != null && doFocus )
				focus();
			cursor.setState(cur, table);
		} else
			cursor.set();
	}

	/**
		Call when changes are done, after endChanges.
	**/
	public function endChanges() {
		changesDepth--;
		if( changesDepth != 0 ) return;

		var newValue = api.copy();
		if( newValue == currentValue )
			return;
		var state = undoState[0];
		var newSheet = getCurrentSheet();
		currentValue = newValue;
		save();
		undo.change(Custom(function(undo) {
			var currentSheet;
			if( undo ) {
				undoState.shift();
				currentValue = state.data;
				currentSheet = state.sheet;
			} else {
				undoState.unshift(state);
				currentValue = newValue;
				currentSheet = newSheet;
			}
			pushCursorState();
			api.load(currentValue);
			DataFiles.save(true); // save reloaded data
			element.removeClass("is-cdb-editor");
			refreshAll();
			element.addClass("is-cdb-editor");
			syncSheet(currentSheet);
			refresh(state);
			save();
		}));
	}

	function save() {
		api.save();
	}


	function undoStatesEqual( s1 : UndoState, s2 : UndoState, cmpCursors = true ) {
		function cursorEqual(c1 : Cursor.CursorState, c2 : Cursor.CursorState) {
			if( c1 == c2 )
				return true;
			if( c1 == null || c2 == null )
				return false;
			return c1.sheet == c2.sheet && c1.x == c2.x && c1.y == c2.y;
		}
		function undoSheetEqual(s1 : UndoSheet, s2 : UndoSheet) {
			if( s1.parent == null && s2.parent == null )
				return s1.sheet == s2.sheet;
			if( s1.parent == null || s2.parent == null )
				return false;
			if ( s1.sheet != s2.sheet || s1.parent.column != s2.parent.column || s1.parent.line != s2.parent.line )
				return false;
			return undoSheetEqual(s1.parent.sheet, s2.parent.sheet);
		}
		if ( s1.sheet != s2.sheet )
			return false;
		if( s1.tables.length != s2.tables.length )
			return false;
		for( i in 0...s1.tables.length ) {
			if( !undoSheetEqual(s1.tables[i], s2.tables[i]) )
				return false;
		}
		if( !cmpCursors )
			return true;
		if( cursorEqual(s1.cursor, s2.cursor) )
			return true;
		if( s1.cursor == null || s2.cursor == null )
			return false;
		return s1.cursor.y == -1 && s2.cursor.y == -1;
	}

	public function pushCursorState() {
		if ( cursor == null )
			return;
		var state = getState();
		state.data = null;

		var stateBehind = (cursorStates.length <= 0) ? null : cursorStates[cursorIndex];
		if( stateBehind != null && undoStatesEqual(state, stateBehind) )
			return;
		var stateAhead = (cursorStates.length <= 0 || cursorIndex >= cursorStates.length - 1) ? null : cursorStates[cursorIndex + 1];
		if ( stateAhead != null && undoStatesEqual(state, stateAhead) ) {
			cursorIndex++;
			return;
		}

		if( cursorIndex < cursorStates.length - 1 && cursorIndex >= 0 ) {
			cursorStates.splice(cursorIndex + 1, cursorStates.length);
		}

		cursorStates.push(state);
		if( cursorIndex < cursorStates.length - 1 )
			cursorIndex++;
	}

	function cursorJump(back = true) {
		focus();

		if( (back && cursorIndex <= 0) || (!back && cursorIndex >= cursorStates.length - 1) )
			return;
		if( back && cursorIndex == cursorStates.length - 1)
			pushCursorState();

		if(back)
			cursorIndex--;
		else
			cursorIndex++;

		var state = cursorStates[cursorIndex];
		syncSheet(null, state.sheet);

		if( undoStatesEqual(state, getState(), false) ) {
			setState(state, true);
			if( cursor.table != null ) {
				for( t in tables ) {
					if( t.sheet.getPath() == cursor.table.sheet.getPath() )
						cursor.table = t;
				}
				cursor.update();
			}
		} else
			refresh(state);

		if( cdbTable != null )
			@:privateAccess cdbTable.syncTabs();
	}

	public static var inRefreshAll(default,null) : Bool;
	public static function refreshAll( eraseUndo = false ) {
		var editors : Array<Editor> = [for( e in new Element(".is-cdb-editor").elements() ) e.data("cdb")];
		DataFiles.load();
		inRefreshAll = true;
		for( e in editors ) {
			e.syncSheet(Ide.inst.database);
			e.refresh();
			// prevent undo over input changes
			if( eraseUndo ) {
				e.currentValue = e.api.copy();
				e.undo.clear();
				e.undoState = [];
			}
		}
		inRefreshAll = false;
	}

	function showReferences() {
		if( cursor.table == null ) return;
		var results = cursor.table.sheet.getReferences(cursor.y);
		if( results == null )
			return;
		if( results.length == 0 ) {
			ide.message("No reference found");
			return;
		}
		var message = [];
		for( rs in results ) {
			var path = [];
			for( i in 0...rs.s.length ) {
				var s = rs.s[i];
				var oid = Reflect.field(rs.o.path[i], s.id);
				var idx = rs.o.indexes[i];
				if( oid == null || oid == "" )
					path.push(s.s.name.split("@").pop() + (idx < 0 ? "" : "[" + idx +"]"));
				else
					path.push(oid);
			}
			path.push(rs.s[rs.s.length-1].c);
			message.push(rs.s[0].s.name+"  "+path.join("."));
		}
		ide.message(message.join("\n"));
	}

	function gotoReference( c : Cell ) {
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
		ide.open("hide.view.CdbTable", {}, function(view) Std.downcast(view,hide.view.CdbTable).goto(s,line,column));
	}

	public function syncSheet( ?base, ?name ) {
		if( base == null ) base = this.base;
		this.base = base;
		if( name == null ) name = getCurrentSheet();
		// swap sheet if it was modified
		this.currentSheet = null;
		for( s in base.sheets )
			if( s.name == name ) {
				this.currentSheet = s;
				break;
			}
	}

	function isUniqueID( sheet : cdb.Sheet, obj : {}, id : String ) {
		var uniq = base.getSheet(sheet.name).index.get(id);
		return uniq == null || uniq.obj == obj;
	}

	public function refreshRefs() {
		base.sync();

		for( t in tables ) {
			for( l in t.lines ) {
				for( c in l.cells ) {
					switch( c.column.type ){
					case TRef(_):
						c.refresh();
					case TString:
						if( c.column.kind == Script )
							c.refresh();
					default:
					}
				}
			}
		}
	}

	public function refresh( ?state : UndoState ) {
		if( state == null )
			state = getState();

		var hasFocus = element.find(":focus").length > 0;

		base.sync();

		element.empty();
		element.addClass('cdb');

		searchBox = new Element("<div>").addClass("searchBox").appendTo(element);
		var txt = new Element("<input type='text'>").appendTo(searchBox).keydown(function(e) {
			if( e.keyCode == 27 ) {
				searchBox.find("i").click();
				return;
			}
		}).keyup(function(e) {
			searchFilter(e.getThis().val());
		});
		new Element("<i>").addClass("ico ico-times-circle").appendTo(searchBox).click(function(_) {
			searchFilter(null);
			searchBox.toggle();
			var c = cursor.save();
			focus();
			cursor.load(c);
		});

		formulas = new Formulas(this);
		formulas.evaluateAll(currentSheet.realSheet);

		var content = new Element("<table>");
		tables = [];
		new Table(this, currentSheet, content, displayMode);
		content.appendTo(element);

		setState(state, hasFocus);

		if( cursor.table != null ) {
			for( t in tables )
				if( t.sheet.getPath() == cursor.table.sheet.getPath() )
					cursor.table = t;
			cursor.update();
		}

		if( currentFilter != null ) {
			updateFilter();
			searchBox.show();
			txt.val(currentFilter);
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

	public function getColumnProps( c : cdb.Data.Column ) {
		var pr : EditorColumnProps = c.editor;
		if( pr == null ) pr = {};
		return pr;
	}

	public function isColumnVisible( c : cdb.Data.Column ) {
		var props = getColumnProps(c);
		var cats = ide.projectConfig.dbCategories;
		return cats == null || props.categories == null || cats.filter(c -> props.categories.indexOf(c) >= 0).length > 0;
	}

	public function newColumn( sheet : cdb.Sheet, ?index : Int, ?onDone : cdb.Data.Column -> Void, ?col ) {
		var modal = new hide.comp.cdb.ModalColumnForm(this, sheet, col, element);
		modal.setCallback(function() {
			var c = modal.getColumn(col);
			if (c == null)
				return;
			beginChanges(true);
			var err;
			if( col != null )
				err = base.updateColumn(sheet, col, c);
			else
				err = sheet.addColumn(c, index == null ? null : index + 1);
			endChanges();
			if (err != null) {
				modal.error(err);
				return;
			}
			// perform side effects before refresh
			if( onDone != null )
				onDone(c);
			// if first column or subtable, refresh all
			if( sheet.columns.length == 1 || sheet.name.indexOf("@") > 0 )
				refresh();
			for( t in tables )
				if( t.sheet == sheet )
					t.refresh();
			modal.closeModal();
		});
	}

	public function editColumn( sheet : cdb.Sheet, col : cdb.Data.Column ) {
		newColumn(sheet,col);
	}

	public function insertLine( table : Table, index = 0 ) {
		if( !table.canInsert() )
			return;
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
					@:privateAccess table.insertProperty(ins.val());
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

	public function popupColumn( table : Table, col : cdb.Data.Column, ?cell : Cell ) {
		if( view != null )
			return;
		var sheet = table.getRealSheet();
		var indexColumn = sheet.columns.indexOf(col);
		var menu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{ label : "Edit", click : function () editColumn(sheet, col) },
			{ label : "Add Column", click : function () newColumn(sheet, indexColumn) },
			{ label : "", isSeparator: true },
			{ label : "Move Left", enabled:  (indexColumn > 0 &&
				nextVisibleColumnIndex(table, indexColumn, Left) > -1), click : function () {
				beginChanges();
				var nextIndex = nextVisibleColumnIndex(table, indexColumn, Left);
				sheet.columns.remove(col);
				sheet.columns.insert(nextIndex, col);
				if (cursor.x == indexColumn)
					cursor.set(cursor.table, nextIndex, cursor.y);
				else if (cursor.x == nextIndex)
					cursor.set(cursor.table, nextIndex + 1, cursor.y);
				endChanges();
				refresh();
			}},
			{ label : "Move Right", enabled: (indexColumn < sheet.columns.length - 1 &&
				nextVisibleColumnIndex(table, indexColumn, Right) < sheet.columns.length), click : function () {
				beginChanges();
				var nextIndex = nextVisibleColumnIndex(table, indexColumn, Right);
				sheet.columns.remove(col);
				sheet.columns.insert(nextIndex, col);
				if (cursor.x == indexColumn)
					cursor.set(cursor.table, nextIndex, cursor.y);
				else if (cursor.x == nextIndex)
					cursor.set(cursor.table, nextIndex - 1, cursor.y);
				endChanges();
				refresh();
			}},
			{ label: "", isSeparator: true },
			{ label : "Delete", click : function () {
				if( table.displayMode == Properties ) {
					beginChanges();
					changeObject(cell.line, col, base.getDefault(col,sheet));
				} else {
					beginChanges(true);
					sheet.deleteColumn(col.name);
				}
				endChanges();
				refresh();
			}}
		];

		if( table.parent == null ) {
			var props = table.sheet.props;
			switch( col.type ) {
			case TString, TRef(_):
				menu.push({ label : "Display Name", click : function() {
					beginChanges();
					props.displayColumn = (props.displayColumn == col.name ? null : col.name);
					endChanges();
					refresh();
				}, checked: props.displayColumn == col.name });
			case TTilePos:
				menu.push({ label : "Display Icon", click : function() {
					beginChanges();
					props.displayIcon = (props.displayIcon == col.name ? null : col.name);
					endChanges();
					refresh();
				}, checked: props.displayIcon == col.name });
			default:
			}

			var editProps = getColumnProps(col);
			menu.push({ label : "Categories", menu: categoriesMenu(editProps.categories, function(cats) {
				beginChanges();
				editProps.categories = cats;
				col.editor = editProps;
				endChanges();
				refresh();
			})});

			switch(col.type) {
			case TId | TString:
				menu.push({ label : "Sort", click: () -> table.sortBy(col) });
			default:
			}
		}

		if( col.type == TString && col.kind == Script )
			menu.insert(1,{ label : "Edit all", click : function() editScripts(table,col) });
		if( table.displayMode == Properties ) {
			menu.push({ label : "Delete All", click : function() {
				if( !ide.confirm("Delete row for all Props?") )
					return;
				beginChanges(true);
				table.sheet.deleteColumn(col.name);
				endChanges();
				refresh();
			}});
		}
		new hide.comp.ContextMenu(menu);
	}

	function nextVisibleColumnIndex( table : Table, index : Int, dir : Direction){
		var next = index;
		do {
			next += (dir == Left ? -1 : 1);
		}
		while (next >= 0 && next <= table.columns.length - 1 && !isColumnVisible(table.columns[next]));
		return next;
	}

	function editScripts( table : Table, col : cdb.Data.Column ) {
		// TODO : create single edit-all script view allowing global search & replace
	}

	function moveLine( line : Line, delta : Int ) {
		if( !line.table.canInsert() )
			return;
		beginChanges();
		var prevIndex = line.index;

		var distance = (delta >= 0 ? delta : -1 * delta);
		var index : Null<Int> = null;
		var currIndex : Null<Int> = line.index;
		for( _ in 0...distance ) {
			currIndex = line.table.sheet.moveLine( currIndex, delta );
			if( currIndex == null )
				break;
			else
				index = currIndex;
		}

		if( index != null ) {
			if (index != prevIndex) {
				if ( cursor.y == prevIndex ) cursor.set(cursor.table, cursor.x, index);
				else if ( cursor.y > prevIndex && cursor.y <= index) cursor.set(cursor.table, cursor.x, cursor.y - 1);
				else if ( cursor.y < prevIndex && cursor.y >= index) cursor.set(cursor.table, cursor.x, cursor.y + 1);
			}
			refresh();
		}
		endChanges();
	}

	function moveLines(lines : Array<Line>, delta : Int) {
		if( lines.length == 0 || !lines[0].table.canInsert() || delta == 0 )
			return;
		beginChanges();
		lines.sort((a, b) -> { return (a.index - b.index) * delta * -1; });
		for( l in lines ) {
			moveLine(l, delta);
		}
		endChanges();
	}

	function separatorCount( sheet : cdb.Sheet, fromLine : Int, toSep : Int ) {
		var count = 0;
		if( fromLine >= sheet.separators[toSep] ) {
			for( i in (toSep + 1)...sheet.separators.length ) {
				if( sheet.separators[i] > fromLine )
					break;
				count--;
			}
		} else {
			for( i in 0...(toSep + 1) ) {
				if( sheet.separators[i] <= fromLine )
					continue;
				count++;
			}
		}
		return count;
	}

	public function popupLine( line : Line ) {
		if( !line.table.canInsert() )
			return;
		var sheet = line.table.sheet;
		var selection = cursor.getSelectedLines();
		var isSelectedLine = false;
		for( l in selection ) {
			if( l == line ) {
				isSelectedLine = true;
				break;
			}
		}
		var firstLine = isSelectedLine ? selection[0] : line;
		var lastLine = isSelectedLine ? selection[selection.length - 1] : line;

		var sepIndex = sheet.separators.indexOf(line.index);
		var moveSubmenu : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
		if( sheet.props.separatorTitles != null ) {
			for( i in 0...sheet.separators.length ) {
				if( sheet.props.separatorTitles[i] == null )
					continue;
				var lastOfGroup = (i == sheet.separators.length - 1) ? line.table.lines.length : sheet.separators[i + 1];
				var usedLine = firstLine;
				if( lastOfGroup > line.index ) {
					lastOfGroup--;
					usedLine = lastLine;
				}
				var delta = lastOfGroup - usedLine.index + separatorCount(sheet, usedLine.index, i);
				moveSubmenu.push({
					label : sheet.props.separatorTitles[i],
					enabled : true,
					click : isSelectedLine ? moveLines.bind(selection, delta) : moveLine.bind(usedLine, delta),
				});
			}
		}

		var hasLocText = false;
		function checkRec(s:cdb.Sheet) {
			for( c in s.columns ) {
				switch( c.type ) {
				case TList, TProperties:
					var sub = s.getSub(c);
					checkRec(sub);
				case TString if( c.kind == Localizable ):
					hasLocText = true;
				default:
				}
			}
		}
		if( sheet.parent == null )
			checkRec(sheet);

		var menu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{
				label : "Move Up",
				enabled:  (firstLine.index > 0 || sepIndex >= 0),
				click : isSelectedLine ? moveLines.bind(selection, -1) : moveLine.bind(line, -1),
			},
			{
				label : "Move Down",
				enabled:  (lastLine.index < sheet.lines.length - 1),
				click : isSelectedLine ? moveLines.bind(selection, 1) : moveLine.bind(line, 1),
			},
			{ label : "Move to Group", enabled : sheet.props.separatorTitles != null, menu : moveSubmenu },
			{ label : "", isSeparator : true },
			{ label : "Insert", click : function() {
				insertLine(line.table,line.index);
				cursor.set(line.table, -1, line.index + 1);
				focus();
			}, keys : config.get("key.cdb.insertLine") },
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
		];
		if( hasLocText ) {
			menu.push({ label : "", isSeparator : true });
			menu.push({
				label : "Export Localized Texts",
				checked : !Reflect.hasField(line.obj,cdb.Lang.IGNORE_EXPORT_FIELD),
				click : function() {
					beginChanges();
					if( Reflect.hasField(line.obj,cdb.Lang.IGNORE_EXPORT_FIELD) )
						Reflect.deleteField(line.obj,cdb.Lang.IGNORE_EXPORT_FIELD);
					else
						Reflect.setField(line.obj,cdb.Lang.IGNORE_EXPORT_FIELD, true);
					endChanges();
					line.syncClasses();
				},
			});
		}
		new hide.comp.ContextMenu(menu);
	}

	function rename( sheet : cdb.Sheet, name : String ) {
		if( !base.r_ident.match(name) ) {
			ide.error("Invalid sheet name");
			return false;
		}
		var f = base.getSheet(name);
		if( f != null ) {
			if( f != sheet ) ide.error("Sheet name already in use");
			return false;
		}
		beginChanges();
		var old = sheet.name;
		sheet.rename(name);
		base.mapType(function(t) {
			return switch( t ) {
			case TRef(o) if( o == old ):
				TRef(name);
			case TLayer(o) if( o == old ):
				TLayer(name);
			default:
				t;
			}
		});

		for( s in base.sheets )
			if( StringTools.startsWith(s.name, old + "@") )
				s.rename(name + "@" + s.name.substr(old.length + 1));
		endChanges();
		DataFiles.save(true,[ sheet.name => old ]);
		return true;
	}

	function categoriesMenu(categories: Array<String>, setFunc : Array<String> -> Void) {
		var menu : Array<ContextMenu.ContextMenuItem> = [{ label : "Set...", click : function() {
			var wstr = "";
			if(categories != null)
				wstr = categories.join(",");
			wstr = ide.ask("Set Categories (comma separated)", wstr);
			if(wstr == null)
				return;
			categories = [for(s in wstr.split(",")) { var t = StringTools.trim(s); if(t.length > 0) t; }];
			setFunc(categories.length > 0 ? categories : null);
			ide.initMenu();
		}}];

		for(name in getCategories(base)) {
			var has = categories != null && categories.indexOf(name) >= 0;
			menu.push({
				label: name, checked: has, stayOpen: true, click: function() {
					if(has)
						categories.remove(name);
					else {
						if(categories == null)
							categories = [];
						categories.push(name);
					}
					has = !has;
					setFunc(categories.length > 0 ? categories : null);
				}
			});
		}

		return menu;
	}

	public function popupSheet( ?sheet : cdb.Sheet, ?onChange : Void -> Void ) {
		if( view != null )
			return;
		if( sheet == null ) sheet = this.currentSheet;
		if( onChange == null ) onChange = function() {}
		var index = base.sheets.indexOf(sheet);

		var content : Array<ContextMenu.ContextMenuItem> = [
			{ label : "Add Sheet", click : function() { beginChanges(); var db = ide.createDBSheet(index+1); endChanges(); if( db != null ) onChange(); } },
			{ label : "Move Left", click : function() { beginChanges(); base.moveSheet(sheet,-1); endChanges(); onChange(); } },
			{ label : "Move Right", click : function() { beginChanges(); base.moveSheet(sheet,1); endChanges(); onChange(); } },
			{ label : "Rename", click : function() {
				var name = ide.ask("New name", sheet.name);
				if( name == null || name == "" || name == sheet.name ) return;
				if( !rename(sheet, name) ) return;
				onChange();
			}},
			{ label : "Delete", click : function() {
				beginChanges();
				base.deleteSheet(sheet);
				endChanges();
				onChange();
			}},
			{ label : "Categories", menu: categoriesMenu(getSheetProps(sheet).categories, function(cats) {
				beginChanges();
				var props = getSheetProps(sheet);
				props.categories = cats;
				sheet.props.editor = props;
				endChanges();
				onChange();
			})},
			{ label : "", isSeparator: true },

		];
		if( sheet.props.dataFiles == null )
			content = content.concat([
				{ label : "Add Index", checked : sheet.props.hasIndex, click : function() {
					beginChanges();
					if( sheet.props.hasIndex ) {
						for( o in sheet.getLines() )
							Reflect.deleteField(o, "index");
						sheet.props.hasIndex = false;
					} else {
						for( c in sheet.columns )
							if( c.name == "index" ) {
								ide.error("Column 'index' already exists");
								return;
							}
						sheet.props.hasIndex = true;
					}
					endChanges();
				}},
				{ label : "Add Group", checked : sheet.props.hasGroup, click : function() {
					beginChanges();
					if( sheet.props.hasGroup ) {
						for( o in sheet.getLines() )
							Reflect.deleteField(o, "group");
						sheet.props.hasGroup = false;
					} else {
						for( c in sheet.columns )
							if( c.name == "group" ) {
								ide.error("Column 'group' already exists");
								return;
							}
						sheet.props.hasGroup = true;
					}
					endChanges();
				}},
			]);
		if( sheet.lines.length == 0 || sheet.props.dataFiles != null )
			content.push({
				label : "Data Files",
				checked : sheet.props.dataFiles != null,
				click : function() {
					var txt = ide.ask("Data Files Path", sheet.props.dataFiles);
					if( txt == null ) return;
					txt = StringTools.trim(txt);
					beginChanges();
					if( txt == "" ) {
						Reflect.deleteField(sheet.props,"dataFile");
						@:privateAccess sheet.sheet.lines = [];
					} else {
						sheet.props.dataFiles = txt;
						@:privateAccess sheet.sheet.lines = null;
						DataFiles.load();
					}
					endChanges();
					refresh();
				}
			});
		new ContextMenu(content);
	}

	public function close() {
		for( t in tables.copy() )
			t.dispose();
	}

	public function focus() {
		if( element.is(":focus") ) return;
		(element[0] : Dynamic).focus({ preventScroll : true });
	}

	static public function getSheetProps( s : cdb.Sheet ) {
		var pr : EditorSheetProps = s.props.editor;
		if( pr == null ) pr = {};
		return pr;
	}

	static public function getCategories(db: cdb.Database) : Array<String> {
		var names : Array<String> = [];
		for( s in db.sheets ) {
			var props = getSheetProps(s);
			if(props.categories != null) {
				for(n in props.categories)
					if(names.indexOf(n) < 0)
						names.push(n);
			}
		}
		names.sort((a, b) -> Reflect.compare(a, b));
		return names;
	}
}

