package hrt.shgraph;

import hxsl.Ast.Type;

enum SType {
	/** Bool **/
	Bool;
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

	static public function getType(type : hxsl.Type) : SType {
		switch (type) {
			case TVec(2, VFloat):
				return Vec2;
			case TVec(3, VFloat):
				return Vec3;
			case TVec(4, VFloat):
				return Vec4;
			case TBool:
				return Bool;
			case TFloat:
				return Float;
			case TSampler2D:
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