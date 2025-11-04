package hrt.prefab;

enum SettingCategory {
	/** saved for all the inspectors**/
	Global;

	/** saved for similar inspector (i.e. same prefab type)**/
	SameKind;
}

@:allow(hide.kit.Element)
abstract class EditContext2 {
	var parent : EditContext2 = null;

	public function new(parent: EditContext2) {
		this.parent = parent;
	}

	#if !macro
	public var root: hide.kit.KitRoot;

	/**
		Request the inspector to be rebuild, resulting in edit2 to be called again
	**/
	public abstract function rebuildInspector() : Void;

	/**
		Request that the given prefab should be recreated in the editor
	**/
	public abstract function rebuildPrefab(prefab: Prefab) : Void;

	/**
		Request that the scene tree widget should be rebuild for the given prefab
	**/
	public abstract function rebuildTree(prefab: Prefab) : Void;

	/**
		Return the scene3d of the current editor
	**/
	public abstract function getScene3d() : h3d.scene.Scene;

	/**
		Return the camera controller of the current editor
	**/
	public abstract function getCameraController3d() : #if js hide.view.CameraController.CameraControllerBase #else Dynamic #end;

	/**
		Open the given file path in the editor
	**/
	public abstract function openFile(path: String) : Void;

	public abstract function listMatLibraries(path: String) : Array<{path: String, name: String}>;
	public abstract function listMaterialFromLibrary(path: String, libName: String) : Array<{path: String, mat: hrt.prefab.Material}>;

	abstract function recordUndo(callback: (isUndo: Bool) -> Void ) : Void;
	abstract function saveSetting(category: SettingCategory, key: String, value: Dynamic) : Void;
	abstract function getSetting(category: SettingCategory, key: String) : Null<Dynamic>;
	#end

	public macro function build(ethis: haxe.macro.Expr, dml: haxe.macro.Expr, ?contextObj: haxe.macro.Expr) : haxe.macro.Expr {
		return hide.kit.Macros.build(macro $ethis.root, dml, contextObj);
	}
}