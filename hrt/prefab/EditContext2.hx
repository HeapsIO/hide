package hrt.prefab;

enum SettingCategory {
	/** saved for all the inspectors**/
	Global;

	/** saved for similar inspector (i.e. same prefab type)**/
	SameKind;
}

@:allow(hide.kit.Element)
abstract class EditContext2 {
	#if !macro
	public var root: hide.kit.KitRoot;

	public abstract function refreshInspector() : Void;
	public abstract function getScene3d() : h3d.scene.Scene;
	public abstract function getCameraController3d() : hide.view.CameraController.CameraControllerBase;


	abstract function recordUndo(callback: (isUndo: Bool) -> Void ) : Void;
	abstract function saveSetting(category: SettingCategory, key: String, value: Dynamic) : Void;
	abstract function getSetting(category: SettingCategory, key: String) : Null<Dynamic>;
	#end

	public macro function build(ethis: haxe.macro.Expr, dml: haxe.macro.Expr, ?contextObj: haxe.macro.Expr) : haxe.macro.Expr {
		return hide.kit.Macros.build(macro $ethis.root, dml, contextObj);
	}
}