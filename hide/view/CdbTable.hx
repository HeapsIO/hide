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
		editor = new hide.comp.cdb.Editor(config,{
			copy : () -> (ide.database.save() : Any),
			load : (v:Any) -> ide.database.load((v:String)),
			save : function() {
				ide.saveDatabase();
				haxe.Timer.delay(syncTabs,0);
			}
		});
		undo = editor.undo;
		currentSheet = this.config.get("cdb.currentSheet");
		view = cast this.config.get("cdb.view");
	}

	public function goto( s : cdb.Sheet, line : Int, column : Int ) {
		var sheets = [for( s in getSheets() ) s.name];
		var index = sheets.indexOf(s.name);
		if( index < 0 ) return;
		tabs.currentTab = tabContents[index].parent();
		editor.setFilter(null);
		editor.cursor.setDefault(line, column);
		editor.focus();
		haxe.Timer.delay(() -> editor.cursor.update(), 1); // scroll
	}

	function syncTabs() {
		if( getTabCache() != tabCache || editor.getCurrentSheet() != currentSheet ) {
			currentSheet = editor.getCurrentSheet();
			rebuild();
		}
	}

	function getSheets() {
		return [for( s in ide.database.sheets ) if( !s.props.hide && (view == null || view.exists(s.name)) ) s];
	}

	function getTabCache() {
		return [for( s in getSheets() ) s.name].join("|");
	}

	override function onActivate() {
		if( editor != null ) editor.focus();
	}

	function setEditor(index:Int) {
		var sheets = getSheets();
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
				var sheet = ide.createDBSheet();
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
				editor.popupSheet(getSheets()[index], function() {
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

		applyCategories(ide.projectConfig.dbCategories);

		watch(@:privateAccess ide.databaseFile, () -> syncTabs());
	}

	public function applyCategories(cats: Array<String>) {
		var sheets = getSheets();
		var header = @:privateAccess tabs.header;
		for(i in 0...sheets.length) {
			var props = hide.comp.cdb.Editor.getSheetProps(sheets[i]);
			var show = cats == null || props.categories == null || cats.filter(c -> props.categories.indexOf(c) >= 0).length > 0;
			var tab = header.find('[index=$i]');
			tab.toggleClass("hidden", !show);
			tab.toggleClass("cat", props.categories != null);
			tab[0].className = ~/(cat-[^\s]+)/g.replace(tab[0].className, "");
			if(props.categories != null)
				for(c in props.categories)
					tab.addClass("cat-" + c);
		}
		editor.refresh();
	}

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

	override function getTitle() {
		return "CDB"+ @:privateAccess (ide.databaseDiff != null ? " - "+ide.databaseDiff : "");
	}

	static var _ = hide.ui.View.register(CdbTable);

}
