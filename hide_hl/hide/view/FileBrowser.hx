package hide.view;
import hrt.ui.*;

class FileBrowser extends HuiView<{path: String, mode: hrt.ui.HuiFileBrowser.BrowserMode}> {

	var fileBrowser : HuiFileBrowser;

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		var path = state.path ?? hide.Ide.inst.resourceDir;
		fileBrowser = new HuiFileBrowser(path, this);
		fileBrowser.onOpen = (file) -> {
			hide.Ide.inst.openFile(file.path);
		};
		updateMode(state.mode ?? FileTree);
	}

	override function getViewName():String {
		return "File Browser";
	}

	function updateMode(mode: hrt.ui.HuiFileBrowser.BrowserMode) {
		state.mode = mode;
		fileBrowser.mode = mode;

	}

	override function getContextMenuContent(content:Array<hrt.ui.HuiMenu.MenuItem>) {
		content.push({label: "Refresh", click: () -> fileBrowser.markRefresh()});
		content.push({label: "Layout", menu: [
				{label: "File Tree", click: updateMode.bind(FileTree)},
				{label: "Galery", click: updateMode.bind(Gallery)},
				{label: "Horizontal", click: updateMode.bind(Horizontal)},
				{label: "Vertical", click: updateMode.bind(Vertical)},
			]
		});
	}

	static var _ = HuiView.register("fileBrowser", FileBrowser);
}