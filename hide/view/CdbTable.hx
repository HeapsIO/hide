package hide.view;

class CdbTable extends hide.ui.View<{}> {

	var tabContents : Array<Element>;
	var editor : hide.comp.cdb.Editor;
	var currentSheet : String;
	var tabCache : String;
	var tabs : hide.comp.Tabs;
	var view : cdb.DiffFile.ConfigView;

	public function new( ?state ) {
		super(state);
		editor = new hide.comp.cdb.Editor(config, {
			copy : () -> (ide.database.save() : Any),
			load : (v:Any) -> ide.database.load((v:String)),
			save : function() {
				ide.saveDatabase();
				haxe.Timer.delay(syncTabs,0);
			}
		}, this);
		undo = editor.undo;
		currentSheet = this.config.get("cdb.currentSheet");
		view = cast this.config.get("cdb.view");
	}

	public function goto2(rootSheet : cdb.Sheet, path: hide.comp.cdb.Editor.Path) {
		var sheets = [for( s in getSheets() ) s.name];
		var index = sheets.indexOf(rootSheet.name);
		if( index < 0 ) return;

		// Tabs can be null if the sheet is opened but hasn't had time to properly initilalize, so we delay the call to this function
		if (tabs == null) {
			haxe.Timer.delay(() -> goto2(rootSheet, path), 50);
			return;
		}

		if (tabs.currentTab.get(0) != tabContents[index].parent().get(0)) {
			@:privateAccess editor.currentFilters = [];
			tabs.currentTab = tabContents[index].parent();
		}
		editor.setFilter(null);
		var curTable = @:privateAccess editor.tables[0];
		var lastCell = null;
		for (i => part in path) {
			var lineNo = 0;
			var colNo = 0;
			switch (part) {
				case Id(idcol, name, target):
					for (l in curTable.lines) {
						if (Reflect.field(l.obj, idcol) == name) {
							break;
						}
						lineNo +=1;
					}
					if (target != null) {
						for (c in curTable.columns) {
							if (c.name == target) {
								break;
							}
							colNo += 1;
						}
					}
				case Prop(name):
					var props = curTable.sheet.lines[0];
					var cols = curTable.columns;

					if (props != null) {
						for (c in curTable.columns) {
							if (c.name == name)
								break;
							if (curTable.shouldDisplayProp(props, c)) {
								lineNo += 1;
							}
						}
					}
				case Line(id,target):
					lineNo = id;
					if (target != null) {
						for (c in curTable.columns) {
							if (c.name == target) {
								break;
							}
							colNo += 1;
						}
					}
				case Script(line):
					var cell = lastCell;
					if (cell != null) {
						#if js
						//cell.open(false);
						var scr = Std.downcast(cell.line.subTable, hide.comp.cdb.ScriptTable);
						if (scr != null) {
							haxe.Timer.delay(function() {
								@:privateAccess scr.script.editor.setPosition({column:0, lineNumber: line+1});
								haxe.Timer.delay(() ->@:privateAccess scr.script.editor.revealLineInCenter(line+1), 1);
							}, 1);
						}
						#end
					}
					colNo = -1;
					lineNo = -1;
			}

			if (i == path.length-1) {
				editor.pushCursorState();
			}
			trace(i, colNo, lineNo);
			if (colNo >= 0 && lineNo >= 0) {
				editor.cursor.set(curTable, colNo, lineNo, i == path.length-1);
				lastCell = editor.cursor.getCell();
				if( editor.cursor.table != null) {
					editor.cursor.table.expandLine(lineNo);
					if (i < path.length-1) {
						var sub = editor.cursor.getLine().subTable;
						var cell = editor.cursor.getCell();
						if (sub != null && sub.cell == cell) {
							curTable = sub;
						}
						else {
							cell.open(false);
							curTable = editor.cursor.table;
						}
					}
				}
			}

		}
		haxe.Timer.delay(function() {
			editor.focus();
			editor.cursor.update();
		}, 1);
		/*for (i in 0...coords.length) {
			var c = coords[i];
			editor.cursor.set(curTable, c.column, c.line);
			if( editor.cursor.table != null && c.line != null ) {
				editor.cursor.table.expandLine(c.line);
				if (i < coords.length - 1) {
					var sub = editor.cursor.getLine().subTable;
					var cell = editor.cursor.getCell();
					if (sub != null && sub.cell == cell) {
						curTable = sub;
					}
					else {
						cell.open(false);
						curTable = editor.cursor.table;
					}
				}
			}
			else
				break;
		}*/

	}

	public function goto( s : cdb.Sheet, ?line : Int, ?column : Int, ?scriptLine : Int ) {
		var sheets = [for( s in getSheets() ) s.name];
		var index = sheets.indexOf(s.name);
		if( index < 0 ) return;
		@:privateAccess editor.currentFilters = [];
		tabs.currentTab = tabContents[index].parent();
		editor.setFilter(null);
		if( line != null ) {
			if( column != null )
				editor.cursor.setDefault(line, column);
			if( editor.cursor.table != null )
				editor.cursor.table.expandLine(line);
			if (scriptLine != null) {
				var cell = editor.cursor.getCell();
				if (cell != null) {
					cell.open(false);
					#if js
					var scr = Std.downcast(cell.line.subTable, hide.comp.cdb.ScriptTable);
					if (scr != null) {
						@:privateAccess scr.script.editor.setPosition({column:0, lineNumber: scriptLine});
					}
					#end
				}
			}
		}
		editor.focus();
		haxe.Timer.delay(() -> editor.cursor.update(), 1); // scroll
	}

