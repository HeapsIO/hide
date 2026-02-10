package hide.view;
import hrt.ui.*;

#if hui

class Prefab extends HuiView<{}> {
	static var SRC =
		<prefab>
			<hui-prefab-editor id="prefab-editor"/>
		</prefab>

	static var _ = HuiView.register("prefab", Prefab);

	public function new(state: Dynamic, ?parent) {
		super(state, parent);
		initComponent();

		var path = Ide.inst.getRelPath(state.path);

		prefabEditor.setPrefab(hxd.res.Loader.currentInstance.load(path).toPrefab().load().clone());
	}

}

#end