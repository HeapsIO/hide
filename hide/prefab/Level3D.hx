package hide.prefab;

class Level3D extends Prefab {

	override function load(obj:Dynamic) {
	}

	override function save() {
		return {};
	}

	override function getHideProps() {
		return { icon : "cube", name : "Level3D", fileSource : ["l3d"] };
	}

	static var _ = Library.register("level3d", Level3D);
}