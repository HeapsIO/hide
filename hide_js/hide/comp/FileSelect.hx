package hide.comp;

class FileSelect extends Component {

	var extensions : Array<String>;
	public var path(default, set) : String;
	public var disabled(default, set) = false;
	public var directory : Bool = false;
	// the path is saved as absolute, instead of relative to the resources
	public var absolutePath : Bool = false;
	// displayed when the path is null
	public var nullPrompt : String = "-- select --";

	public function new(extensions,?parent,?root, handleDragAndDrop=true) {
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
					ide.chooseFileOptions(function(files) {
						this.path = files.pop();
						onChange();
					}, { exts : extensions, workingDir : path, isAbsolute : absolutePath });
				} else {
					ide.chooseDirectory(function(path) {
						this.path = path;
						onChange();
					}, absolutePath);
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
					hide.tools.IdeData.showFileInExplorer(fpath);
				} },
				{ label : "Open in Resources", enabled : path != null, click : function() {
					ide.showFileInResources(path);
				}},
			]);
			return false;
		}

		root.parent().prev("dt").contextmenu(contextMenu);
		root.contextmenu(contextMenu);

		if (handleDragAndDrop) {

			hide.tools.DragAndDrop.makeDropTarget(root.get(0), (event: hide.tools.DragAndDrop.DropEvent, dragData: hide.tools.DragAndDrop.DragData) -> {
				var paths : Array<hide.tools.FileManager.FileEntry> = cast dragData.data.get("drag/filetree") ?? [];
				if (paths.length == 0) {
					dragData.dropTargetValidity = ForbidDrop;
					return;
				}

				var newPath = absolutePath ? ide.getPath(paths[0].path) : ide.makeRelative(paths[0].path);
				if (!pathIsValid(newPath)) {
					dragData.dropTargetValidity = ForbidDrop;
					return;
				}

				switch (event) {
					case Enter:
						root.addClass("fancy-drag-drop-target");
					case Leave:
						root.removeClass("fancy-drag-drop-target");
					case Move:
					case Drop:
						path = newPath;
						onChange();
				}
			});
		}

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

	function pathIsValid( path : String ) : Bool {
		return pathIsValidStatic(path, extensions, directory);
	}

	static public function pathIsValidStatic(path: String, extensions: Array<String>, directory: Bool) : Bool {
		if (!directory) {
			return (
				path != null
				&& sys.FileSystem.exists(hide.Ide.inst.getPath(path))
				&& extensions.indexOf(path.split(".").pop().toLowerCase()) >= 0
			);
		} else {
			return (
				path != null
				&& sys.FileSystem.exists(hide.Ide.inst.getPath(path))
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
		try {
			if (absolutePath)
				exists = p != null && sys.FileSystem.exists(p);
			else if (fullPath != null) {
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
		} catch(e) {
		}

		var text = p == null ? nullPrompt : (exists ? "" : "[NOT FOUND] ") + p;
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