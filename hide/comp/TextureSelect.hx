package hide.comp;

class TextureSelect extends FileSelect {

	public var value(default, set) : h3d.mat.Texture;
	public var area(default, set) : { x : Int, y : Int, width : Int, height : Int };
	var preview : Element;

	public function new(?parent,?root) {
		preview = new Element("<div class='texture-preview'>");
		super(["jpg", "jpeg", "gif", "png"], parent, root);
		preview.insertAfter(root);
	}

	override function remove() {
		super.remove();
		preview.remove();
	}

	function set_area(v) {
		area = v;
		this.path = path;
		return v;
	}

	override function set_path(p:String) {
		super.set_path(p);
		if( p == null )
			value = null;
		else if( value == null || value.name != p ) {
			var scene = Scene.getNearest(element);
			if( scene != null ) {
				scene.setCurrent();
				value = scene.loadTexture("", p);
			}
		}
		if( p == null )
			preview.hide();
		else {
			preview.show();
			preview.css("background-image", "url('file://" + ide.getPath(p) + "')");
			preview.css("background-size", area == null ? "15px 15px" : area.width + "px " + area.height + "px");
			preview.css("background-position", area == null ? "" : area.x + "px " + area.y + "px");
		}
		return p;
	}

	function set_value(t:h3d.mat.Texture) {
		value = t;
		var p = value == null ? null : value.name;
		if( p != path )
			this.path = p;
		return t;
	}

}