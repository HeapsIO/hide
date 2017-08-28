package hide.comp;

class TextureSelect extends FileSelect {

	public var value(default, set) : h3d.mat.Texture;

	public function new(root) {
		super(root,["jpg", "jpeg", "gif"]);
	}

	override function set_path(p:String) {
		super.set_path(p);
		if( p == null )
			value = null;
		else if( value == null || value.name != p )
			value = Scene.getNearest(root).loadTextureFile("", p);
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