package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Fresnel")
@description("Fresnel input")
@width(180)
@group("Math")
class Fresnel extends ShaderNodeHxsl {
	@prop() var RGB : Bool = true;
	@prop() var ALPHA : Bool = false;
	@prop() var ALPHA_ADD : Bool = false;
	@prop() var REVERSE : Bool = false;

	static var SRC = {
		@sginput var rgba : Vec4;
		@sginput var worldPosition : Vec3;
		@sginput var normals : Vec3;

		@sgconst var RGB : Int = 1;
		@sgconst var ALPHA : Int = 0;
		@sgconst var ALPHA_ADD : Int = 0;
		@sgconst var REVERSE : Int = 0;

		@global var camera : {
			var position : Vec3;
		};

		@sginput var color : Vec3;
		@sginput(0.2) var bias : Float;
		@sginput(1.0) var scale : Float;
		@sginput(1.0) var power : Float;
		@sginput(1.0) var totalAlpha : Float;
		@sgoutput var output : Vec4;

		function fragment() {
			output = rgba;

			var cameraDir = (worldPosition - camera.position).normalize();
			var fresnel = 0.0;

			if(REVERSE == 1)
				fresnel = clamp(bias + scale * (1 - pow(1.0 + dot(cameraDir, normals), power)), 0 , 1);
			else
				fresnel = clamp(bias + scale * pow(1.0 + dot(cameraDir, normals), power), 0 , 1);

			if(RGB == 1)
				output.rgb = mix(rgba.rgb, color, fresnel);
			if(ALPHA == 1)
				output.a *= fresnel * totalAlpha;
			else if (ALPHA_ADD == 1)
				output.a = saturate(rgba.a + fresnel * totalAlpha);
		}
	}

	override function getConstValue(name: String) : Null<Int> {
		switch (name) {
			case "RGB":
				return this.RGB ? 1 : 0;
			case "ALPHA":
				return this.ALPHA ? 1 : 0;
			case "ALPHA_ADD":
				return this.ALPHA_ADD ? 1 : 0;
			case "REVERSE":
				return this.REVERSE ? 1 : 0;
			default:
				return 0;
		}
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: ${width * 0.8}px; height: 40px"></div>');


		var container = new hide.Element('<div style="width: ${width * 0.8}px;"></div>');
		container.css("display","flex");
		var rgbEl = new hide.Element('<input type="checkbox" id="rgb"></input>');
		rgbEl.prop('checked', this.RGB);
		rgbEl.css("float","");
		container.append('<span>RGB&nbsp</span>');
		container.append(rgbEl);
		element.append(container);

		rgbEl.on("change", function(e) {
			this.RGB = rgbEl.is(':checked');
		});

		var container = new hide.Element('<div style="width: ${width * 0.8}px;"></div>');
		container.css("display","flex");
		container.append('<span>ALPHA&nbsp</span>');
		var alphaEl = new hide.Element('<input type="checkbox" id="alpha"></input>');
		alphaEl.prop('checked', this.ALPHA);
		alphaEl.css("float","");
		container.append(alphaEl);
		element.append(container);

		alphaEl.on("change", function(e) {
			this.ALPHA = alphaEl.is(':checked');
		});


		var container = new hide.Element('<div style="width: ${width * 0.8}px;"></div>');
		container.css("display","flex");
		container.append('<span>ALPHA ADD&nbsp</span>');
		var alphaAddEl = new hide.Element('<input type="checkbox" id="alpha-add"></input>');
		alphaAddEl.prop('checked', this.ALPHA_ADD);
		alphaAddEl.css("float","");
		container.append(alphaAddEl);
		element.append(container);

		alphaAddEl.on("change", function(e) {
			this.ALPHA_ADD = alphaAddEl.is(':checked');
		});

		var container = new hide.Element('<div style="width: ${width * 0.8}px;"></div>');
		container.css("display","flex");
		container.append('<span>REVERSE&nbsp</span>');
		var reverseEl = new hide.Element('<input type="checkbox" id="reverse"></input>');
		reverseEl.prop('checked', this.REVERSE);
		reverseEl.css("float","");
		container.append(reverseEl);
		element.append(container);

		reverseEl.on("change", function(e) {
			this.REVERSE = reverseEl.is(':checked');
		});

		elements.push(element);
		element.height(70);
		return elements;
	}
	#end
}