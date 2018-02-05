package hide.prefab;

class Group extends Prefab {

	override function load(v:Dynamic) {
	}

	override function save() {
		return {};
	}

	override function getHideProps():HideProps {
		return { name : "Group", icon : "folder" };
	}

	static var _ = Library.register("group", Group);

}