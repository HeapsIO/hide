package hrt.impl;

import hrt.impl.Gradient;

enum abstract TextureType(String) from String to String {
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
                        var gradData = Utils.getGradientData((val:Dynamic));
                        if (gradData != null) {
                            var t = Gradient.textureFromData(gradData);
                            return t;
                        }
                    }
                    default:
                }
            }
        }
        return null;
    }

    // Returns null if value is not a GradientData
    public static function getGradientData(value : Any)  : Null<Gradient.GradientData> {
        if (getTextureType(value) == gradient) {
            var gradientData = ((value:Dynamic).data:GradientData);
            gradientData.interpolation = gradientData.interpolation != null ? gradientData.interpolation : Linear;
            gradientData.colorMode = (gradientData.colorMode:Dynamic) != null ? gradientData.colorMode : 0;

            return gradientData;
        }
        return null;
    }

    public static function getTextureType(value : Any) : Null<TextureType> {
        if (value == null || Std.isOfType(value, String)) {
            return TextureType.path;
        }
        else if (Type.typeof(value) == TObject) {
            var v : Dynamic = (value:Dynamic);

            if (v.type != null && Std.isOfType(v.type, String)) {
                switch ((v.type:String):TextureType) {
                    case TextureType.gradient: return TextureType.gradient;
                    default:
                        return null;
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
