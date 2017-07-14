package hide.view;

class FileView extends hide.ui.View<{ path : String }> {

	var extension(get,never) : String;
	var modified(default,set) : Bool;
	var props(get, null) : hide.comp.Props;
	var undo = new hide.comp.UndoHistory();

	function get_extension() {
		var file = state.path.split("/").pop();
		return file.indexOf(".") < 0 ? "" : file.split(".").pop().toLowerCase();
	}

	public function getDefaultContent() : haxe.io.Bytes {
		return null;
	}

	override function setContainer(cont) {
		super.setContainer(cont);
		var lastSave = undo.currentID;
		undo.onChange = function() {
			modified = (undo.currentID != lastSave);
		};
		registerKey("undo", function() undo.undo());
		registerKey("redo", function() undo.redo());
		registerKey("save", function() {
			save();
			modified = false;
			lastSave = undo.currentID;
		});
	}

	public function save() {
	}

	override function onBeforeClose() {
		if( modified && !js.Browser.window.confirm(state.path+" has been modified, quit without saving?") )
			return false;
		return super.onBeforeClose();
	}

	function get_props() {
		if( props == null )
			props = hide.comp.Props.loadForFile(ide, state.path);
		return props;
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
		var parts = state.path.split("/");
		while( parts.length > 2 ) parts.shift();
		return parts.join(" / ")+(modified?" *":"");
	}

	override function syncTitle() {
		super.syncTitle();
		haxe.Timer.delay(function() container.tab.element.attr("title",getPath()), 100);
	}

}
