package hrt.tools;

class GridShader extends hxsl.Shader {
	static var SRC = {
		@global var camera : {
			var position : Vec3;
		}

		@param var color : Vec3;
		@param var lineWidth : Float;
		@param var lineSpacing : Float;

		var transformedPosition : Vec3;
		var pixelColor : Vec4;

		// https://bgolus.medium.com/the-best-darn-grid-shader-yet-727f9278b9d8
		function pristineGrid(position : Vec2, lineWidth: Vec2, idx : Int) : Float {
			var f = length(abs(camera.position - transformedPosition)) / pow(100, float(idx));
			lineWidth = min(lineWidth, saturate(lineWidth * f));
            var posDDXY = vec4(dFdx(position), dFdy(position));
            var posDeriv = vec2(length(posDDXY.xz), length(posDDXY.yw));
            var invertLine = length(lineWidth) > 0.5;
            var targetWidth = invertLine ? 1.0 - lineWidth : lineWidth;
            var drawWidth = clamp(targetWidth, posDeriv, vec2(0.5, 0.5));
            var lineAA = max(posDeriv, 0.000001) * 1.5;
            var gridUV = abs(vec2(position.x % 1, position.y % 1) * 2.0 - 1.0);
            gridUV = invertLine ? gridUV : 1.0 - gridUV;
            var grid2 = smoothstep(drawWidth + lineAA, drawWidth - lineAA, gridUV);
            grid2 *= saturate(targetWidth / drawWidth);
            grid2 = mix(grid2, targetWidth, saturate(posDeriv * 2.0 - 1.0));
            grid2 = invertLine ? 1.0 - grid2 : grid2;
            return mix(grid2.x, 1.0, grid2.y);
		}

		function fragment() {
			pixelColor.rgb = color;
			pixelColor.a = 0;
			for (idx in 0...3) {
				var f = pow(10., float(idx));
				pixelColor.a = max(pixelColor.a, pristineGrid(
					transformedPosition.xy * (1 / (lineSpacing * f)),
					vec2(lineWidth * f, lineWidth * f) * (1 / (lineSpacing * f)),
					idx));
			}

		}
	}
}

class Grid extends h3d.scene.Object {
	public var color(default, set) : Int = 0x4C4C4C;
	public var lineWidth(default, set) : Float = 0.01;
	public var lineSpacing(default, set) : Float = 1;

	var plane : h3d.scene.Mesh = null;
	var shader : GridShader;

	var cam : h3d.Camera;
	var prevDistance : Float;

	public function new(?parent : h3d.scene.Object) {
		super(parent);

		var prim = createPlanePrimitive(1);
		plane = new h3d.scene.Mesh(prim, null, this);

		shader = new GridShader();
		plane.material.mainPass.addShader(shader);

		plane.material.mainPass.setBlendMode(Alpha);
		plane.material.mainPass.culling = None;
		plane.material.mainPass.setPassName("overlay");

		cam = parent.getScene().camera;
		refresh();
	}

	override function sync(ctx : h3d.scene.RenderContext) {
		super.sync(ctx);
		refresh();
	}

	public function set_color(v) {
		color = v;
		refresh();
		return color;
	}

	public function set_lineWidth(v) {
		lineWidth = v;
		refresh();
		return lineWidth;
	}

	public function set_lineSpacing(v) {
		lineSpacing = v;
		refresh();
		return lineSpacing;
	}

	function refresh() {
		shader.color = h3d.Vector.fromColor(color);
		shader.lineWidth = lineWidth;
		shader.lineSpacing = lineSpacing;

		var d = hxd.Math.abs(cam.pos.length());
		if (d == prevDistance)
			return;
		prevDistance = d;
		plane.setScale(d * 10);
	}

	function createPlanePrimitive(subdivision : Int) : h3d.prim.Primitive {
		var size = subdivision + 1;
		var cellCount = size;
		cellCount *= cellCount;

		var points = [];
		for( y in 0 ... size + 1 ) {
			for( x in 0 ... size + 1 ) {
				points.push(new h3d.col.Point(hxd.Math.lerp(-0.5, 0.5, x / size), hxd.Math.lerp(-0.5, 0.5, y / size)));
			}
		}

		var indices = [];
		for( y in 0 ... size ) {
			for( x in 0 ... size ) {
				var i = x + y * (size + 1);
				if( i % 2 == 0 ) {
					indices.push(i);
					indices.push(i + 1);
					indices.push(i + size + 2);
					indices.push(i);
					indices.push(i + size + 2);
					indices.push(i + size + 1);
				}
				else {
					indices.push(i + size + 1);
					indices.push(i);
					indices.push(i + 1);
					indices.push(i + 1);
					indices.push(i + size + 2);
					indices.push(i + size + 1);
				}
			}
		}

		var uvs = [for(v in points) new h3d.col.Point(v.x + 0.5, v.y + 0.5)];
		var verts = [for(p in points) new h3d.col.Point(p.x, p.y, 0.)];
		var idx = new hxd.IndexBuffer();
		for(i in indices)
			idx.push(i);
		var primitive = new h3d.prim.Polygon(verts, idx);
		primitive.normals = [for(p in points) new h3d.col.Point(0, 0, 1.)];
		primitive.tangents = [for(p in points) new h3d.col.Point(0., 1., 0.)];
		primitive.uvs = [for(uv in uvs) new h3d.prim.UV(uv.x, uv.y)];
		primitive.colors = [for(p in points) new h3d.col.Point(1,1,1)];
		return primitive;
	}
}