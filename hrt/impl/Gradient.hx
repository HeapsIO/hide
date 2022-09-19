package hrt.impl;

import haxe.Json;
import haxe.Int64;
import haxe.Int32;
import h3d.Engine;
import h3d.mat.Texture;
import h3d.Vector;

typedef ColorStop = {position : Float, color : Int};

typedef GradientData = {
    var stops : Array<ColorStop>;
    var resolution : Int;
};

class Gradient {
    public var data : GradientData = {
        stops: new Array<ColorStop>(),
        resolution: 32
    };

    public function new () {
    }

    public static function getDefaultGradientData() : GradientData {
        var data : GradientData = {stops: [{position: 0.0, color:0xFF000000}, {position: 1.0, color:0xFFFFFFFF}], resolution: 64};
        return data;
    }

    public static function evalData(data : GradientData, position : Float, ?outVector : Vector) : Vector {
        if (outVector == null) outVector = new Vector(); 
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
        var start = Vector.fromColor(c1);
        var end = Vector.fromColor(c2);

        outVector.lerp(start, end, blend);
        
        return outVector;
    }

    public function eval(position : Float, ?outVector : Vector) : Vector {
        return evalData(data, position, outVector);
    }

    public static function getCache() : Map<Int32, h3d.mat.Texture> {
		var engine = h3d.Engine.getCurrent();
		var cache : Map<Int32, h3d.mat.Texture> = @:privateAccess engine.resCache.get(Gradient);
		if(cache == null) {
			cache = new Map<Int32, h3d.mat.Texture>();
			@:privateAccess engine.resCache.set(Gradient, cache);
		}
        return cache;
    }

    public static function hashCombine(hash : Int32, newValue : Int32) : Int32 {
        return hash ^ (newValue * 0x01000193);
    }

    public static function getDataHash(data : GradientData) : Int32 {
        var hash = hashCombine(0, data.resolution);
        for (stop in data.stops) {
            hash = hashCombine(hash, stop.color);
            hash = hashCombine(hash, Std.int(stop.position * 214748357));
        };
        return hash;
    }

    public static function textureFromData(data : GradientData) : h3d.mat.Texture {
        var hash = getDataHash(data);

        var cache = getCache();
        var entry = cache.get(hash);
        if (entry != null)
        {
            return entry;
        }

        #if !release
        var oldHash = Gradient.getDataHash(data);
        #end
        function genPixels() {
            #if !release
            var newHash = Gradient.getDataHash(data);

            // If this ever become an issue because we need this feature, we just need to deep copy 'data'
            // and use this copy in the genPixels function. But at this moment we consider that it's a bug
            if(newHash != oldHash) throw "gradient data has changed between first generation and realloc";
            #end
            var pixels = hxd.Pixels.alloc(data.resolution,1, ARGB);

            var vec = new Vector();
            for (x in 0...data.resolution) {
                evalData(data, x / data.resolution, vec);
                pixels.setPixelF(x,0, vec);
            }
            return pixels;
        }


        var texture = Texture.fromPixels(genPixels(), RGBA);
        texture.realloc = function() {
            trace("realloc");
            texture.uploadPixels(genPixels());
        }
        cache.set(hash, texture);

        return texture;
    }

    public function toTexture() : h3d.mat.Texture {
        return textureFromData(data);
    }

}