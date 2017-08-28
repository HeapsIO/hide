package hide.comp;

class FileSelect extends Component {

	public var path(default, set) : String;

	public function new(root, extensions) {
		super(root);
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
		root.val(text);
		root.attr("title", p == null ? "" : p);
		return this.path = p;
	}

	public dynamic function onChange() {
	}

}