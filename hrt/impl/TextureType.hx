package hrt.impl;

@:enum
abstract TextureType(String) from String to String {
    var gradient;
    var path;       // Not used as a type inside the json (the playload is a string), default value
}

class Utils {
    public static function getTextureFromValue(val : Any) : h3d.mat.Texture {
        if (Std.isOfType(val, String)) {
            var t = hxd.res.Loader.currentInstance.load(val).toTexture();
            t.wrap = Repeat;
            return t;
        }
        else if (Type.typeof(val) == TObject) {
            var val = (val:Dynamic);
            if (val.type != null && Std.isOfType(val.type, String)) {

                switch((val.type:String):TextureType) {
                    case TextureType.gradient:
                    {
                        if (Reflect.hasField(val.data, "stops") && Reflect.hasField(val.data, "resolution")) {
                            var t = Gradient.textureFromData(val.data);
                            return t;
                        }
                    }
                    default:
                }
            }
        }
        return null;
    }

    public static function copyTextureData(val : Any) : Any {
        if (Type.typeof(val) == TObject)
            return haxe.Json.parse(haxe.Json.stringify(val));

        return val;
    }
}
