package hide.view;

/** Virtualized cdb view, displays the sheet of the cdb view **/
class Cdb2 extends hide.ui.View<{}> {

	override function onDisplay() {
		var sheet = ide.database.getSheet(config.get("cdb.currentSheet"));
		sheet ??= Lambda.find(ide.database.sheets, (s) -> !s.props.hide);
		element.get(0).appendChild(new hide.comp.cdb2.Table(sheet, undo).element);
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
	}

	override function getTitle() {
		return "CDB2";
	}

	static var _ = hide.ui.View.register(Cdb2);
}
