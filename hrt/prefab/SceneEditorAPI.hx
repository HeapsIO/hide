package hrt.prefab;

#if !macro
interface SceneEditorAPI {
	public function getRootPrefab() : Prefab;
	public function selectPrefabs(prefabs: Array<Prefab>) : Void;
	public function focusObjects(objects: Array<h3d.scene.Object>) : Void;
}
#end