package hrt.impl;

import haxe.Int32;
import h3d.mat.Texture;
import h3d.Vector4;

typedef ColorStop = {position : Float, color : Int};

enum abstract GradientInterpolation(String) from String to String {
    var Linear;
    var Cubic;
    var Constant;
}

typedef GradientData = {
    var stops : Array<ColorStop>;
    var resolution : Int;
    var isVertical : Bool;
    var interpolation: GradientInterpolation;
    var colorMode: Int;
};

#if editor
typedef EditorCacheData = {
	var oldHash : Int;
	var tex : Texture;
};
#end

class Gradient {

    public var data : GradientData = {
        stops: new Array<ColorStop>(),
        resolution: 32,
        isVertical: false,
        interpolation: Linear,
        colorMode: 0,
    };

    public function new () {
    }

    public static function getDefaultGradientData() : GradientData {
        var data : GradientData = {stops: [{position: 0.0, color:0xFF000000}, {position: 1.0, color:0xFFFFFFFF}], resolution: 64, isVertical : false, interpolation: Linear, colorMode: 0};
        return data;
    }

    public static function evalData(data : GradientData, position : Float, ?outVector : Vector4) : Vector4 {
        if (outVector == null) outVector = new Vector4();
        var i : Int = 0;
        while(i < data.stops.length && data.stops[i].position < position) {
            i += 1;
        }

        var firstStopIdx : Int = hxd.Math.iclamp(i-1, 0, data.stops.length-1);
        var secondStopIdx : Int = hxd.Math.iclamp(i, 0, data.stops.length-1);

        var firstStop = data.stops[firstStopIdx];
        var secondStop = data.stops[secondStopIdx];

        var c1 : Int = firstStop.color;
        var c2 : Int = secondStop.color;

        var distance = secondStop.position - firstStop.position;
        var offsetFromSecondStop = secondStop.position - position;

        var blend = if (distance != 0.0) 1.0 - (offsetFromSecondStop / distance) else 0.0;
        blend = hxd.Math.clamp(blend, 0.0, 1.0);

        var func = ColorSpace.colorModes[data.colorMode];

        var start = func.ARGBToValue(ColorSpace.Color.fromInt(c1), null);
        var end = func.ARGBToValue(ColorSpace.Color.fromInt(c2), null);

        inline function lerp_angle(a:Float,b:Float,t:Float) : Float {
            var diff = (b - a) % 1.0;
            var dist = ((2.0 * diff) % 1.0) - diff;
            return outVector.x = (a + dist * t + 1.0) % 1.0;
        }

        switch (data.interpolation) {
            case Linear:
                outVector.lerp(start, end, blend);

                // Patch hue values that need to be lerped around the cercle
                if (func.name.charAt(0) == "H") {
                    outVector.x = lerp_angle(start.x, end.x, blend);
                }
            case Constant:
                outVector.load(start);
            case Cubic:
                // Honteusement copié de https://github.com/godotengine/godot/blob/c241f1c52386b21cf2df936ee927740a06970db6/scene/resources/gradient.h#L159
                var i0 = firstStopIdx-1;
                var i3 = secondStopIdx+1;
                if (i0 < 0) {
                    i0 = firstStopIdx;
                }
                if (i3 >= data.stops.length) {
                    i3 = data.stops.length-1;
                }
                var c0 = func.ARGBToValue(ColorSpace.Color.fromInt(data.stops[i0].color), null);
                var c3 = func.ARGBToValue(ColorSpace.Color.fromInt(data.stops[i3].color), null);

                inline function cubicInterpolate(p_from: Float, p_to: Float, p_pre: Float, p_post: Float, p_weight: Float) {
                    return 0.5 *
                            ((p_from * 2.0) +
                                    (-p_pre + p_to) * p_weight +
                                    (2.0 * p_pre - 5.0 * p_from + 4.0 * p_to - p_post) * (p_weight * p_weight) +
                                    (-p_pre + 3.0 * p_from - 3.0 * p_to + p_post) * (p_weight * p_weight * p_weight));
                }

                outVector.r = cubicInterpolate(start.r, end.r, c0.r, c3.r, blend);
                outVector.g = cubicInterpolate(start.g, end.g, c0.g, c3.g, blend);
                outVector.b = cubicInterpolate(start.b, end.b, c0.b, c3.b, blend);
                outVector.a = cubicInterpolate(start.a, end.a, c0.a, c3.a, blend);
            default:
                throw "Unknown interpolation mode";

        }

        var tmp = func.valueToARGB(outVector, null);
        ColorSpace.iRGBtofRGB(tmp, outVector);

        return outVector;
    }

