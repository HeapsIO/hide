package hide.view;
import hrt.ui.*;

class FileBrowser extends HuiView<{path: String}> {

	var fileBrowser : HuiFileBrowser;

	public function new(_state: Dynamic, ?parent) {
		super(state, parent);
		initComponent();

		var path = state.path ?? hide.Ide.inst.resourceDir;
		fileBrowser = new HuiFileBrowser(path, this);
		fileBrowser.onOpen = (file) -> {
			hide.Ide.inst.openFile(file.fullPath);
		};
	}

	static var _ = HuiView.register("fileBrowser", FileBrowser);
}