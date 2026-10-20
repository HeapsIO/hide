package hrt.shgraph;

using hxsl.Ast;

#if editor
class CustomVarChooser extends hide.comp.Component {
	public var variable : TVar = null;

	public static var validNamePattern = ~/^[_a-zA-Z][_a-zA-Z0-9]*$/;
	public static var reservedKeywords = [
		// Control flow & statements
		"for", "while", "do", "if", "else", "switch", "case", "default", "break", "continue", "return", "discard",
		// Declarations & qualifiers
		"function", "var", "true", "false", "null", "const", "input", "output", "param", "uniform", "varying", "attribute",
		"in", "out", "inout", "centroid", "flat", "smooth", "noperspective", "layout", "precision", "highp", "mediump", "lowp", "struct",
		// Scalar & vector types
		"void", "bool", "bvec2", "bvec3", "bvec4",
		"int", "ivec2", "ivec3", "ivec4",
		"uint", "uvec2", "uvec3", "uvec4",
		"float", "vec2", "vec3", "vec4",
		"double", "dvec2", "dvec3", "dvec4",
		// Matrices
		"mat2", "mat3", "mat4", "mat3x4", "mat2x2", "mat2x3", "mat2x4", "mat3x2", "mat3x3", "mat4x2", "mat4x3", "mat4x4",
		// Textures & samplers
		"sampler2D", "samplerCube", "sampler2DArray", "sampler3D", "channel",
		// Language reserved keywords
		"class", "enum", "typedef", "import", "package", "static", "public", "private", "override", "inline", "dynamic", "new", "this", "super", "try", "catch", "throw", "cast", "untyped", "main"
	];

	public static var availableTypes : Map<String, Type> = [
		"Color" => TVec( 4, VFloat ),
		"Float" => TFloat,
		"Vec2" => TVec( 2, VFloat ),
		"Vec3" => TVec( 3, VFloat ),
		"Int" => TInt,
		"Bool" => TBool,
	];

	public static function isValidVariableName(name: String) : Bool {
		if (name == null || name == "")
			return false;
		if (!validNamePattern.match(name))
			return false;
		if (reservedKeywords.indexOf(name) >= 0)
			return false;
		return true;
	}

	public static function areTypesEqual(a: Type, b: Type) : Bool {
		if (a == null || b == null)
			return a == b;
		return std.Type.enumEq(a, b);
	}

	function makeVariable(name: String, type: Type) : TVar {
		return {
			parent: null,
			id: 0,
			kind: Local,
			name: name,
			type: type,
		};
	}

	public function new(?parent : hide.Element, ?initialName : String, ?initialType : Type, onChange : (TVar) -> Void) {
		var el = new hide.Element('<div class="custom-var">
			<div class="custom-var-row">
				<label for="customName">Name</label><span><input type="text" id="customName"/></span>
			</div>
			<div class="custom-var-row">
				<label for="customType">Type</label><span><select id="customType"></select></span>
			</div>
		</div>');
		super(parent, el);

		var textInput = element.find("#customName");
		var select = element.find("#customType");

		var selectedKey: String = null;
		for( key => value in availableTypes ) {
			select.append(new hide.Element('<option value="${key}">${key}</option>'));
			if( initialType != null && areTypesEqual(value, initialType) ) {
				selectedKey = key;
			}
		}

		if( selectedKey != null ) {
			select.val(selectedKey);
		}

		if( initialName != null ) {
			textInput.val(initialName);
		}

		var currentType = initialType ?? availableTypes[select.val()];
		if( initialName != null && initialName != "" && currentType != null && isValidVariableName(initialName) ) {
			variable = makeVariable(initialName, currentType);
		}

		function changedFun(_) {
			var name = textInput.val();
			var typeKey = select.val();
			var resolvedType = typeKey != null ? availableTypes[typeKey] : null;

			if( !isValidVariableName(name) || resolvedType == null ) {
				variable = null;
				textInput.addClass("error");
				textInput.attr("title", 'Invalid variable name (must start with _ or a letter, contain only alphanumeric characters, and cannot be a reserved keyword)');
				onChange(null);
				return;
			}

			textInput.removeClass("error");
			textInput.removeAttr("title");
			variable = makeVariable(name, resolvedType);
			onChange(variable);
		}

		select.on("change", changedFun);
		textInput.on("input change", changedFun);
	}

	public function show() {
		element.show();
	}

	public function hide() {
		element.hide();
	}
}
#end
