package hrt.prefab.fx;

/**
	Easing functions, mapping [0, 1] to a curve from 0 to 1 (`Back` and
	`Elastic` overshoot). Used as the shape of an emitter param over the
	particle life, see `EmitterParam.ParamShape`.
**/
enum abstract Easing(String) from String to String {
	var Linear;
	var SineIn;
	var SineOut;
	var SineInOut;
	var QuadIn;
	var QuadOut;
	var QuadInOut;
	var CubicIn;
	var CubicOut;
	var CubicInOut;
	var QuartIn;
	var QuartOut;
	var QuartInOut;
	var QuintIn;
	var QuintOut;
	var QuintInOut;
	var ExpoIn;
	var ExpoOut;
	var ExpoInOut;
	var CircIn;
	var CircOut;
	var CircInOut;
	var BackIn;
	var BackOut;
	var BackInOut;
	var ElasticIn;
	var ElasticOut;
	var ElasticInOut;
	var BounceIn;
	var BounceOut;
	var BounceInOut;

	public static var ALL : Array<Easing> = [
		Linear,
		SineIn, SineOut, SineInOut,
		QuadIn, QuadOut, QuadInOut,
		CubicIn, CubicOut, CubicInOut,
		QuartIn, QuartOut, QuartInOut,
		QuintIn, QuintOut, QuintInOut,
		ExpoIn, ExpoOut, ExpoInOut,
		CircIn, CircOut, CircInOut,
		BackIn, BackOut, BackInOut,
		ElasticIn, ElasticOut, ElasticInOut,
		BounceIn, BounceOut, BounceInOut,
	];

	public static function isValid( name : String ) {
		return ALL.indexOf(name) >= 0;
	}

	/** The easing at `t`, clamped to [0, 1]. **/
	public function eval( t : Float ) : Float {
		if( t <= 0 ) t = 0;
		if( t >= 1 ) t = 1;
		inline function pow( v : Float, n : Float ) return Math.pow(v, n);
		inline function inOut( t : Float, n : Int ) return t < 0.5 ? pow(2, n - 1) * pow(t, n) : 1 - pow(-2 * t + 2, n) / 2;
		final PI = Math.PI;
		final c1 = 1.70158;
		final c2 = c1 * 1.525;
		final c3 = c1 + 1;
		final c4 = (2 * PI) / 3;
		final c5 = (2 * PI) / 4.5;
		return switch( (cast this : Easing) ) {
		case Linear: t;
		case SineIn: 1 - Math.cos(t * PI / 2);
		case SineOut: Math.sin(t * PI / 2);
		case SineInOut: -(Math.cos(PI * t) - 1) / 2;
		case QuadIn: t * t;
		case QuadOut: 1 - (1 - t) * (1 - t);
		case QuadInOut: inOut(t, 2);
		case CubicIn: t * t * t;
		case CubicOut: 1 - pow(1 - t, 3);
		case CubicInOut: inOut(t, 3);
		case QuartIn: pow(t, 4);
		case QuartOut: 1 - pow(1 - t, 4);
		case QuartInOut: inOut(t, 4);
		case QuintIn: pow(t, 5);
		case QuintOut: 1 - pow(1 - t, 5);
		case QuintInOut: inOut(t, 5);
		case ExpoIn: t == 0 ? 0 : pow(2, 10 * t - 10);
		case ExpoOut: t == 1 ? 1 : 1 - pow(2, -10 * t);
		case ExpoInOut: t == 0 ? 0 : t == 1 ? 1 : t < 0.5 ? pow(2, 20 * t - 10) / 2 : (2 - pow(2, -20 * t + 10)) / 2;
		case CircIn: 1 - Math.sqrt(1 - t * t);
		case CircOut: Math.sqrt(1 - (t - 1) * (t - 1));
		case CircInOut: t < 0.5 ? (1 - Math.sqrt(1 - 4 * t * t)) / 2 : (Math.sqrt(1 - pow(-2 * t + 2, 2)) + 1) / 2;
		case BackIn: c3 * t * t * t - c1 * t * t;
		case BackOut: 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
		case BackInOut: t < 0.5 ? (pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2 : (pow(2 * t - 2, 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2;
		case ElasticIn: t == 0 ? 0 : t == 1 ? 1 : -pow(2, 10 * t - 10) * Math.sin((t * 10 - 10.75) * c4);
		case ElasticOut: t == 0 ? 0 : t == 1 ? 1 : pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * c4) + 1;
		case ElasticInOut: t == 0 ? 0 : t == 1 ? 1 : t < 0.5
			? -(pow(2, 20 * t - 10) * Math.sin((20 * t - 11.125) * c5)) / 2
			: (pow(2, -20 * t + 10) * Math.sin((20 * t - 11.125) * c5)) / 2 + 1;
		case BounceIn: 1 - bounceOut(1 - t);
		case BounceOut: bounceOut(t);
		case BounceInOut: t < 0.5 ? (1 - bounceOut(1 - 2 * t)) / 2 : (1 + bounceOut(2 * t - 1)) / 2;
		default: t;
		}
	}

	static function bounceOut( t : Float ) : Float {
		final n1 = 7.5625;
		final d1 = 2.75;
		if( t < 1 / d1 )
			return n1 * t * t;
		if( t < 2 / d1 ) {
			t -= 1.5 / d1;
			return n1 * t * t + 0.75;
		}
		if( t < 2.5 / d1 ) {
			t -= 2.25 / d1;
			return n1 * t * t + 0.9375;
		}
		t -= 2.625 / d1;
		return n1 * t * t + 0.984375;
	}
}
