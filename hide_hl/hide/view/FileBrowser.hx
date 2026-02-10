package hide.view;
import hrt.ui.*;

class FileBrowser extends HuiView<{path: String}> {

	var fileBrowser : HuiFileBrowser;

	public function new(state: Dynamic, ?parent) {
		super(state, parent);
		initComponent();

		fileBrowser = new HuiFileBrowser(state.path, this);
		fileBrowser.onOpen = (file) -> {
			trace("open " + file.fullPath);
		};
	}

	static var _ = HuiView.register("fileBrowser", FileBrowser);
}