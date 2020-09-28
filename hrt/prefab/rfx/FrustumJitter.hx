package hrt.prefab.rfx;

@:enum abstract Pattern(String) {
	var Still = "Still";
	var Uniform2 = "Uniform2";
	var Uniform4 = "Uniform4";
	var Uniform4_Helix = "Uniform4_Helix";
	var Uniform4_DoubleHelix = "Uniform4_DoubleHelix";
	var SkewButterfly = "SkewButterfly";
	var Rotated4 = "Rotated4";
	var Rotated4_Helix = "Rotated4_Helix";
	var Rotated4_Helix2 = "Rotated4_Helix2";
	var Poisson10 = "Poisson10";
	var Pentagram = "Pentagram";
	var Halton_2_3_x8 = "Halton_2_3_x8";
	var Halton_2_3_x16 = "Halton_2_3_x16";
	var Halton_2_3_x32 = "Halton_2_3_x32";
	var Halton_2_3_x256 = "Halton_2_3_x256";
	var MotionPerp2 = "MotionPerp2";
	var MotionVPerp2 = "MotionVPerp2";
}

class FrustumJitter {
	
	public var points_Still : Array<Float> = [
		0.0, 0.0,
	];

   	public var points_Uniform2 : Array<Float> = [
		-0.2, -0.2,//ll
		0.2,  0.2,//ur
	];

	public var points_Uniform4 : Array<Float> = [
		-0.2, -0.2,//ll
		0.2, -0.2,//lr
		0.2,  0.2,//ur
		-0.2,  0.2,//ul
	];

	public var points_Uniform4_Helix : Array<Float> = [
		-0.2, -0.2,//ll  3  1
		0.2,  0.2,//ur   \/|
		0.2, -0.2,//lr   /\|
		-0.2,  0.2,//ul  0  2
	];

	public var points_Uniform4_DoubleHelix : Array<Float> = [
		-0.2, -0.2,//ll  3  1
		0.2,  0.2,//ur   \/|
		0.2, -0.2,//lr   /\|
		-0.2,  0.2,//ul  0  2
		-0.2, -0.2,//ll  6--7
		0.2, -0.2,//lr   \
		-0.2,  0.2,//ul    \
		0.2,  0.2,//ur  4--5
	];

	public var points_SkewButterfly : Array<Float> = [
		-0.250, -0.250,
		0.250,  0.250,
		0.12, -0.12,
		-0.12,  0.12,
	];

	public var points_Rotated4 : Array<Float> = [
		-0.12, -0.37,//ll
		0.37, -0.12,//lr
		0.12,  0.37,//ur
		-0.37,  0.12,//ul
	];

	public var points_Rotated4_Helix : Array<Float> = [
		-0.12, -0.37,//ll  3  1
		0.12,  0.37,//ur   \/|
		0.37, -0.12,//lr   /\|
		-0.37,  0.12,//ul  0  2
	];

	public var points_Rotated4_Helix2 : Array<Float> = [
		-0.12, -0.37,//ll  2--1
		0.12,  0.37,//ur   \/
		-0.37,  0.12,//ul   /\
		0.37, -0.12,//lr  0  3
	];

	public var points_Poisson10 : Array<Float> = [
		-0.16795960*0.2,  0.65544910*0.2,
		-0.69096030*0.2,  0.59015970*0.2,
		0.49843820*0.2,  0.83099720*0.2,
		0.17230150*0.2, -0.03882703*0.2,
		-0.60772670*0.2, -0.06013587*0.2,
		0.65606390*0.2,  0.24007600*0.2,
		0.80348370*0.2, -0.48096900*0.2,
		0.33436540*0.2, -0.73007030*0.2,
		-0.47839520*0.2, -0.56005300*0.2,
		-0.12388120*0.2, -0.96633990*0.2,
	];

	public var points_Pentagram : Array<Float> = [
		0.000000*0.,  0.525731*0.,// head
		-0.309017*0., -0.42532*0.,// lleg
		0.500000*0.,  0.162460*0.,// rarm
		-0.500000*0.,  0.162460*0.,// larm
		0.309017*0., -0.42532*0.,// rleg
	];

	public var points_Halton_2_3_x8 : Array<Float> = [];
	public var points_Halton_2_3_x16 : Array<Float> = [];
	public var points_Halton_2_3_x32 : Array<Float> = [];
	public var points_Halton_2_3_x256 : Array<Float> = [];
	public var points_MotionPerp2 : Array<Float> = [
		0.00, -0.2,
		0.00,  0.2,
	];