    public function eval(position : Float, ?outVector : Vector4) : Vector4 {
        return evalData(data, position, outVector);
    }

	#if !editor
    static function getCache() : Map<Int32, h3d.mat.Texture> {
		var engine = h3d.Engine.getCurrent();
		var cache : Map<Int32, h3d.mat.Texture> = @:privateAccess engine.resCache.get(Gradient);
		if(cache == null) {
			cache = new Map<Int32, h3d.mat.Texture>();
			@:privateAccess engine.resCache.set(Gradient, cache);
		}
        return cache;
    }
	#end

	#if editor
	public static function getEditorCache() : Map<{}, EditorCacheData> {
		var engine = h3d.Engine.getCurrent();
		var cache : Map<{}, EditorCacheData> = @:privateAccess engine.resCache.get(Gradient);
		if(cache == null) {
			cache = new Map<{}, EditorCacheData>();
			@:privateAccess engine.resCache.set(Gradient, cache);
		}
        return cache;
	}

	public static function purgeEditorCache() {
		var cache = getEditorCache();
		for (c in cache) {
			if (c.tex != null) {
				c.tex.dispose();
			}
		}
		cache.clear();
	}
	#end

    public static function getDataHash(data : GradientData) : Int32 {

        var hash = hxd.Rand.hash(data.resolution);
        hash = hxd.Rand.hash(data.isVertical ? 0 : 1, hash);

        // Vieux hack nul
        hash = hxd.Rand.hash((data.interpolation:String).charCodeAt(0), hash);
        hash = hxd.Rand.hash((data.interpolation:String).charCodeAt(1), hash);

        hash = hxd.Rand.hash(data.colorMode, hash);

        for (stop in data.stops) {
            hash =  hxd.Rand.hash(stop.color, hash);
            hash = hxd.Rand.hash(Std.int(stop.position * 0x7FFFFFFF), hash);
        }
        return hash;
    }

    public static function textureFromCDB( g : cdb.Types.Gradient, size : Int ) {
        if( g == null ) return null;
        var d : GradientData = {
            stops : [for( i in 0...g.data.colors.length ) { position : g.data.positions[i], color : g.data.colors[i] }],
            resolution : size,
            isVertical : false,
            interpolation: Linear,
            colorMode: 0,
        };
        return textureFromData(d);
    }

    public static function textureFromData(data : GradientData) : h3d.mat.Texture {

        var hash = getDataHash(data);
		#if !editor

        var cache = getCache();
        var entry = cache.get(hash);
        if (entry != null)
        {
            return entry;
        }
		#else
		var cache = getEditorCache();
		var entry = cache.get(data);
		if (entry != null)
		{
            if (entry.oldHash != hash) {
                entry.oldHash = hash;
                entry.tex.realloc();
            }
            return entry.tex;
		}
		#end

        #if !release
        var oldHash = Gradient.getDataHash(data);
        #end
        function genPixels() {
            #if !release
            var newHash = Gradient.getDataHash(data);

            var cache = getEditorCache();
            var entry = cache.get(data);
            if (entry != null) {
                if (entry.oldHash != newHash) {
                    throw "gradient data has changed between first generation and realloc";
                }
            }

            // If this ever become an issue because we need this feature, we just need to deep copy 'data'
            // and use this copy in the genPixels function. But at this moment we consider that it's a bug
            #end
            var xScale = data.isVertical ? 0 : 1;
            var yScale = 1 - xScale;
            var pixels = hxd.Pixels.alloc(data.resolution * xScale + 1 * yScale,1 * xScale + data.resolution * yScale, ARGB);

            var vec = new Vector4();
            for (x in 0...data.resolution) {
                evalData(data, x / (data.resolution-1), vec);
                pixels.setPixelF(x * xScale,x*yScale, vec);
            }
            return pixels;
        }


        var texture = Texture.fromPixels(genPixels(), RGBA);
        texture.realloc = function() {
            texture.uploadPixels(genPixels());
        }

		#if !editor
        cache.set(hash, texture);
		#else
		cache.set(data, {oldHash: hash, tex: texture});
		#end

        return texture;
    }

    public function toTexture() : h3d.mat.Texture {
        return textureFromData(data);
    }
}