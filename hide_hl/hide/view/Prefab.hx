package hide.view;
import hrt.ui.*;

#if hui

class Prefab extends HuiView<{path: String}> {
	static var SRC =
		<prefab>
			<hui-prefab-editor id="prefab-editor"/>
		</prefab>

	static var _ = HuiView.register("prefab", Prefab);

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		var path = Ide.inst.getRelPath(state.path);

		prefabEditor.setPrefab(hxd.res.Loader.currentInstance.load(path).toPrefab().load().clone());
	}

	override function getDisplayName():String {
		return state.path.split("/").splice(-1, 2).join("/");
	}

}

#end