	public var points_MotionVPerp2 : Array<Float> = [
		-0.20, -0.0,
		0.20,  0.0,
	];


	
    private inline function getSeq( pattern : Pattern ) : Array<Float> {
       return switch (pattern) {
			case Still: points_Still;
			case Uniform2 : points_Uniform2;
			case Uniform4 : points_Uniform4;
			case Uniform4_Helix : points_Uniform4_Helix;
			case Uniform4_DoubleHelix : points_Uniform4_DoubleHelix;
			case SkewButterfly : points_SkewButterfly;
			case Rotated4 : points_Rotated4;
			case Rotated4_Helix : points_Rotated4_Helix;
			case Rotated4_Helix2 : points_Rotated4_Helix2;
			case Poisson10 : points_Poisson10;
			case Pentagram : points_Pentagram;
			case Halton_2_3_x8 : points_Halton_2_3_x8;
			case Halton_2_3_x16 : points_Halton_2_3_x16;
			case Halton_2_3_x32 : points_Halton_2_3_x32;
			case Halton_2_3_x256 : points_Halton_2_3_x256;
			case MotionPerp2 : points_MotionPerp2;
			case MotionVPerp2 : points_MotionVPerp2;
			default : null;
		}
    }

	public var patternScale = 1.0;
	public var activeIndex = 0;
	public var curSample = new h2d.col.Point(0,0);
	public var prevSample = new h2d.col.Point(0,0);
	public var curPattern : Pattern = Still;

	public function new() {
		
		// points_Pentagram
		var vh = new h3d.Vector(points_Pentagram[0] - points_Pentagram[2], points_Pentagram[1] - points_Pentagram[3]);
		var vu = new h3d.Vector(0.0, 1.0);
		transformPattern(points_Pentagram, hxd.Math.degToRad(0.5 * hxd.Math.atan2(vh.y - vu.y, vh.x - vu.x)), 1.0);

		// points_Halton_2_3_xN
		points_Halton_2_3_x8.resize(8);
		initializeHalton_2_3(points_Halton_2_3_x8);
		points_Halton_2_3_x16.resize(16);
		initializeHalton_2_3(points_Halton_2_3_x16);
		points_Halton_2_3_x32.resize(32);
		initializeHalton_2_3(points_Halton_2_3_x32);
		points_Halton_2_3_x256.resize(256);
		initializeHalton_2_3(points_Halton_2_3_x256);
	}

	public function update() {

		var seq = getSeq(curPattern);
		if( seq == null )
			return;

		activeIndex += 1;
		activeIndex %= seq.length;

		var newSample = sample(seq, activeIndex);
		prevSample.load(curSample);
		curSample.load(newSample);
	}

	private function sample( pattern : Array<Float>, index : Int ) : h2d.col.Point
    {
        var n = Std.int(pattern.length / 2.0);
        var i = index % n;

        var x = patternScale * pattern[2 * i + 0];
		var y = patternScale * pattern[2 * i + 1];
		
		return new h2d.col.Point(x, y);

        /*if (pattern != Pattern.MotionPerp2)
            return new Vector2(x, y);
        else
            return new Vector2(x, y).Rotate(Vector2.right.SignedAngle(focalMotionDir));*/
    }

	private function transformPattern( seq : Array<Float>, theta : Float, scale : Float) {
        var cs = hxd.Math.cos(theta);
		var sn = hxd.Math.sin(theta);
		var i = 0;
		var j = 1;
		while( i != seq.length ) {
			var x = scale * seq[i];
            var y = scale * seq[j];
            seq[i] = x * cs - y * sn;
            seq[j] = x * sn + y * cs;
			i += 2;
			j += 2;
		}
    }

	// http://en.wikipedia.org/wiki/Halton_sequence
	private function haltonSeq(prime : Int, index : Int = 1/* NOT! zero-based */) : Float {
		var r = 0.0;
		var f = 1.0;
		var i = index;
		while( i > 0 ) {
			f /= prime;
			r += f * (i % prime);
			i = hxd.Math.floor(i / prime);
		}
		return r;
	}

	private function initializeHalton_2_3( seq : Array<Float> ) {
		var sampleCount = Std.int(seq.length / 2.0);
		for( i in 0 ... sampleCount ) {
			var u = haltonSeq(2, i + 1) - 0.5;
			var v = haltonSeq(3, i + 1) - 0.5;
			seq[2 * i + 0] = u;
			seq[2 * i + 1] = v;
		}
	}
}