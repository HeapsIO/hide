package hide.view;

class WorldSceneEditor extends Prefab.PrefabSceneEditor {

	public function new(view, data) {
		super(view, data);
	}

	override function onSceneReady() {
		super.onSceneReady();
		var world = cast(sceneData, hrt.prefab.World);
		@:privateAccess world.editor = this;
	}
}

class World extends Prefab {

	override function createData() {
		data = new hrt.prefab.World();
	}

	override function createEditor() {
		sceneEditor = new WorldSceneEditor(this, data);
	}

	override function onDisplay() {
		super.onDisplay();

		element.find(".hide-scroll").first().append('
		<div name="Properties" icon="cog">
			<div class="world-props"></div>
		</div>
		');
		var worldProps = new hide.comp.PropsEditor(undo,null,element.find(".world-props"));
		{
			var edit = new hide.prefab.EditContext(sceneEditor.context);
			edit.properties = worldProps;
			edit.scene = sceneEditor.scene;
			edit.cleanups = [];
			data.edit(edit);
		}
	}

	override function save() {
		super.save();
	}

	static var _ = FileTree.registerExtension(World, ["world"], { icon : "industry", createNew : "World" });
}