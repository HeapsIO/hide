package hide.kit;

enum SettingCategory {
	/** saved for all the inspectors**/
	Global;

	/** saved for similar inspector (i.e. same prefab type)**/
	SameKind;
}

interface EditorAPI {
	public function recordUndo(callback: (isUndo: Bool) -> Void ) : Void;

	public function refreshInspector() : Void;

	public function saveSetting(category: SettingCategory, key: String, value: Dynamic) : Void;
	public function getSetting(category: SettingCategory, key: String) : Null<Dynamic>;
}