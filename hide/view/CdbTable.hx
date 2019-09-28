package hide.view;

class CdbTable extends hide.ui.View<{ path : String }> {

	var sheets : Array<cdb.Sheet>;
	var tabContents : Array<Element>;
	var editor : hide.comp.cdb.Editor;
	var currentSheet : Int = 0;

	public function new( ?state ) {
		super(state);
		syncSheets();
		var name = this.config.get("cdb.currentSheet");
		if( name != null )
			for( s in sheets )
				if( s.name == name ) {
					currentSheet = sheets.indexOf(s);
					break;
				}
	}

	function syncSheets() {
		if( state.path == null )
			sheets = [for( s in ide.database.sheets ) if( !s.props.hide ) s];
		else {
			for( s in ide.database.sheets )
				if( s.name == state.path ) {
					sheets = [s];
					break;
				}
		}
	}

	override function onActivate() {
		if( editor != null ) editor.focus();
	}

	function setEditor(index:Int) {
		syncSheets();
		if( editor != null )
			editor.remove();
		editor = new hide.comp.cdb.Editor(sheets[index],config,ide.databaseApi,tabContents[index]);
		haxe.Timer.delay(function() {
			// delay
			editor.focus();
			editor.onFocus = activate;
		},0);
		undo = ide.databaseApi.undo;
		currentSheet = index;
		ide.currentConfig.set("cdb.currentSheet", sheets[index].name);
	}

	override function onDisplay() {
		if( sheets == null ) {
			element.text("CDB sheet not found '" + state.path + "'");
			return;
		}
		if( sheets.length == 0 ) {
			element.html("No CDB sheet created, <a href='#'>create one</a>");
			element.find("a").click(function(_) {
				var sheet = ide.createDBSheet();
				if( sheet == null ) return;
				syncSheets();
				rebuild();
			});
			return;
		}
		element.addClass("cdb-view");
		var tabs = state.path != null ? null : new hide.comp.Tabs(element, true);
		tabContents = [];
		for( sheet in sheets ) {
			var tab = tabs == null ? element : tabs.createTab(sheet.name);
			var sc = new hide.comp.Scrollable(tab);
			tabContents.push(sc.element);
		}
		if( tabs != null ) {
			tabs.onTabChange = setEditor;
			tabs.onTabRightClick = function(index) {
				syncSheets();
				var sheetCount = sheets.length;
				editor.popupSheet(sheets[index], function() {
					syncSheets();
					if( sheets.length > sheetCount )
						currentSheet = index + 1;
					else if( sheets.length < sheetCount )
						currentSheet = index == 0 ? 0 : index - 1;
					rebuild();
				});
			};
		}
		if( sheets.length > 0 )
			tabs.currentTab = tabContents[currentSheet].parent();

		watch(@:privateAccess ide.databaseFile, () -> {
			syncSheets();
			rebuild();
		});
	}

	override function getTitle() {
		if( state.path == null )
			return "CDB";
		return state.path.charAt(0).toUpperCase() + state.path.substr(1);
	}

	static var _ = hide.ui.View.register(CdbTable);

}
