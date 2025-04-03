package hide.comp;

class FileSelect extends Component {

	var extensions : Array<String>;
	public var path(default, set) : String;
	public var disabled(default, set) = false;
	public var directory : Bool = false;

	public function new(extensions,?parent,?root) {
		if( root == null )
			root = new Element("<input>");
		super(parent,root);
		root.addClass("file");
		this.extensions = extensions;
		path = null;
		root.mousedown(function(e) {
			e.preventDefault();
			if (disabled) return;
			if( e.button == 0 ) {
				if (!directory) {
					ide.chooseFile(extensions, function(path) {
						this.path = path;
						onChange();
					}, false, path);
				} else {
					ide.chooseDirectory(function(path) {
						this.path = path;
						onChange();
					}, false);
				}
			}
		});

		function contextMenu(e) {
			e.preventDefault();
			var fpath = getFullPath();
			ContextMenu.createFromEvent(cast e, [				{ label : "View", enabled : fpath != null, click : function() onView() },
				{ label : "Clear", enabled : path != null && !disabled, click : function() { path = null; onChange(); } },
				{ label : "Copy Path", enabled : path != null, click : function() ide.setClipboard(path) },
				{ label : "Copy Absolute Path", enabled : fpath != null, click : function() { ide.setClipboard(fpath); } },
				{ label : "Paste Path", enabled: !disabled, click : function() {
					path = ide.getClipboard();
					onChange();
				}},
				{ label : "Open in Explorer", enabled : fpath != null, click : function(){
					Ide.showFileInExplorer(fpath);
				} },
				{ label : "Open in Resources", enabled : path != null, click : function() {
					ide.showFileInResources(path);
				}},
			]);
			return false;
		}

		root.parent().prev("dt").contextmenu(contextMenu);
		root.contextmenu(contextMenu);

		// allow drag files
		root.on("dragover", function(e) {
			root.addClass("dragover");
		});
		root.on("dragleave", function(e) {
			root.removeClass("dragover");
		});
		root.on("drop", function(e) {
			root.removeClass("dragover");
		});
	}

	public dynamic function onView() {
		ide.openFile(getFullPath());
	}

	public function onDragDrop( items : Array<String>, isDrop : Bool, event: js.html.DragEvent) : Bool {
		if( items.length == 0 )
			return false;
		var newPath = ide.makeRelative(items[0]);
		if( pathIsValid(newPath) ) {
			if( isDrop ) {
				path = newPath;
				onChange();
			}
			return true;
		}
		return false;
	}

	function pathIsValid( path : String ) : Bool {
		if (!directory) {
			return (
				path != null
				&& sys.FileSystem.exists(ide.getPath(path))
				&& extensions.indexOf(path.split(".").pop().toLowerCase()) >= 0
			);
		} else {
			return (
				path != null
				&& sys.FileSystem.exists(ide.getPath(path))
				&& sys.FileSystem.isDirectory(path)
			);
		}
	}


	public function getFullPath() {
		if( path == null )
			return null;
		var fpath = ide.getPath(path);
		if( sys.FileSystem.exists(fpath) )
			return fpath;
		return null;
	}

	function set_path(p:String) {
		// We need to do this comparison since sys.FileSystem.exists() is case insensitive on Windows
		var fullPath = ide.getPath(p);
		var exists = false;
		if (fullPath != null) {
			var filename = fullPath.substr(fullPath.lastIndexOf('/') + 1);
			var parentDir = fullPath.substring(0, fullPath.lastIndexOf('/'));
			var files = sys.FileSystem.readDirectory(parentDir);
			for (f in files) {
				if (f == filename) {
					exists = true;
					break;
				}
			}
		}
		var text = p == null ? "-- select --" : (exists ? "" : "[NOT FOUND] ") + p;
		element.val(text);
		element.attr("title", p == null ? "" : p);
		return this.path = p;
	}

	function set_disabled(disabled : Bool) {
		element.toggleClass("disabled", disabled);
		return this.disabled = disabled;
	}

	public dynamic function onChange() {
	}

}