package hide.view;

class CdbTable extends hide.ui.View<{ path : String }> {

	var sheets : Array<cdb.Sheet>;
	var tabContents : Array<Element>;
	var editor : hide.comp.cdb.Editor;

	public function new( ?state ) {
		super(state);
		updateSheet();
	}

	function updateSheet() {
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
		if( editor != null )
			editor.remove();
		editor = new hide.comp.cdb.Editor(sheets[index],config,ide.databaseApi,tabContents[index]);
		editor.focus();
		editor.onFocus = activate;
		undo = ide.databaseApi.undo;
	}

	override function onDisplay() {
		if( sheets == null ) {
			element.text("CDB sheet not found '" + state.path + "'");
			return;
		}
		var tabs = sheets.length == 1 ? null : new hide.comp.Tabs(element);
		if( tabs != null )
			tabs.onTabChange = setEditor;
		tabContents = [];
		for( sheet in sheets ) {
			var tab = tabs == null ? element : tabs.createTab(sheet.name);
			var sc = new hide.comp.Scrollable(tab);
			tabContents.push(sc.element);
		}
		if( sheets.length > 0 )
			setEditor(0);

		watch(@:privateAccess ide.databaseFile, () -> {
			updateSheet();
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
