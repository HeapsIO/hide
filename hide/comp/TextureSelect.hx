package hide.comp;

class TextureSelect extends Component {

	var engine : h3d.Engine;
	public var value(default, set) : h3d.mat.Texture;

	public function new(root) {
		super(root);
		root.mousedown(function(e) {
			e.preventDefault();
			if( e.button == 0 ) {
				ide.chooseFile(["jpg", "jpeg", "gif"], function(path) {
					value = Scene.getNearest(root).loadTextureFile("", path);
					onChange();
				});
			}
		});
		root.contextmenu(function(e) {
			e.preventDefault();
			var path = getPath();
			new ContextMenu([
				{ label : "View", enabled : path != null, click : function() ide.open("hide.view.Image", {path:path}) },
				{ label : "Clear", enabled : value != null, click : function() { value = null; onChange(); } },
			]);
			return false;
		});
	}

	public function getPath() {
		var t = value;
		if( t == null || t.name == null )
			return null;
		var path = ide.getPath(t.name);
		if( sys.FileSystem.exists(path) )
			return path;
		return null;
	}

	function set_value(t:h3d.mat.Texture) {
		var path = t == null ? "-- select --" : t.name == null ? "????" : (sys.FileSystem.exists(ide.getPath(t.name)) ? "" : "[NOT FOUND]") + t.name;
		root.val(path);
		root.attr("title", t == null ? "" : t.name);
		return value = t;
	}

	public dynamic function onChange() {
	}

}