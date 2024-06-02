package hide.comp;

class FileSelect extends Component {

	var extensions : Array<String>;
	public var path(default, set) : String;

	public function new(extensions,?parent,?root) {
		if( root == null )
			root = new Element("<input>");
		super(parent,root);
		root.addClass("file");
		this.extensions = extensions;
		path = null;
		root.mousedown(function(e) {
			e.preventDefault();
			if( e.button == 0 ) {
				ide.chooseFile(extensions, function(path) {
					this.path = path;
					onChange();
				}, false, path);
			}
		});

		function contextMenu(e) {
			e.preventDefault();
			var fpath = getFullPath();
			new ContextMenu([
				{ label : "View", enabled : fpath != null, click : function() ide.openFile(fpath) },
				{ label : "Clear", enabled : path != null, click : function() { path = null; onChange(); } },
				{ label : "Copy Path", enabled : path != null, click : function() ide.setClipboard(path) },
				{ label : "Paste Path", click : function() {
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

	public function onDragDrop( items : Array<String>, isDrop : Bool ) : Bool {
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
		return (
			path != null
			&& sys.FileSystem.exists(ide.getPath(path))
			&& extensions.indexOf(path.split(".").pop().toLowerCase()) >= 0
		);
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
		var text = p == null ? "-- select --" : (sys.FileSystem.exists(ide.getPath(p)) ? "" : "[NOT FOUND] ") + p;
		element.val(text);
		element.attr("title", p == null ? "" : p);
		return this.path = p;
	}

	public dynamic function onChange() {
	}

}