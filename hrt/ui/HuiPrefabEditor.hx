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

	override function new(?parent) {
		super(parent);
		initComponent();

		new h3d.scene.CameraController(scene.s3d);

		setPrefab(HuiRes.loader.load("SimplePrefab.prefab").toPrefab().load(), "");
	}

	function setPrefab(newPrefab: hrt.prefab.Prefab, path: String) {
		if (prefab != null) {
			prefab.shared.root2d.remove();
			prefab.shared.root3d.remove();
			prefab = null;
		}

		prefab = newPrefab;
		prefab.setSharedRec(new hrt.prefab.ContextShared(path, new h2d.Object(scene.s2d), new h3d.scene.Object(scene.s3d)));
		prefab.make();
	}
}

#end