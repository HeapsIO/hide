package hide.comp.cdb;

class AllEditors extends Editor {

	public function new() {
		super(null,null,hide.Ide.inst.databaseApi);
	}

	override function init() {
	}

	function getEditors() : Array<Editor> {
		return [for( i in ide.getViews(hide.view.CdbTable) ) @:privateAccess i.editor];
	}

	override function refresh( ?state : Editor.UndoState ) {
		for( e in getEditors() ) {
			e.syncSheet();
			e.refresh(state);
		}
	}

}