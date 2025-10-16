package hide.kit;

interface EditorAPI {
	public function recordUndo(callback: (isUndo: Bool) -> Void ) : Void;

	public function refreshInspector() : Void;
}