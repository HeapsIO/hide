package hrt.prefab.l3d;

@:deprecated("Use hrt.prefab.Library instead")
class Level3D extends hrt.prefab.Library {

	public function new() {
		super();
		type = "level3d";
	}

	static var _ = Library.register("level3d", Level3D, "l3d");
}