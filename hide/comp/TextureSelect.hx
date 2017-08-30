package hide.comp;

class TextureSelect extends FileSelect {

	public var value(default, set) : h3d.mat.Texture;
	public var area(default, set) : { x : Int, y : Int, width : Int, height : Int };
	var preview : Element;

	public function new(root) {
		preview = new Element("<div class='texture-preview'>");
		preview.insertAfter(root);
		super(root, ["jpg", "jpeg", "gif", "png"]);
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
		else if( value == null || value.name != p )
			value = Scene.getNearest(root).loadTextureFile("", p);
		if( p == null )
			preview.hide();
		else {
			preview.show();
			preview.css("background-image", "url(file://" + ide.getPath(p) + ")");
			preview.css("background-size", area == null ? "" : area.width + "px " + area.height + "px");
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