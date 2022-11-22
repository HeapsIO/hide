package hrt.impl;

#if editor

class EditorIcon extends hrt.prefab.l3d.Billboard.BillboardObj {
    override function sync(ctx) {
        visible = hide.Ide.inst.show3DIcons;
        super.sync(ctx);
    }
}

class EditorTools {
    public static function create3DIcon(object:h3d.scene.Object, iconPath:String, scale:Float = 1.0) : EditorIcon {
        var ide = hide.Ide.inst;
        var tex = ide.getTexture(ide.getHideResPath(iconPath));
        var icon = new EditorIcon(tex, object);

        icon.texture = tex;
        icon.scale(scale);

        return icon;
    }
}
#end