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
					if( path == null ) return; // cancel
					this.path = path;
					onChange();
				});
			}
		});
		root.contextmenu(function(e) {
			e.preventDefault();
			var fpath = getFullPath();
			new ContextMenu([
				{ label : "View", enabled : fpath != null, click : function() ide.openFile(fpath) },
				{ label : "Clear", enabled : path != null, click : function() { path = null; onChange(); } },
			]);
			return false;
		});
		// allow drag files
		root.on("dragover", function(e) {
			root.addClass("dragover");
			e.preventDefault();
		});
		root.on("dragleave", function(e) {
			root.removeClass("dragover");
		});
		root.on("drop", function(e:js.jquery.Event) {
			root.removeClass("dragover");
			var file = getTransferFile(e);
			if( file != null ) {
				path = file;
				onChange();
			}
			e.preventDefault();
		});
	}

	function getTransferFile( e : js.jquery.Event ) {
		var data : js.html.DataTransfer = untyped e.originalEvent.dataTransfer;
		var text = data.getData("text/html");
		var path : String = null;

		if( data.files.length > 0 )
			path = untyped data.files[0].path;
		else if( StringTools.startsWith(text, "<a") && text.indexOf("jstree-anchor") > 0 ) {
			var rpath = ~/id="([^"]+)_anchor"/;
			if( rpath.match(text) )
				path = rpath.matched(1);
		}
		if( path != null && sys.FileSystem.exists(ide.getPath(path)) && extensions.indexOf(path.split(".").pop().toLowerCase()) >= 0 )
			return ide.makeRelative(path);
		return null;
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