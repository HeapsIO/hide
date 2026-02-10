package hrt.ui;

#if hui

@:access(hrt.prefab.Prefab)
class HuiPrefabEditor extends HuiElement {
	static var SRC =
		<hui-prefab-editor>
			<hui-split-container id="main-split">

				<hui-split-container id="scene-tree-split">
					<hui-element id="scene-panel">
						<hui-element id="scene-toolbar"/>
						<hui-scene id="scene"/>
					</hui-element>
					<hui-element id="panel-tree">
						<hui-tree id="tree-prefab"/>
					</hui-element>
				</hui-split-container>

				<hui-element id="inspector-panel">
					<hui-text("inspector")/>
				</hui-element>
			</hui-split-container>
		</hui-prefab-editor>

	var prefab: hrt.prefab.Prefab;
	var errorMessage : h2d.Text;

	override function new(?parent) {
		super(parent);
		initComponent();

		errorMessage = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		new h3d.scene.CameraController(scene.s3d);
	}

	public function setPrefab(newPrefab: hrt.prefab.Prefab) {
		if (prefab != null) {
			prefab.shared.root2d.remove();
			prefab.shared.root3d.remove();
			prefab = null;
		}

		prefab = newPrefab;
		tryMake();
	}

	public function tryMake() {
		if (prefab != null) {
			prefab.shared.root2d?.remove();
			prefab.shared.root3d?.remove();
		}
		errorMessage.text = "";

		@:privateAccess prefab.shared.root2d = prefab.shared.current2d = new h2d.Object(scene.s2d);
		@:privateAccess prefab.shared.root3d = prefab.shared.current3d = new h3d.scene.Object(scene.s3d);

		try {
			prefab.make();
		} catch (e) {
			prefab.shared.root2d?.remove();
			prefab.shared.root3d?.remove();

			errorMessage.text = "Error loading prefab : " + e;

			trace("Error loading prefab " + e);
		}
	}
}

#end