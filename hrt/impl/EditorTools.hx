package hrt.impl;

#if editor

class EditorIcon extends hrt.prefab.l3d.Billboard.BillboardObj {
    public var scaleWithParent = false;
	public var category : IconCategory;

	public function new(?tile : h3d.mat.Texture,  ?parent : h3d.scene.Object, category: IconCategory) {
		super(tile, parent);
		ignoreCollide = false;
		this.category = category;
	}

	override function sync(ctx) {
        visible =  EditorTools.isVisible(category);
        super.sync(ctx);
    }

	override function getLocalCollider():h3d.col.Collider {
		return new h3d.col.Sphere(0,0,0,billboardScale/2.0);
	}

	// Ingonre scale and rotation
	override function calcAbsPos() {
		absPos.identity();
		absPos.tx = x;
		absPos.ty = y;
		absPos.tx = z;

		if (parent != null) {
			absPos.tx += parent.absPos.tx;
			absPos.ty += parent.absPos.ty;
			absPos.tz += parent.absPos.tz;
		}

		if( invPos != null )
			invPos._44 = 0; // mark as invalid
	}
}

class Editor2DIcon extends h2d.ObjectFollower {
	public var category : IconCategory;


	public function new( obj, ?parent, texture, category: IconCategory)  {
		super(obj, parent);
		horizontalAlign = Middle;
		followVisibility = true;
		var ico = new h2d.Bitmap(h2d.Tile.fromTexture(texture), this);
		this.category = category;

	}

	override function sync(ctx) {
		visible = EditorTools.isVisible(category);
		super.sync(ctx);
	}
}

enum IconCategory {
	Light;
	Trails;
	Object3D;
	Audio;
	Misc;
}

class EditorTools {
	// Create a 3d Icon that will be displayed inside the scene as a 3d object, meaning that it can be
	// obscured by the other objects
    public static function create3DIcon(object:h3d.scene.Object, iconPath:String, scale:Float = 1.0, category: IconCategory) : EditorIcon {
		var ide = hide.Ide.inst;
        var tex = ide.getTexture(iconPath);
        var icon = new EditorIcon(tex, object, category);

        icon.texture = tex;
		icon.billboardScale = scale;

        return icon;
    }

	// Creates a 2d Icon that will be displayed in front of all the other icons
	public static function create2DIcon(object: h3d.scene.Object, s2d: h2d.Object, iconPath: String, category: IconCategory) : Editor2DIcon {
		var ide = hide.Ide.inst;
		return new Editor2DIcon(object, s2d, ide.getTexture(iconPath), category);
	}

	public static function setupIconCategories() {
		for (categoryName in haxe.EnumTools.getConstructors(IconCategory)) {
			var category = haxe.EnumTools.createByName(IconCategory, categoryName, []);
			var ide = hide.Ide.inst;
			if(!ide.show3DIconsCategory.exists(category)) {
				var value = js.Browser.window.localStorage.getItem(iconVisibilityKey(category));
				var shouldBeDisplayed = false;
				if (value == null || value == "true") {
					shouldBeDisplayed = true;
				}
				ide.show3DIconsCategory.set(category, shouldBeDisplayed);
			}
		}
	}

	public static function iconVisibilityKey(category: IconCategory) {
		return "3dIconVisibility/" + haxe.EnumTools.EnumValueTools.getName(category);
	}

	public static function isVisible(category: IconCategory) : Bool {
		return hide.Ide.inst.show3DIcons && hide.Ide.inst.show3DIconsCategory.get(category);
	}
}
#end