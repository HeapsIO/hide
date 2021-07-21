package hide.view;

enum LayoutDirection {
	Horizontal;
	Vertical;
}
class ResizablePanel extends hide.comp.Component {

	var scene : hide.comp.Scene;
	var layoutDirection : LayoutDirection;

	public function new(layoutDirection : LayoutDirection, element : Element, scene : hide.comp.Scene) {
		super(null, element);
		this.scene = scene;
		this.layoutDirection = layoutDirection;
		var splitter = new Element('<div class="lm_splitter"><div class="lm_drag_handle"></div></div>');
		switch (layoutDirection) {
			case Horizontal:
				splitter.addClass("lm_horizontal");
				splitter.width("5px");
			case Vertical:
				splitter.addClass("lm_vertical");
				splitter.height("5px");
		}
		splitter.insertBefore(element);
		var handle = splitter.find(".lm_drag_handle").first();
		var drag = false;
		var startSize = 0;
		var startPos = 0;
		handle.mousedown((e) -> {
			drag = true;
			startSize = Std.int(layoutDirection == Horizontal? element.width() : element.height());
			startPos = layoutDirection == Horizontal? e.clientX : e.clientY;
		});
		handle.mouseup((e) -> drag = false);
		handle.dblclick((e) -> {
			setSize(Std.parseInt(element.css("min-width")));
		});
		var scenePartition = element.parent();
		scenePartition.mousemove((e) -> {
			if (drag){
				setSize(startSize - ((layoutDirection == Horizontal? e.clientX : e.clientY) - startPos));
			}
		});
		scenePartition.mouseup((e) -> {
			drag = false;
		});
		scenePartition.mouseleave((e) -> {
			drag = false;
		});
	}

	public function setSize(?newSize : Int) {
		var minSize = (layoutDirection == Horizontal? Std.parseInt(element.css("min-width")) : Std.parseInt(element.css("min-height")));
		var maxSize = (layoutDirection == Horizontal? Std.parseInt(element.css("max-width")) : Std.parseInt(element.css("max-height")));
		var clampedSize = 0;
		if (newSize !=  null) clampedSize = hxd.Math.iclamp(newSize, minSize, maxSize);
		else clampedSize = hxd.Math.iclamp(getDisplayState("size"), minSize, maxSize);
		switch (layoutDirection) {
			case Horizontal :
				element.width(clampedSize);
			case Vertical :
				element.height(clampedSize);
		}
		if (newSize != null) saveDisplayState("size", clampedSize);
		@:privateAccess if( scene.window != null) scene.window.checkResize();
	}
}

class FileView extends hide.ui.View<{ path : String }> {

	public var extension(get,never) : String;
	public var modified(default, set) : Bool;
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

	public function save() {
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
