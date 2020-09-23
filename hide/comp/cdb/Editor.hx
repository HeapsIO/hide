package hide.comp.cdb;
import hxd.Key in K;

typedef UndoSheet = {
	var sheet : String;
	var parent : { sheet : UndoSheet, line : Int, column : Int };
}

typedef UndoState = {
	var data : Any;
	var sheet : String;
	var cursor : { sheet : String, x : Int, y : Int, select : Null<{ x : Int, y : Int }> };
	var tables : Array<UndoSheet>;
}

typedef EditorApi = {
	function load( data : Any ) : Void;
	function copy() : Any;
	function save() : Void;
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
	public var view : cdb.DiffFile.ConfigView;
	public var config : hide.Config;
	public var cursor : Cursor;
	public var keys : hide.ui.Keys;
	public var undo : hide.ui.UndoHistory;

	public function new(config,api) {
		super(null,null);
		this.api = api;
		this.config = config;
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
		keys.register("cdb.gotoReference", gotoReference);
		base = sheet.base;
		cursor = new Cursor(this);
		if( displayMode == null ) displayMode = Table;
		DataFiles.load();
		if( currentValue == null ) currentValue = api.copy();
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
		if( clipboard == null || text != clipboard.text ) {
			if( cursor.x < 0 || cursor.y < 0 ) return;
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
			beginChanges();
			for( x in x1...x2+1 ) {
				var col = columns[x];
				if( !cursor.table.canEditColumn(col.name) )
					continue;
				var lines = y1 == y2 ? [text] : text.split("\n");
				for( y in y1...y2+1 ) {
					var value : Dynamic = null;
					var text = lines[y - y1];
					if( text == null ) text = lines[lines.length - 1];
					switch( col.type ) {
					case TId:
						if( ~/^[A-Za-z0-9_]+$/.match(text) ) value = text;
					case TString:
						value = text;
					case TInt:
						text = text.split(",").join("").split(" ").join("");
						value = Std.parseInt(text);
					case TFloat:
						text = text.split(",").join("").split(" ").join("");
						value = Std.parseFloat(text);
						if( Math.isNaN(value) ) value = null;
					default:
					}
					if( value == null ) continue;
					var obj = sheet.lines[y];
					Reflect.setField(obj, col.name, value);
				}
			}
			endChanges();
			realSheet.sync();
			refreshAll();
			return;
		}
		beginChanges();
		var posX = cursor.x < 0 ? 0 : cursor.x;
		var posY = cursor.y < 0 ? 0 : cursor.y;
		for( obj1 in clipboard.data ) {
			if( posY == sheet.lines.length ) {
				if( !cursor.table.canInsert() ) break;
				sheet.newLine();
			}
			var obj2 = sheet.lines[posY];
			for( cid in 0...clipboard.schema.length ) {
				var c1 = clipboard.schema[cid];
				var c2 = columns[cid + posX];
				if( c2 == null ) continue;

				if( !cursor.table.canEditColumn(c2.name) )
					continue;

				var f = base.getConvFunction(c1.type, c2.type);
				var v : Dynamic = Reflect.field(obj1, c1.name);
				if( f == null )
					v = base.getDefault(c2, sheet);
				else {
					// make a deep copy to erase references
					if( v != null ) v = haxe.Json.parse(haxe.Json.stringify(v));
					if( f.f != null )
						v = f.f(v);
				}
				if( v == null && !c2.opt )
					v = base.getDefault(c2, sheet);
				if( v == null )
					Reflect.deleteField(obj2, c2.name);
				else
					Reflect.setField(obj2, c2.name, v);
			}
			posY++;
		}
		endChanges();
		realSheet.sync();
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
		if( value == null )
			Reflect.deleteField(line.obj, column.name);
		else
			Reflect.setField(line.obj, column.name, value);
		line.table.getRealSheet().updateValue(column, line.index, prev);
		endChanges();
	}

	/**
		Call before modifying the database, allow to group several changes together.
		Allow recursion, only last endChanges() will trigger db save and undo point creation.
	**/
	public function beginChanges() {
		if( changesDepth == 0 )
			undoState.unshift(getState());
		changesDepth++;
	}

	function getState() : UndoState {
		return {
			data : currentValue,
			sheet : getCurrentSheet(),
			cursor : cursor.table == null ? null : {
				sheet : cursor.table.sheet.name,
				x : cursor.x,
				y : cursor.y,
				select : cursor.select == null ? null : { x : cursor.select.x, y : cursor.select.y }
			},
			tables : [for( i in 1...tables.length ) {
				var t = tables[i];
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
						if( cell.line.subTable == null )
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
			for( t in tables )
				if( t.sheet.name == cur.sheet ) {
					table = t;
					break;
				}
			if( table != null && doFocus )
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

	public static function refreshAll( eraseUndo = false ) {
		var editors : Array<Editor> = [for( e in new Element(".is-cdb-editor").elements() ) e.data("cdb")];
		DataFiles.load();
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
		new Element("<i>").addClass("fa fa-times-circle").appendTo(searchBox).click(function(_) {
			searchFilter(null);
			searchBox.toggle();
			var c = cursor.save();
			focus();
			cursor.load(c);
		});

		var content = new Element("<table>");
		tables = [];
		new Table(this, currentSheet, content, displayMode);
		content.appendTo(element);

		if( state != null )
			setState(state, hasFocus);

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

	public function newColumn( sheet : cdb.Sheet, ?index : Int, ?onDone : cdb.Data.Column -> Void, ?col ) {
		var modal = new hide.comp.cdb.ModalColumnForm(base, sheet, col, element);
		modal.setCallback(function() {
			var c = modal.getColumn(base, sheet, col);
			if (c == null)
				return;
			beginChanges();
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

	public function popupColumn( table : Table, col : cdb.Data.Column, ?cell : Cell ) {
		if( view != null )
			return;
		var sheet = table.getRealSheet();
		var indexColumn = sheet.columns.indexOf(col);
		var menu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{ label : "Edit", click : function () editColumn(sheet, col) },
			{ label : "Add Column", click : function () newColumn(sheet, indexColumn) },
			{ label : "", isSeparator: true },
			{ label : "Move Left", enabled:  (indexColumn > 0), click : function () {
				beginChanges();
				sheet.columns.remove(col);
				sheet.columns.insert(indexColumn - 1, col);
				endChanges();
				refresh();
			}},
			{ label : "Move Right", enabled: (indexColumn < sheet.columns.length - 1), click : function () {
				beginChanges();
				sheet.columns.remove(col);
				sheet.columns.insert(indexColumn + 1, col);
				endChanges();
				refresh();
			}},
			{ label: "", isSeparator: true },
			{ label : "Delete", click : function () {
				beginChanges();
				if( table.displayMode == Properties )
					changeObject(cell.line, col, base.getDefault(col,sheet));
				else
					sheet.deleteColumn(col.name);
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
		}

		if( col.type == TString && col.kind == Script )
			menu.insert(1,{ label : "Edit all", click : function() editScripts(table,col) });
		if( table.displayMode == Properties ) {
			menu.push({ label : "Delete All", click : function() {
				beginChanges();
				table.sheet.deleteColumn(col.name);
				endChanges();
				refresh();
			}});
		}
		new hide.comp.ContextMenu(menu);
	}

	function editScripts( table : Table, col : cdb.Data.Column ) {
		// TODO : create single edit-all script view allowing global search & replace
	}

	function moveLine( line : Line, delta : Int ) {
		if( !line.table.canInsert() )
			return;
		beginChanges();
		var index = line.table.sheet.moveLine(line.index, delta);
		if( index != null ) {
			cursor.set(cursor.table, -1, index);
			refresh();
		}
		endChanges();
	}

	public function popupLine( line : Line ) {
		if( !line.table.canInsert() )
			return;
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
		return true;
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
					beginChanges();
					var txt = StringTools.trim(ide.ask("Data Files Path", sheet.props.dataFiles));
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

}

