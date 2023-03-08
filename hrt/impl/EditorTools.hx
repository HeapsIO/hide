package hrt.impl;

#if editor

class EditorIcon extends hrt.prefab.l3d.Billboard.BillboardObj {
    public var scaleWithParent = false;

	public function new(?tile : h3d.mat.Texture,  ?parent : h3d.scene.Object) {
		super(tile, parent);
		ignoreCollide = false;
	}

	override function sync(ctx) {
        visible = hide.Ide.inst.show3DIcons;
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

class EditorTools {
    public static function create3DIcon(object:h3d.scene.Object, iconPath:String, scale:Float = 1.0) : EditorIcon {
        var ide = hide.Ide.inst;
        var tex = ide.getTexture(ide.getHideResPath(iconPath));
        var icon = new EditorIcon(tex, object);

        icon.texture = tex;
		icon.billboardScale = scale;

        return icon;
    }
}
#end