package hide.view;

/** Virtualized cdb view, a tab per sheet **/
class Cdb2 extends hide.ui.View<{}> {
	var tabs : hide.comp.Tabs;
	var tabCache : String;
	/** Shared by all the tabs, moved to the selected one **/
	var table : hide.comp.cdb2.Table;

	override function onDisplay() {
		var sheets = getSheets();
		table = new hide.comp.cdb2.Table(null, undo);
		tabs = new hide.comp.Tabs(element, true);
		tabCache = getTabCache();
		var tabContents = [for (sheet in sheets) tabs.createTab(sheet.name)];
		for (c in hide.comp.cdb.Editor.getCategories(ide.database))
			tabs.createTab(c, null, true);

		tabs.onTabChange = function(index) {
			tabContents[index].get(0).appendChild(table.element);
			table.openSheet(sheets[index]);
			ide.projectUserConfig.set("cdb.currentSheet", sheets[index].name);
		}
		tabs.onTabClick = function(index) {
			if (index < sheets.length)
				return;
			var allCats = hide.comp.cdb.Editor.getCategories(ide.database);
			var c = allCats[index - sheets.length];
			var content : Array<hrt.ui.HuiMenu.MenuItem> = [];
			for (idx => s in sheets) {
				var props = hide.comp.cdb.Editor.getSheetProps(s);
				if (props.categories == null || props.categories.indexOf(c) < 0)
					continue;
				content.push({ label: s.name, click: () -> tabs.currentTab = tabContents[idx] });
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
					applyCategories(visibleCats);
					ide.initMenu();
				} });
			}
			content.push({ label: "Categories", menu: catMenu });
			hide.comp.ContextMenu.createFromPoint(ide.mouseX, ide.mouseY, content);
		}

		var current = config.get("cdb.currentSheet");
		var index = 0;
		for (i => s in sheets)
			if (s.name == current)
				index = i;
		if (sheets.length > 0)
			tabs.currentTab = tabContents[index];

		applyCategories(ide.projectState.get("dbCategories"));

		watch(@:privateAccess ide.databaseFile, () -> if (getTabCache() != tabCache) rebuild());
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
	}

	function getSheets() {
		var view : cdb.DiffFile.ConfigView = cast config.get("cdb.view");
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

	/** Hides the tabs of the sheets grouped in their category tab, `displayedCats` null displays all **/
	function applyCategories(displayedCats: Array<String>) {
		var sheets = getSheets();
		var header = @:privateAccess tabs.header;
		for (i in 0...sheets.length) {
			var props = hide.comp.cdb.Editor.getSheetProps(sheets[i]);
			var tab = header.find('[index=$i]');
			tab.toggleClass("cat", props.categories != null);
			tab.get(0).className = ~/(cat-[^\s]+)/g.replace(tab.get(0).className, "");
			if (props.categories != null)
				for (c in props.categories)
					tab.addClass("cat-" + c);
		}

		for (idx in 0...header.children().length)
			header.find('[index=$idx]').toggleClass("hidden", false);

		var allCats = hide.comp.cdb.Editor.getCategories(ide.database);
		for (idx => cat in allCats) {
			var grouped = displayedCats?.indexOf(cat) < 0;
			header.find('[index=${sheets.length + idx}]').toggleClass("hidden", !grouped);
			if (grouped)
				header.find('.cat-$cat').toggleClass("hidden", true);
		}
	}

	override function getTitle() {
		return "CDB2";
	}

	static var _ = hide.ui.View.register(Cdb2);
}
