package hide.view;

using hide.tools.Extensions;

class CdbTable extends hide.ui.View<{}> {

	public var sheetsOrder : Array<String>;
	var tabContents : Array<Element>;
	var editor : hide.comp.cdb.Editor;
	var currentSheet : String;
	var tabCache : String;
	var tabs : hide.comp.Tabs;
	var view : cdb.DiffFile.ConfigView;

	var topBar : Element;
	var regularCountEl : Element;
	var warningCountEl : Element;
	var errorCountEl : Element;

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
		undoStack[0] = editor.undo;
		currentSheet = this.config.get("cdb.currentSheet");
		view = cast this.config.get("cdb.view");
		saveDisplayKey = "cdb:" + ide.getPath(@:privateAccess ide.databaseFile);
		sheetsOrder = getDisplayState("sheetsOrder");
		if( sheetsOrder == null ) sheetsOrder = [];
	}

	override function destroy() {
		if (editor != null && editor.gradientEditor != null) {
			@:privateAccess editor.gradientEditor.cleanupPreview();
			editor.gradientEditor.remove();
			editor.gradientEditor = null;
		}
		super.destroy();
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

		if (tabs.currentTab.get(0) != tabContents[index].get(0))
			tabs.currentTab = tabContents[index];

		@:privateAccess editor.filters = [];
		@:privateAccess editor.updateFilters();
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
								haxe.Timer.delay(function() {
									scr.setCursor();
									@:privateAccess scr.script.editor.revealLineInCenter(line+1);
								}, 1);
							}, 1);
						}
						#end
					}
					colNo = -1;
					lineNo = -1;
			}

			if (colNo >= 0 && lineNo >= 0) {
				var isLastJump : Bool = i == path.length-1;
				editor.cursor.set(curTable, colNo, lineNo, null, isLastJump, isLastJump, isLastJump);
				lastCell = editor.cursor.getCell();
				if( editor.cursor.table != null) {
					editor.cursor.table.revealLine(lineNo);
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
	}

	public function goto( s : cdb.Sheet, ?line : Int, ?column : Int, ?scriptLine : Int ) {
		var sheets = [for( s in getSheets() ) s.name];
		var index = sheets.indexOf(s.name);
		if( index < 0 ) return;

		// Tabs can be null if the sheet is opened but hasn't had time to properly initilalize, so we delay the call to this function
		if (tabs == null) {
			haxe.Timer.delay(() -> goto(s, line, column, scriptLine), 50);
			return;
		}

		tabs.currentTab = tabContents[index];
		@:privateAccess editor.filters = [];
		@:privateAccess editor.updateFilters();
		if( line != null ) {
			if( column != null )
				editor.cursor.setDefault(@:privateAccess editor.tables[0], column, line);
			if( editor.cursor.table != null )
				editor.cursor.table.revealLine(line);
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
		var arr = [for( s in ide.database.sheets ) if( !s.props.hide && (view == null || view.exists(s.name)) ) s];
		haxe.ds.ArraySort.sort(arr, (s1, s2) -> sheetsOrder.indexOf(s1.name) - sheetsOrder.indexOf(s2.name));
		sheetsOrder = arr.map(s -> s.name);
		saveSheetsOrder();
		return arr;
	}

	public function saveSheetsOrder() {
		saveDisplayState("sheetsOrder", sheetsOrder);
	}

	public function moveSheetDisplayOrder( s : cdb.Sheet, delta : Int ) {
		var index = sheetsOrder.findIndex(o -> o == s.name);
		var newIndex = index + delta;
		if( index < 0 || newIndex < 0 || newIndex >= sheetsOrder.length )
			return false;
		var order = sheetsOrder[index];
		sheetsOrder.remove(order);
		sheetsOrder.insert(newIndex, order);
		return true;
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
		editor.show(sheets[index],tabContents[index]);
		currentSheet = editor.getCurrentSheet();
		ide.currentConfig.set("cdb.currentSheet", sheets[index].name);

		var validationFunc = @:privateAccess editor.formulas?.validationFuncs?.get(currentSheet);
		if (validationFunc == null) {
			topBar.get(0).style.display = "none";
		} else {
			topBar.get(0).style.display = null;
		}

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
		hide.tools.DragAndDrop.makeDropTarget(element.get(0), onDropEvent);

		element.addClass("cdb-view");
		element.toggleClass("cdb-diff", @:privateAccess ide.databaseDiff != null);
		tabs = new hide.comp.Tabs(element, true);
		tabCache = getTabCache();
		tabContents = [];
		for( sheet in sheets ) {
			var tab = tabs == null ? element : tabs.createTab(sheet.name);
			tabContents.push(tab);
		}
		if( tabs != null ) {
			tabs.onTabChange = setEditor;
			tabs.onTabRightClick = function(index) {
				var sheet = getSheets()[index];
				editor.popupSheet(true, sheet, function() {
					var newSheets = getSheets();
					var delta = newSheets.length - sheets.length;
					var sshow = null;
					if( delta > 0 )
						sshow = newSheets[index+1];
					else if( delta < 0 )
						sshow = newSheets[index-1];
					else
						sshow = sheet; // rename or move display order
					if( sshow != null )
						currentSheet = sshow.name;
					if( getTabCache() != tabCache )
						rebuild();
					applyCategories(ide.projectConfig.dbCategories);
				});
			};
		}

		topBar = new Element('<div class="top-bar">
			<span class="regular ${@:privateAccess editor.filterFlags.has(Regular) ? "" : "disabled"}"><div class="icon ico ico-check-square"></div><p>0</p></span>
			<span class="warning" ${@:privateAccess editor.filterFlags.has(Warning) ? "" : "disabled"}><div class="icon ico ico-warning"></div><p>0</p></span>
			<span class="error" ${@:privateAccess editor.filterFlags.has(Error) ? "" : "disabled"}><div class="icon ico ico-exclamation-circle"></div><p>0</p></span>
		</div>');
		tabs.element.prepend(topBar);
		regularCountEl = topBar.find(".regular").find("p");
		warningCountEl = topBar.find(".warning").find("p");
		errorCountEl = topBar.find(".error").find("p");

		function filterListener(el : Element, flag : hide.comp.cdb.Editor.FilterFlag) {
			var disabled = el.hasClass("disabled");
			disabled = !disabled;
			el.toggleClass("disabled", disabled);

			if (disabled)
				@:privateAccess editor.filterFlags.unset(flag);
			else
				@:privateAccess editor.filterFlags.set(flag);
			editor.updateFilters();
		}

		var regularEl = element.find(".regular");
		regularEl.on("click", function(e) { filterListener(regularEl, Regular); });
		var warningEl = element.find(".warning");
		warningEl.on("click", function(e) { filterListener(warningEl, Warning); });
		var errorEl = element.find(".error");
		errorEl.on("click", function(e) { filterListener(errorEl, Error); });


		if( sheets.length > 0 ) {
			var idx = 0;
			for( i in 0...sheets.length )
				if( sheets[i].name == currentSheet ) {
					idx = i;
					break;
				}
			tabs.currentTab = tabContents[idx];
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
	function onDropEvent(event: hide.tools.DragAndDrop.DropEvent, dragData: hide.tools.DragAndDrop.DragData) {
		var files : Array<hide.tools.FileManager.FileEntry> = dragData.data.get("drag/filetree");
		if (files == null || files.length <= 0) {
			dragData.dropTargetValidity = ForbidDrop;
			return;
		}

		var path = ide.makeRelative(files[0].relPath);
		var cell = getCellFromMousePos(ide.mouseX, ide.mouseY);
		if( cell == null ) {
			dragData.dropTargetValidity = ForbidDrop;
			return;
		}

		if (event != Drop)
			return;

		cell.dragDropFile(path, true);
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
