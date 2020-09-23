package hrt.prefab.terrain;

class Surface {
	public var albedo : h3d.mat.Texture;
	public var normal : h3d.mat.Texture;
	public var pbr : h3d.mat.Texture;
	public var tilling = 1.0;
	public var offset : h3d.Vector;
	public var angle = 0.0;
	public var minHeight = 0.0;
	public var maxHeight = 1.0;

	public function new( ?albedo : h3d.mat.Texture, ?normal : h3d.mat.Texture, ?pbr : h3d.mat.Texture ) {
		this.albedo = albedo;
		this.normal = normal;
		this.pbr = pbr;
		this.offset = new h3d.Vector(0);
	}

	public function clone() : Surface {
		var o = new Surface(albedo, normal, pbr);
		o.tilling = tilling;
		o.offset.load(offset);
		o.angle = angle;
		o.minHeight = minHeight;
		o.maxHeight = maxHeight;
		return o;
	}

	public function dispose() {
	}
}

class SurfaceArray {
	public var albedo : h3d.mat.TextureArray;
	public var normal : h3d.mat.TextureArray;
	public var pbr : h3d.mat.TextureArray;
	public var surfaceCount : Int;
	public var params : Array<h3d.Vector> = [];
	public var secondParams : Array<h3d.Vector> = [];

	public function new( count, res ) {
		surfaceCount = count;
		if( count > 0 && res > 0 ) {
			albedo = new h3d.mat.TextureArray(res, res, count, [Target], RGBA);
			normal = new h3d.mat.TextureArray(res, res, count, [Target], RGBA);
			pbr = new h3d.mat.TextureArray(res, res, count, [Target], RGBA);
			albedo.wrap = Repeat;
			albedo.preventAutoDispose();
			normal.wrap = Repeat;
			normal.preventAutoDispose();
			pbr.wrap = Repeat;
			pbr.preventAutoDispose();
		}
	}

	public function clone() : SurfaceArray {
		var o = new SurfaceArray(albedo.layerCount, albedo.width);
		return o;
	}

	public function dispose() {
		if( albedo != null ) albedo.dispose();
		if( normal != null ) normal.dispose();
		if( pbr != null ) pbr.dispose();
	}
}
