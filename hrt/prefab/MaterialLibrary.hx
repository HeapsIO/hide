package hrt.prefab;

@:prefabName("Material Library")
@:prefabIcon(hrt.ui.HuiRes.ui.icons.prefab.material)
@:prefabHideInAddMenu
class MaterialLibrary extends Prefab {
	public static function isMaterialLibrary(p : hrt.prefab.Prefab) {
		return Std.isOfType(p, MaterialLibrary);
	}

	static var _ = Prefab.register("matlib", MaterialLibrary, "matlib");
}
