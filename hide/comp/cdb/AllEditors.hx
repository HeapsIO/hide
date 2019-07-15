package hide.comp.cdb;

class AllEditors extends Editor {

	public function new() {
		super(null,null,hide.Ide.inst.databaseApi);
	}

	override function init() {
	}

	function getEditors() : Array<Editor> {
		return [for( e in new Element(".is-cdb-editor").elements() ) e.data("cdb")];
	}

	override function refresh( ?state : Editor.UndoState ) {
		for( e in getEditors() ) {
			e.syncSheet();
			e.refresh(state);
		}
	}

}