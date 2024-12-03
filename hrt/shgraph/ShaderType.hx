package hrt.shgraph;

enum SType {
	/** Bool **/
	Bool;
	/** Vector of bools of size 2 **/
	VecBool2;
	/** Vector of bools of size 3 **/
	VecBool3;
	/** Vector of bools of size 4 **/
	VecBool4;
	/** Float **/
	Float;
	/** Vector of size 2 **/
	Vec2;
	/** Vector of size 3 **/
	Vec3;
	/** Vector of size 4 **/
	Vec4;
	/** Float or Vectors **/
	Number;
	/** Texture **/
	Sampler;
	/** Any **/
	Variant;
}

class ShaderType {

	static public function getType(type : SType) : hxsl.Ast.Type {
		switch (type) {
			case Vec2:
				return TVec(2, VFloat);
			case Vec3:
				return TVec(3, VFloat);
			case Vec4:
				return TVec(4, VFloat);
			case VecBool2:
				return TVec(2, VBool);
			case VecBool3:
				return TVec(3, VBool);
			case VecBool4:
				return TVec(4, VBool);
			case Bool:
				return TBool;
			case Float:
				return TFloat;
			case Sampler:
				return TSampler(T2D,false);
			default:
		}
		return null;
	}

	static public function getSType(type : hxsl.Ast.Type) : SType {
		switch (type) {
			case TVec(2, VFloat):
				return Vec2;
			case TVec(3, VFloat):
				return Vec3;
			case TVec(4, VFloat):
				return Vec4;
			case TVec(2, VBool):
				return VecBool2;
			case TVec(3, VBool):
				return VecBool3;
			case TVec(4, VBool):
				return VecBool4;
			case TBool:
				return Bool;
			case TFloat:
				return Float;
			case TSampler(_):
				return Sampler;
			default:
		}
		return Variant;
	}

	static public function checkCompatibilities (a : SType, b : SType) : Bool {
		return (checkConversion(a, b) || checkConversion(b, a));
	}

	static public function checkConversion(from : SType, to : SType) {
		switch (to) {
			case Vec2:
				return (from == Float || from == Vec2);
			case Vec3:
				return (from == Float || from == Vec2 || from == Vec3);
			case Vec4:
				return (from == Float || from == Vec2 || from == Vec3 || from == Vec4);
			case Bool:
				return (from == Bool);
			case VecBool2:
				return (from == Bool || from == VecBool2);
			case VecBool3:
				return (from == Bool || from == VecBool3);
			case VecBool4:
				return (from == Bool || from == VecBool4);
			case Float:
				return (from == Float);
			case Number:
				return (from == Float || from == Vec2 || from == Vec3 || from == Vec4);
			case Sampler:
				return (from == Sampler);
			case Variant:
				return true;
			default:
				return false;
		}
	}

}
