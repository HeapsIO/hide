package hide.view;

class FileView extends hide.ui.View<{ path : String }> {

	var extension(get,never) : String;
	var modified(default,set) : Bool;

	function get_extension() {
		var file = state.path.split("/").pop();
		return file.indexOf(".") < 0 ? "" : file.split(".").pop().toLowerCase();
	}

	override function onBeforeClose() {
		if( modified && !js.Browser.window.confirm(state.path+" has been modified, quit without saving?") )
			return false;
		return super.onBeforeClose();
	}

	function set_modified(b) {
		if( modified == b )
			return b;
		modified = b;
		syncTitle();
		return b;
	}

	function getPath() {
		return ide.getPath(state.path);
	}

	override function getTitle() {
		return state.path.split("/").pop()+(modified?" *":"");
	}

}
