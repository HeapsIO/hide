package hrt.shgraph;

using hxsl.Ast;

@noheader()
@width(120)
@color("#d6d6d6")
class ShaderParam extends ShaderNode {

	@output() var output = SType.Variant;

	@prop() public var parameterId : Int;

	public var variable : TVar;

	override public function computeOutputs() {
		if (variable != null)
			addOutput("output", variable.type);
		else
			removeOutput("output");
	}

	override public function getOutput(key : String) : TVar {
		return variable;
	}

	override public function loadProperties(props : Dynamic) {
		parameterId = Reflect.field(props, "parameterId");
	}

	override public function saveProperties() : Dynamic {
		var parameters = {
			parameterId: parameterId
		};

		return parameters;
	}

	override public function build(key : String) : TExpr {
		return null;
	}

	#if editor
	private var parameterName : String;
	private var eltName : hide.Element;

	private var parameterDisplay : String;
	private var displayDiv : hide.Element;
	public var parameterIndex : Int;
	public function setName(s : String) {
		parameterName = s;
		if (eltName != null)
			eltName.html(s);
	}
	public function setDisplayValue(value : String) {
		parameterDisplay = value;
		switch (this.variable.type) {
			case TFloat:
				if (displayDiv != null)
					displayDiv.html(value);
			case TSampler2D:
				if (displayDiv != null)
					displayDiv.css("background-image", 'url(${value})');
			case TVec(4, VFloat):
				if (displayDiv != null)
					displayDiv.css("background-color", value);
			default:
		}
	}
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var height = 25;
		switch (this.variable.type) {
			case TFloat:
				displayDiv = new hide.Element('<div class="float-preview" ></div>');
				height += 20;
			case TSampler2D:
				displayDiv = new hide.Element('<div class="texture-preview" ></div>');
				height += 50;
			case TVec(4, VFloat):
				displayDiv = new hide.Element('<div class="color-preview" ></div>');
				height += 25;
			default:
				displayDiv = null;
		}
		var element = new hide.Element('<div style="width: 110px; height: ${height}px"></div>');
		if (displayDiv != null) {
			setDisplayValue(parameterDisplay);
			displayDiv.appendTo(element);
		}
		eltName = new hide.Element('<div class="paramVisible" >${parameterName}</div>').appendTo(element);

		elements.push(element);

		return elements;
	}
	#end

}