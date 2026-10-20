package hrt.prefab.fx;

typedef ParamDef = {
	> hrt.prefab.Props.PropDef,
	?animate: Bool,
	?instance: Bool,
	?groupName: String
}

class EmitterHelper {

	/** `m.rotate(0, 0, angle)`: the same matrix (the terms `rotate` adds are zeros), without its 4 other sin/cos and the full multiply **/
	public static inline function rotateZ( m : h3d.Matrix, angle : Float ) {
		var c = Math.cos(angle);
		var s = Math.sin(angle);
		var a = m._11, b = m._12;
		m._11 = a * c - b * s; m._12 = a * s + b * c;
		a = m._21; b = m._22;
		m._21 = a * c - b * s; m._22 = a * s + b * c;
		a = m._31; b = m._32;
		m._31 = a * c - b * s; m._32 = a * s + b * c;
		a = m._41; b = m._42;
		m._41 = a * c - b * s; m._42 = a * s + b * c;
	}
}
