package hide.view;

class CdbTable extends hide.ui.View<{ path : String }> {

	var sheet : cdb.Sheet;
	var editor : hide.comp.cdb.Editor;

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
			element.text("Sheet not found '" + state.path + "'");
			return;
		}
		element.addClass("hide-scroll");
		editor = new hide.comp.cdb.Editor(sheet,props,element);
		editor.undo = undo;
		undo.onChange = function() {
			editor.save();
		};
		editor.save = function() {
			ide.saveDatabase();
		};
		new Element("<div style='width:100%; height:300px'></div>").appendTo(element);
	}

	override function getTitle() {
		return state.path.charAt(0).toUpperCase() + state.path.substr(1);
	}

	static var _ = hide.ui.View.register(CdbTable);

}