	function syncTabs() {
		if( getTabCache() != tabCache || editor.getCurrentSheet() != currentSheet ) {
			currentSheet = editor.getCurrentSheet();
			rebuild();
		}
	}

	public function getSheets() {
		return [for( s in ide.database.sheets ) if( !s.props.hide && (view == null || view.exists(s.name)) ) s];
	}

	function getTabCache() {
		return [for( s in getSheets() ) s.name].join("|");
	}

	#if js
	override function onActivate() {
		if( editor != null ) editor.focus();
	}
	#end

	function setEditor(index:Int) {
		var sheets = getSheets();
		editor.pushCursorState();
		editor.show(sheets[index],tabContents[index]);
		currentSheet = editor.getCurrentSheet();
		ide.currentConfig.set("cdb.currentSheet", sheets[index].name);
		haxe.Timer.delay(editor.focus,1);
	}

	override function onDisplay() {
		var sheets = getSheets();
		if( sheets.length == 0 ) {
			element.html("No CDB sheet created, <a href='#'>create one</a>");
			element.find("a").click(function(_) {
				var sheet = editor.createDBSheet();
				if( sheet == null ) return;
				rebuild();
			});
			return;
		}
		element.addClass("cdb-view");
		element.toggleClass("cdb-diff", @:privateAccess ide.databaseDiff != null);
		tabs = new hide.comp.Tabs(element, true);
		tabCache = getTabCache();
		tabContents = [];
		for( sheet in sheets ) {
			var tab = tabs == null ? element : tabs.createTab(sheet.name);
			var sc = new hide.comp.Scrollable(tab);
			tabContents.push(sc.element);
		}
		if( tabs != null ) {
			tabs.onTabChange = setEditor;
			tabs.onTabRightClick = function(index) {
				editor.popupSheet(true, getSheets()[index], function() {
					var newSheets = getSheets();
					var delta = newSheets.length - sheets.length;
					var sshow = null;
					if( delta > 0 )
						sshow = newSheets[index+1];
					else if( delta < 0 )
						sshow = newSheets[index-1];
					else
						sshow = newSheets[index]; // rename
					if( sshow != null )
						currentSheet = sshow.name;
					if( getTabCache() != tabCache )
						rebuild();
					applyCategories(ide.projectConfig.dbCategories);
				});
			};
		}

		if( sheets.length > 0 ) {
			var idx = 0;
			for( i in 0...sheets.length )
				if( sheets[i].name == currentSheet ) {
					idx = i;
					break;
				}
			tabs.currentTab = tabContents[idx].parent();
		}

		applyCategories(ide.projectConfig.dbCategories, false);
		applyProofing(false);

		watch(@:privateAccess ide.databaseFile, () -> syncTabs());
	}

	public function applyProofing(doRefresh = true) {
		if (doRefresh)
			@:privateAccess tabs.syncTabs();
		var sheets = getSheets();
		var header = @:privateAccess tabs.header;
		element.toggleClass("loc-proofread", ide.projectConfig.dbProofread == true);
		if( ide.projectConfig.dbProofread == true ) {
			for(i in 0...sheets.length) {
				var tab = header.find('[index=$i]');
				var ignoreCount = 0;
				for( l in sheets[i].lines ) {
					if( Reflect.hasField(l, cdb.Lang.IGNORE_EXPORT_FIELD) )
						ignoreCount++;
				}
				tab.addClass("ignore-loc-" + ignoreCount);
				if( ignoreCount > 0 ) {
					tab.addClass("has-loc-ignored");
					tab.get(0).textContent += ' ($ignoreCount)';
				}
			}
		}
		applyCategories(ide.projectConfig.dbCategories, doRefresh);
	}

	public function applyCategories(cats: Array<String>, doRefresh=true) {
		var sheets = getSheets();
		var header = @:privateAccess tabs.header;
		for(i in 0...sheets.length) {
			var props = hide.comp.cdb.Editor.getSheetProps(sheets[i]);
			var show = cats == null || props.categories == null || cats.filter(c -> props.categories.indexOf(c) >= 0).length > 0;
			var tab = header.find('[index=$i]');
			tab.toggleClass("hidden", !show);
			tab.toggleClass("cat", props.categories != null);
			tab.get(0).className = ~/(cat-[^\s]+)/g.replace(tab.get(0).className, "");
			if(props.categories != null)
				for(c in props.categories)
					tab.addClass("cat-" + c);
		}
		if( doRefresh ) editor.refresh();
	}

	#if js
	override public function onDragDrop( items : Array<String>, isDrop : Bool ) {
		if( items.length == 0 )
			return false;
		var path = ide.makeRelative(items[0]);
		var cell = getCellFromMousePos(ide.mouseX, ide.mouseY);
		if( cell == null )
			return false;
		return cell.dragDropFile(path, isDrop);
	}

	public function getCellFromMousePos( x : Int, y : Int ) : Null<hide.comp.cdb.Cell> {
		var pickedEl = js.Browser.document.elementFromPoint(x, y);
		var el = pickedEl;
		while (el != null) {
			var cellRoot = new Element(el);
			var cell : hide.comp.cdb.Cell = cellRoot.prop("cellComp");
			if (cell != null) return cell;
			el = el.parentElement;
		}
		return null;
	}
	#end

	override function getTitle() {
		return "CDB"+ @:privateAccess (ide.databaseDiff != null ? " - "+ide.databaseDiff : "");
	}

	static var _ = hide.ui.View.register(CdbTable);

}
