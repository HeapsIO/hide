package hide.view;
import hrt.ui.*;

#if hui

class Prefab extends HuiView<{}> {
	static var SRC =
		<prefab>
			<hui-prefab-editor id="prefab-editor"/>
		</prefab>

	static var _ = HuiView.register("prefab", Prefab);

}

#end