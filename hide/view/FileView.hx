package hide.view;

class FileView extends hide.ui.View<{ path : String }> {

	public var extension(get,never) : String;
	public var modified(default, set) : Bool;
	var skipNextChange : Bool;

	public function new(state) {
		super(state);
		if( state.path != null )
			watch(state.path, function() {
				if( skipNextChange ) {
					skipNextChange = false;
					return;
				}
				onFileChanged(!sys.FileSystem.exists(ide.getPath(state.path)));
			}, { checkDelete : true, keepOnRebuild : true });
	}

	function onFileChanged( wasDeleted : Bool ) {
		if( wasDeleted ) {
			if( modified ) return;
			element.html('${state.path} no longer exists');
			return;
		}
		if( modified && !ide.confirm('${state.path} has been modified, reload and ignore local changes?') )
			return;
		modified = false;
		rebuild();
	}

	function get_extension() {
		if( state.path == null )
			return "";
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
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
		keys.register("save", function() {
			save();
			skipNextChange = true;
			modified = false;
			lastSave = undo.currentID;
		});
	}

	public function save() {
	}

	public function saveAs() {
		ide.chooseFileSave(state.path, function(target) {
			if( target == null ) return;
			state.path = target;
			save();
			modified = false;
			syncTitle();
		});
	}

	override function onBeforeClose() {
		if( modified && !js.Browser.window.confirm(state.path+" has been modified, quit without saving?") )
			return false;
		return super.onBeforeClose();
	}

	override function get_config() {
		if( config == null ) {
			if( state.path == null ) return super.get_config();
			config = hide.Config.loadForFile(ide, state.path);
		}
		return config;
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
		if( parts[parts.length - 1] == "" ) parts.pop(); // directory
		while( parts.length > 2 ) parts.shift();
		return parts.join(" / ")+(modified?" *":"");
	}

	override function syncTitle() {
		super.syncTitle();
		if( state.path != null )
			haxe.Timer.delay(function() container.tab.element.attr("title",getPath()), 100);
	}

	override function buildTabMenu() {
		var arr : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{ label : "Save", enabled : modified, click : function() { save(); modified = false; } },
			{ label : "Save As...", click : saveAs },
			{ label : null, isSeparator : true },
			{ label : "Reload", click : function() rebuild() },
			{ label : null, isSeparator : true },
		];
		return arr.concat(super.buildTabMenu());
	}

}
