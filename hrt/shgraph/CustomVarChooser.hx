package hrt.shgraph;

using hxsl.Ast;

#if editor
class CustomVarChooser extends hide.comp.Component {
	public var variable : TVar = null;

	public static var validNamePattern = ~/^[_a-zA-Z][_a-zA-Z0-9]*$/;
	public static var reservedKeywords = [
		"for", "while", "do", "if", "else", "switch", "case", "default", "break", "continue", "return", "discard",
		"function", "var", "true", "false", "null", "const", "input", "output", "param",
		"void", "bool", "int", "float", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "mat3x4",
		"sampler2D", "samplerCube", "sampler2DArray", "channel"
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
		var availableTypes = [
			"Color" => TVec( 4, VFloat ),
			"Int" => TInt,
			"Bool" => TBool,
			"Float" => TFloat,
			"String" => TString,
			"Vec2" => TVec( 2, VFloat ),
			"Vec3" => TVec( 3, VFloat ),
		];
		for( key => value in availableTypes ) {
			select.append(new hide.Element('<option value="${key}">${key}</option>'));
			if( value == initialType )
				select.val(key);
		}
		if( initialName != null ) {
			textInput.val(initialName);
		}
		if( initialName != null && initialName != "" && initialType != null && isValidVariableName(initialName) ) {
			variable = {
				parent: null,
				id: 0,
				kind: Local,
				name: initialName,
				type: availableTypes[select.val()],
			};
		}
		function changedFun(_) {
			var name = textInput.val();
			if( !isValidVariableName(name) ) {
				textInput.addClass("error");
				textInput.attr("title", 'Invalid variable name (must start with _ or a letter, contain only alphanumeric characters, and cannot be a reserved keyword)');
				return;
			}
			textInput.removeClass("error");
			textInput.removeAttr("title");
			variable = {
				parent: null,
				id: 0,
				kind: Local,
				name: name,
				type: availableTypes[select.val()],
			};
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
