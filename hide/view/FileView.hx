package hide.view;

class FileView extends hide.ui.View<{ path : String }> {

	public var extension(get,never) : String;
	public var modified(default, set) : Bool = false;
	var skipNextChange : Bool;
	var lastSaveTag : Int;

	var currentSign : String;

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

	override function onRebuild() {
		var path = getPath();
		if( path != null ) {
			saveDisplayKey = Type.getClassName(Type.getClass(this)) + ":" + path.split("\\").join("/");
			if( !sys.FileSystem.exists(path) ) {
				element.html('${state.path} no longer exists');
				return;
			}
		}
		super.onRebuild();
	}

	function makeSign() {
		var content = sys.io.File.getContent(getPath());
		return haxe.crypto.Md5.encode(content);
	}

	function onFileChanged( wasDeleted : Bool, rebuildView = true ) {
		if( !wasDeleted && currentSign != null ) {
			// double check if content has changed
			if( makeSign() == currentSign )
				return;
		}
		if( wasDeleted ) {
			if( modified ) return;
			element.html('${state.path} no longer exists');
			return;
		}

		if( modified && !ide.confirm('${state.path} has been modified, reload and ignore local changes?') )
			return;
		modified = false;
		lastSaveTag = 0;
		undo.clear(); // prevent any undo that would reset past reload
		if( rebuildView )
			rebuild();
	}

	function get_extension() {
		if( state.path == null )
			return "";
		var file = state.path.split("/").pop();
		return file.indexOf(".") < 0 ? "" : file.split(".").pop().toLowerCase();
	}

	public function getDefaultContent() : haxe.io.Bytes {
		throw "Not implemented";
		return null;
	}

	override function setContainer(cont) {
		super.setContainer(cont);
		lastSaveTag = undo.currentID;
		undo.onChange = function() {
			modified = (undo.currentID != lastSaveTag);
		};
		keys.register("undo", function() undo.undo());
		keys.register("redo", function() undo.redo());
		keys.register("save", function() save());
		keys.register("view.refresh", function() rebuild());
		keys.register("view.refreshApp", function() untyped chrome.runtime.reload());
	}

	public function canSave() {
		return true;
	}

	public function save() {
		if( !canSave() )
			return;
		skipNextChange = true;
		modified = false;
		lastSaveTag = undo.currentID;
	}

	function saveBackup(content: String) {
		var tmpPath = ide.resourceDir + "/.tmp/" + state.path;
		var baseName = haxe.io.Path.withoutExtension(tmpPath);
		var tmpDir = haxe.io.Path.directory(tmpPath);

		// Save backup file
		try {
			sys.FileSystem.createDirectory(tmpDir);
			var dateFmt = DateTools.format(Date.now(), "%Y%m%d-%H%M%S");
			sys.io.File.saveContent(baseName + "-backup" + dateFmt + "." + haxe.io.Path.extension(state.path), content);
		}
		catch (e: Dynamic) {
			trace("Cannot save backup", e);
		}

		// Delete old files
		var allTemp = [];
		for( f in try sys.FileSystem.readDirectory(tmpDir) catch( e : Dynamic ) [] ) {
			if(~/-backup[0-9]{8}-[0-9]{6}$/.match(haxe.io.Path.withoutExtension(f))) {
				allTemp.push(f);
			}
		}
		allTemp.sort(Reflect.compare);
		if(allTemp.length > 10) {
			sys.FileSystem.deleteFile(tmpDir + "/" + allTemp[0]);
		}
	}

	public function saveAs() {
		ide.chooseFileSave(state.path, function(target) {
			state.path = target;
			save();
			skipNextChange = false;
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
			haxe.Timer.delay(function() if( container.tab != null ) container.tab.element.attr("title",getPath()), 100);
	}

	override function buildTabMenu() {
		var hasPath = state.path != null && state.path != "";
		var reloadItem : hide.comp.ContextMenu.ContextMenuItem = { label : "Reload", click : function() rebuild() };
		var arr : Array<hide.comp.ContextMenu.ContextMenuItem>;
		if( !hasPath && !canSave() ) {
			arr = [
				reloadItem,
				{ label : null, isSeparator : true },
			];
		}
		else {
			arr = [
				{ label : "Save", enabled : canSave() && modified, click : function() { save(); modified = false; } },
				{ label : "Save As...", enabled : canSave(), click : saveAs },
				{ label : null, isSeparator : true },
				reloadItem,
				{ label : "Copy Path", enabled : hasPath, click : function() { ide.setClipboard(state.path); } },
				{ label : "Open in Explorer", enabled : hasPath, click : function() { FileTree.exploreFile(getPath()); } },
				{ label : "Open in Resources", enabled : hasPath, click : function() {
					var filetree = ide.getViews(FileTree)[0];
					if( filetree != null ) {
						filetree.revealNode(state.path);
					}
				}},
				{ label : null, isSeparator : true },
			];
		}
		return arr.concat(super.buildTabMenu());
	}
}
