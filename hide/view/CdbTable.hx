package hide.view;

class CdbTable extends hide.ui.View<{ path : String }> {

	var sheet : cdb.Sheet;
	var editor : hide.comp.CdbTable;

	public function new(state) {
		super(state);
		for( s in ide.database.sheets )
			if( s.name == state.path ) {
				sheet = s;
				break;
			}
	}

	override function onDisplay() {
		if( sheet == null ) {
			root.text("Sheet not found '" + state.path + "'");
			return;
		}
		root.addClass("hide-scroll");
		editor = new hide.comp.CdbTable(root, sheet);
	}

	override function getTitle() {
		return state.path.charAt(0).toUpperCase() + state.path.substr(1);
	}

	static var _ = hide.ui.View.register(CdbTable);

}
