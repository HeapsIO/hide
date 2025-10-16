package hide.kit;

class EditorAPI {
	public function new() {}

	dynamic public function recordUndo(callback: (isUndo: Bool) -> Void ) {
		throw "recordUndo is not implemented";
	}

	dynamic public function refreshInspector() : Void {
		throw "refreshInspector is not implemented";
	}
}