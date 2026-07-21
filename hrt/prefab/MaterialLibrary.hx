package hrt.prefab;

@:prefabName("Material Library")
@:prefabIcon(hrt.ui.HuiRes.ui.icons.prefab.material)
@:prefabHideInAddMenu
class MaterialLibrary extends Prefab {
	public static function isMaterialLibrary(path : String) {
		return path.indexOf(".matlib") >= 0;
	}

	static var _ = Prefab.register("matlib", MaterialLibrary, "matlib");
}
