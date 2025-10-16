package hrt.ui;

class HuiBackgroundShader extends hxsl.Shader {
	static var SRC = {

		var calculatedUV : Vec2;
		var pixelColor : Vec4;
		@param var size: Vec2;

		function fragment() {
			// Todo : expose this as parameters
			var borderColor = vec4(vec3(0.7),1.0);
			var boxBackground = vec4(vec3(0.2),1.0);
			var shadowColor = vec4(0.0,0.0,0.0,0.5);
			var borderWidth = 1;
			var boxCorners = vec4(5);
			var shadowOffset = -vec2(2,2);


			var localPos = calculatedUV * size;
			pixelColor = vec4(0,0,0,1);

			var p = localPos - size/2.0;
			// p.x = p.x > 0.0 ? floor(p.x) : ceil(p.x) - 0;
			// p.y = p.y > 0.0 ? floor(p.y) : ceil(p.y);

			var halfSize = size/2.0;

			var halfBorderWidth = (borderWidth-1) / 2.0;
			var remaining = fract(halfBorderWidth)+0.5;

			var boxSize = (size)/2.0 - vec2(5) - remaining;
			var d = sdRoundedBox(p, boxSize , boxCorners);

			var shadow = sdRoundedBox(p + shadowOffset, boxSize , boxCorners);

			var color = mix(vec4(0.0,0.0,0.0,0.0), boxBackground, d < 0 ? 1.0 : 0.0);
			var borderAlpha = saturate(1+halfBorderWidth-abs(d));
			var boxColor = mix(color, borderColor, pow(borderAlpha, 0.33) /** Boost anti-aliasing contrast **/);

			shadow = saturate(-(shadow - 1 - halfBorderWidth) / 2.0);
			var shadowOut = mix(vec4(0), shadowColor, shadow);

			boxColor = mix(shadowOut, boxColor, boxColor.a);
			pixelColor = boxColor;
		}

		function sdRoundedBox( p: Vec2, b: Vec2, r: Vec4) : Float {
			r.xy = (p.x > 0.0) ? r.xy : r.zw;
			r.x = (p.y > 0.0) ? r.x : r.y;
			var q = abs(p) - b + r.x;
			return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
		}
	}
}

class HuiBackground extends h2d.ScaleGrid implements h2d.domkit.Object {
	var shader : HuiBackgroundShader;

	public function new(?parent: h2d.Object) {
		super(h2d.Tile.fromColor(0), 0, 0, 0, 0, parent);
		shader = new HuiBackgroundShader();
		blendMode = Alpha;
		initComponent();
		addShader(shader);
	}

	override function sync(ctx:h2d.RenderContext) {
		super.sync(ctx);

		trace(matA, matB, matC, matD, absX, absY);
		shader.size.set(width, height);
	}
}