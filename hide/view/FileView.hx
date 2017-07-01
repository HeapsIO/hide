package hide.view;

class FileView extends hide.ui.View<{ path : String }> {

	function getPath() {
		return ide.getPath(state.path);
	}

	override function getTitle() {
		return state.path.split("/").pop();
	}

}
