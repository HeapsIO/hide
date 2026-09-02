package hide.view;
import hrt.ui.*;

class FileBrowser extends HuiView<{path: String, mode: hrt.ui.HuiFileBrowser.BrowserMode}> {

	var fileBrowser : HuiFileBrowser;

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		saveDisplayKey = "/filebrowser";

		var path = state.path ?? hide.Ide.inst.resourceDir;
		fileBrowser = new HuiFileBrowser(path, this);
		fileBrowser.onOpen = (file) -> {
			if (file.kind == Dir)
				return;
			hide.Ide.inst.openFile(file.path);
		};
		updateMode(state.mode ?? FileTree);
		fileBrowser.onModeChange = () -> {
			state.mode = fileBrowser.mode;
			saveState();
		}
		fileBrowser.onModeMenu = (items) -> {
			items.push({isSeparator: true});
			addDockMenu(items);
		}
	}

	override function getViewName():String {
		return "File Browser";
	}

	function updateMode(mode: hrt.ui.HuiFileBrowser.BrowserMode) {
		state.mode = mode;
		fileBrowser.mode = mode;
		saveState();
	}

	override function getContextMenuContent(content:Array<hrt.ui.HuiMenu.MenuItem>) {
		content.push({label: "Refresh", click: () -> fileBrowser.markRefresh()});
		addDockMenu(content);
	}

	function addDockMenu(content:Array<hrt.ui.HuiMenu.MenuItem>) {
		var layout = uiBase.mainLayout.projectLayout;

		if (layout.leftPanel.contains(this)) {
			content.push({label: "Dock To Bottom", click: () -> moveTo(layout.bottomPanel)});
		} else {
			content.push({label: "Dock To Left", click: () -> moveTo(layout.leftPanel)});
		}
	}

	function moveTo(tabContainer: HuiTabContainer) {
		hide.App.defer(() -> {
			tabContainer.addTab(this);
			tabContainer.setTab(this);
			tabContainer.dom.applyStyle(uiBase.style);
		});
	}

	static var _ = HuiView.register("fileBrowser", FileBrowser);
}