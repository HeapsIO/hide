package hrt.prefab;


enum SettingCategory {
	/** saved for all the inspectors**/
	Global;

	/** saved for similar inspector (i.e. same prefab type)**/
	SameKind;
}

typedef EditorTool = {
	init: (ctx: hrt.prefab.EditContext2) -> Void,
	update: (ctx: hrt.prefab.EditContext2, dt: Float) -> Void,
	dispose: (ctx: hrt.prefab.EditContext2) -> Void,
};

@:allow(hide.kit.Element)
abstract class EditContext2 {
	var parent : EditContext2 = null;

	public var s3d(get, never): h3d.scene.Scene;
	public var s2d(get, never): h2d.Scene;

	function get_s3d() {return getScene3d();}
	function get_s2d() {return getScene2d();}

	public function new(parent: EditContext2) {
		this.parent = parent;
	}

	#if !macro
	#if domkit
	public var root: hide.kit.KitRoot;
	#end

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
		Return the scene2d of the current editor
	**/
	public abstract function getScene2d() : h2d.Scene;

	/**
		Return the camera controller of the current editor
	**/
	public abstract function getCameraController3d() : #if (js && domkit) hide.view.CameraController.CameraControllerBase #else Dynamic #end;

	/**
		Open the given file path in the editor
	**/
	public abstract function openFile(path: String) : Void;

	public abstract function openPrefab(path: String, ?afterOpen : (ctx: SceneEditorAPI) -> Void) : Void;

	/**
		Prompt the user to select a file, and then call callback with the chosen path.
	**/
	public abstract function chooseFileSave(path: String, callback:(absPath: String) -> Void, allowNull: Bool = false) : Void;

	public abstract function listMaterialLibraries(path: String) : Array<{path: String, name: String}>;

	/**
		Displays an error message to the user
	**/
	public abstract function quickError(message: String) : Void;

	/**
		Set the current tool for the editor. A tool is a fullscreen editor.
		If unique is set, replace the previous unique registered tool. The editor is automatically disposed when
		the prefab is unselected
	**/
	public abstract function setTool(tool: EditorTool, unique: Bool = true) : Void;

	abstract function recordUndo(callback: (isUndo: Bool) -> Void ) : Void;
	abstract function saveSetting(category: SettingCategory, key: String, value: Dynamic) : Void;
	abstract function getSetting(category: SettingCategory, key: String) : Null<Dynamic>;

	abstract function getRootObjects3d() : Array<h3d.scene.Object>;


	#end

	#if domkit
	public macro function build(ethis: haxe.macro.Expr, dml: haxe.macro.Expr, ?contextObj: haxe.macro.Expr) : haxe.macro.Expr {
		return hide.kit.Macros.build(macro $ethis.root, dml, contextObj);
	}
	#end

}
