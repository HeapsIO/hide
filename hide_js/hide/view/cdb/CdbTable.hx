package hide.view.cdb;

using hide.tools.Extensions;

class CdbTable extends hide.ui.View<{}> {
	var tabContents : Array<Element>;
	var editor : hide.comp.cdb.Editor;
	var currentSheet : String;
	var tabCache : String;
	var tabs : hide.comp.Tabs;
	var view : cdb.DiffFile.ConfigView;

	var topBar : Element;

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
	}

	override function destroy() {
		if (editor != null && editor.gradientEditor != null) {
			@:privateAccess editor.gradientEditor.cleanupPreview();
			editor.gradientEditor.remove();
			editor.gradientEditor = null;
		}
		super.destroy();
	}

	public function goto2(rootSheet : cdb.Sheet, path: hrt.tools.CdbUtils.Path) {
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
						var line = editor.cursor.getLine();
						var sub = line == null ? null : line.subTable;
						var cell = editor.cursor.getCell();
						if (sub != null && sub.cell == cell) {
							curTable = sub;
						}
						else if( cell != null && cell.column.type.match(TList | TProperties | TPolymorph) ) {
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

	#if js
	override function onRebuild() {
		// the tabs are rebuilt (a sheet added, renamed, moved...) : the editor keeps its undo
		var undoElts = @:privateAccess editor.undo.undoElts.copy();
		var redoElts = @:privateAccess editor.undo.redoElts.copy();
		super.onRebuild();
		@:privateAccess editor.undo.undoElts = undoElts;
		@:privateAccess editor.undo.redoElts = redoElts;
	}
	#end

	function syncTabs() {
		if( getTabCache() != tabCache || editor.getCurrentSheet() != currentSheet ) {
			currentSheet = editor.getCurrentSheet();
			rebuild();
		} else
			refreshCurrentStatus();
	}

	public function getSheets() {
		var arr = [for( s in ide.database.sheets ) if( !s.props.hide && (view == null || view.exists(s.name)) ) s];
		haxe.ds.ArraySort.sort(arr, (s1, s2) -> hide.comp.cdb.Editor.getSheetProps(s1).index - hide.comp.cdb.Editor.getSheetProps(s2).index);
		for (idx => s in arr) {
			var props = hide.comp.cdb.Editor.getSheetProps(s);
			props.index = idx;
			s.props.editor = props;
		}
		return arr;
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
		ide.projectUserConfig.set("cdb.currentSheet", sheets[index].name);

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
		initTabsDrag();
		tabCache = getTabCache();
		tabContents = [];
		for( sheet in sheets ) {
			var tab = tabs == null ? element : tabs.createTab(sheet.name);
			tabContents.push(tab);
		}
		for (c in hide.comp.cdb.Editor.getCategories(ide.database))
			tabs.createTab(c, null, true);
		if( tabs != null ) {
			tabs.onTabChange = setEditor;
			tabs.onTabClick = function(index) {
				var sheets = getSheets();
				if (index < sheets.length)
					return;
				var allCats = hide.comp.cdb.Editor.getCategories(ide.database);
				var c = allCats[index % sheets.length];
				var content : Array<hrt.ui.HuiMenu.MenuItem> = [];
				for (idx => s in sheets) {
					var props = hide.comp.cdb.Editor.getSheetProps(s);
					if (props.categories == null || props.categories.indexOf(c) < 0)
						continue;
					content.push({ label: s.name, click: () -> {
						tabs.currentTab = tabs.getTabs().siblings('[index=$idx]');
					} });
				}
				var catMenu : Array<hrt.ui.HuiMenu.MenuItem> = [];
				for (c in allCats) {
					var visibleCats : Array<String> = ide.projectState.get("dbCategories");
					catMenu.push({ label: c, icon: visibleCats != null && visibleCats.indexOf(c) < 0 ? null : "check", click: () -> {
						if (visibleCats == null)
							visibleCats = [c];
						else if (visibleCats.contains(c))
							visibleCats.remove(c);
						else
							visibleCats.push(c);
						if (visibleCats.length == 0)
							visibleCats = null;
						ide.projectState.set("dbCategories", visibleCats);
						applyCategories(ide.projectState.get("dbCategories"));
						ide.initMenu();
					} });
				}
				content.push({ label: "Categories", menu: catMenu });
				hide.comp.ContextMenu.createFromPoint(ide.mouseX, ide.mouseY, content);
			}
			tabs.onTabRightClick = function(index) {
				var sheets = getSheets();
				if (index >= sheets.length)
					return;
				var sheet = sheets[index];
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
					applyCategories(ide.projectState.get("dbCategories"));
				});
			};
		}

		topBar = new Element('<div class="top-bar">
			<span class="status error hidden" title="Show only the errors (shift+click: add / remove)"><p>0</p></span>
			<span class="status warning hidden" title="Show only the warnings (shift+click: add / remove)"><p>0</p></span>
			<span class="pin-status" title="Pin the errors / warnings count in the sheet tab"><div class="icon ico ico-thumb-tack"></div></span>
		</div>');
		tabs.element.prepend(topBar);

		// shift+click adds or removes a status to the ones shown
		function filterStatus( flag : hide.comp.cdb.Editor.FilterFlag, add : Bool ) {
			var cur = @:privateAccess editor.filterFlags;
			var filtering = !cur.has(Regular);
			var flags = new haxe.EnumFlags<hide.comp.cdb.Editor.FilterFlag>();
			if( add && filtering ) {
				flags = cur;
				if( flags.has(flag) ) flags.unset(flag) else flags.set(flag);
			} else if( !(filtering && cur.has(flag)) )
				flags.set(flag);
			if( !flags.has(Error) && !flags.has(Warning) ) {
				flags.set(Regular);
				flags.set(Warning);
				flags.set(Error);
			}
			@:privateAccess editor.filterFlags = flags;
			editor.updateFilters();
			refreshCurrentStatus();
		}
		topBar.find(".error").on("click", (e) -> filterStatus(Error, e.shiftKey));
		topBar.find(".warning").on("click", (e) -> filterStatus(Warning, e.shiftKey));
		topBar.find(".pin-status").on("click", function(_) {
			var sheet = getSheets().filter(s -> s.name == editor.getCurrentSheet())[0];
			if( sheet == null ) return;
			var props = hide.comp.cdb.Editor.getSheetProps(sheet);
			editor.beginChanges();
			if( props.pinStatus ) Reflect.deleteField(props, "pinStatus") else props.pinStatus = true;
			sheet.props.editor = props;
			editor.endChanges();
			refreshCurrentStatus();
		});


		if( sheets.length > 0 ) {
			var idx = 0;
			for( i in 0...sheets.length )
				if( sheets[i].name == currentSheet ) {
					idx = i;
					break;
				}
			tabs.currentTab = tabContents[idx];
		}

		applyCategories(ide.projectState.get("dbCategories"), false);
		applyProofing(false);

		watch(@:privateAccess ide.databaseFile, () -> syncTabs());
	}

	public function applyProofing(doRefresh = true) {
		if (doRefresh)
			@:privateAccess tabs.syncTabs();
		var sheets = getSheets();
		var header = @:privateAccess tabs.header;
		element.toggleClass("loc-proofread", ide.projectState.get("dbProofread") == true);
		if( ide.projectState.get("dbProofread") == true ) {
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
		applyCategories(ide.projectState.get("dbCategories"), doRefresh);
	}

	// the order is the index of the sheets in their props, not their order in the database (smaller diffs)
	function initTabsDrag() {
		var header = @:privateAccess tabs.header;
		header.on("mousedown", function(e) {
			if( e.button != 0 ) return;
			var tab = new Element(e.target).closest("[index]");
			if( tab.parent().get(0) != header.get(0) ) return;
			var sheets = getSheets();
			var from = Std.parseInt(tab.attr("index"));
			if( from == null || from >= sheets.length ) return;
			var startX = e.pageX, startY = e.pageY, dragging = false, target = -1;
			var doc = new Element(js.Browser.document);
			doc.on("mousemove.tabDrag", function(e) {
				if( !dragging && Math.abs(e.pageX - startX) + Math.abs(e.pageY - startY) < 5 ) return;
				dragging = true;
				header.addClass("tab-dragging");
				header.children().removeClass("drop-before drop-after");
				target = -1;
				var over = new Element(js.Browser.document.elementFromPoint(e.clientX, e.clientY)).closest("[index]");
				if( over.parent().get(0) != header.get(0) ) return;
				var idx = Std.parseInt(over.attr("index"));
				if( idx == null || idx >= sheets.length ) return;
				var r = over.get(0).getBoundingClientRect();
				var after = e.clientX > r.left + r.width * 0.5;
				over.addClass(after ? "drop-after" : "drop-before");
				target = idx + (after ? 1 : 0);
			});
			doc.on("mouseup.tabDrag", function(_) {
				doc.off(".tabDrag");
				header.removeClass("tab-dragging");
				header.children().removeClass("drop-before drop-after");
				if( !dragging || target < 0 ) return;
				var sheet = sheets[from];
				sheets.remove(sheet);
				sheets.insert(target > from ? target - 1 : target, sheet);
				editor.beginChanges();
				for( i => s in sheets ) {
					var props = hide.comp.cdb.Editor.getSheetProps(s);
					if( props.index != i ) {
						props.index = i;
						s.props.editor = props;
					}
				}
				editor.endChanges();
				currentSheet = sheet.name;
				if( getTabCache() != tabCache )
					rebuild();
			});
		});
	}

	public function setSearchCounts( counts : Map<String, Int> ) {
		var header = @:privateAccess tabs.header;
		header.find(".search-count").remove();
		header.children().removeClass("no-results");
		if( counts == null ) return;
		for( i => s in getSheets() ) {
			var n = counts.get(s.name);
			if( n == null ) continue;
			var tab = header.find('[index=$i]');
			if( n == 0 )
				tab.addClass("no-results");
			else
				new Element('<span class="search-count">$n</span>').appendTo(tab);
		}
	}

	function refreshCurrentStatus() {
		var t = @:privateAccess editor.tables[0];
		if( t != null ) t.refreshLinesStatus();
	}

	public function refreshStatus( errors : Int, warnings : Int ) {
		if( topBar == null ) return;
		var flags = @:privateAccess editor.filterFlags;
		function set( el : Element, n : Int, flag ) {
			var only = flags.has(flag) && !flags.has(Regular);
			el.toggleClass("active", only);
			el.toggleClass("hidden", n == 0 && !only);
			el.find("p").text(n);
		}
		set(topBar.find(".error"), errors, Error);
		set(topBar.find(".warning"), warnings, Warning);
		refreshPinnedStatus(errors, warnings);
	}

	// pinned sheets keep their errors (else warnings) count in their tab, which is wider to always have room for it
	function refreshPinnedStatus( ?currentErrors : Int, ?currentWarnings : Int ) {
		if( tabs == null ) return;
		var header = @:privateAccess tabs.header;
		header.find(".status-count").remove();
		var cur = editor.getCurrentSheet();
		var funcs = @:privateAccess editor.formulas?.validationFuncs;
		for( i => s in getSheets() ) {
			var tab = header.find('[index=$i]');
			var pinned = hide.comp.cdb.Editor.getSheetProps(s).pinStatus == true && funcs != null && funcs.exists(s.name);
			tab.toggleClass("pin-status", pinned);
			tab.removeClass("pin-empty");
			if( s.name == cur )
				topBar.find(".pin-status").toggleClass("active", pinned);
			if( !pinned ) continue;
			var errors = 0, warnings = 0;
			if( s.name == cur && currentErrors != null ) {
				errors = currentErrors;
				warnings = currentWarnings;
			} else {
				for( st in editor.getSheetStatus(s) )
					switch( st ) {
					case Error(_): errors++;
					case Warning(_): warnings++;
					default:
					}
			}
			if( errors > 0 )
				new Element('<span class="status-count error">$errors</span>').appendTo(tab);
			else if( warnings > 0 )
				new Element('<span class="status-count warning">$warnings</span>').appendTo(tab);
			else
				tab.addClass("pin-empty");
		}
	}

	public function applyCategories(displayedCats: Array<String>, doRefresh=true) {
		var sheets = getSheets();
		var header = @:privateAccess tabs.header;
		for (i in 0...sheets.length) {
			var props = hide.comp.cdb.Editor.getSheetProps(sheets[i]);
			var show = displayedCats == null || props.categories == null || displayedCats.filter(c -> props.categories.indexOf(c) >= 0).length > 0;
			var tab = header.find('[index=$i]');
			tab.toggleClass("cat", props.categories != null);
			tab.get(0).className = ~/(cat-[^\s]+)/g.replace(tab.get(0).className, "");
			var color = null;
			if(props.categories != null)
				for(c in props.categories) {
					tab.addClass("cat-" + c);
					if( color == null ) color = hide.comp.cdb.Editor.getCategoryColor(c);
				}
			hide.comp.cdb.Editor.setTabColor(tab, color);
		}

		// Reset order of header tabs and visibility
		for (idx in 0...header.children().length) {
			var e = header.find('[index=$idx]');
			e.toggleClass('hidden', false);
		}

		var allCats = hide.comp.cdb.Editor.getCategories(ide.database);
		for (idx in 0...allCats.length) {
			var cat = allCats[idx];
			var tabHeader = header.find('[index=${sheets.length + idx}]');
			var color = hide.comp.cdb.Editor.getCategoryColor(cat);
			hide.comp.cdb.Editor.setTabColor(tabHeader, color);
			var grouped = displayedCats?.indexOf(cat) < 0;
			tabHeader.toggleClass("hidden", !grouped);
			var grouppedHeaders = header.find('.cat-${cat}');
			if (grouped)
				grouppedHeaders.toggleClass('hidden', true);
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

	override function buildTabMenu() {
		var menu = super.buildTabMenu();
		menu.push({ isSeparator : true });
		menu.push({ label : "Icons Scale...", click : openIconsScale });
		var speed = hide.comp.cdb.Editor.getAnimSpeed();
		function speedItem( label : String, s : Int ) : hrt.ui.HuiMenu.MenuItem {
			return { label : label, radio : () -> speed == s, click : () -> hide.comp.cdb.Editor.setAnimSpeed(s) };
		}
		menu.push({ label : "Animations", menu : [speedItem("x1", 1), speedItem("x2", 2), speedItem("x3", 3), speedItem("Off", 0)] });
		return menu;
	}

	// the icons are shown at the scale of the slider, which is saved by Apply only
	function openIconsScale() {
		var Editor = hide.comp.cdb.Editor;
		var saved = Math.round(Editor.getIconZoom() * 100);
		var popup = new hide.comp.Popup(element);
		popup.position = Inside;
		popup.offsetX = 10;
		popup.offsetY = 10;
		popup.element.addClass("cdb-icons-scale");
		var content = new Element('<div>
			<div class="title">Icons Scale</div>
			<div class="slider"><input type="range" min="25" max="200" step="5" value="$saved"/><span class="value">$saved%</span></div>
			<div class="buttons"><input type="button" class="apply" value="Apply"/><input type="button" class="cancel" value="Cancel"/></div>
		</div>').appendTo(popup.element);
		var range = content.find("input[type=range]");
		var applied = false, pending = false;
		function preview() {
			if( pending ) return;
			pending = true;
			js.Browser.window.requestAnimationFrame(function(_) {
				pending = false;
				Editor.refreshAll(false, false);
			});
		}
		range.on("input", function(_) {
			var v = Std.parseInt(range.val());
			content.find(".value").text(v + "%");
			Editor.previewIconZoom = v;
			preview();
		});
		content.find(".apply").click(function(_) {
			applied = true;
			Editor.setIconZoom(Std.parseInt(range.val()));
			popup.close();
		});
		content.find(".cancel").click((_) -> popup.close());
		popup.onClose = function() {
			Editor.previewIconZoom = null;
			if( !applied && Math.round(Editor.getIconZoom() * 100) != Std.parseInt(range.val()) )
				Editor.refreshAll(false, false);
		};
	}

	override function getTitle() {
		return "CDB"+ @:privateAccess (ide.databaseDiff != null ? " - "+ide.databaseDiff : "");
	}

	static var _ = hide.ui.View.register(CdbTable);

}
