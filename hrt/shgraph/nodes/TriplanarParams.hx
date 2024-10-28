package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Triplanar params")
@description("Returns parameters useful to sample a texture using triplanar mapping")
@width(160)
@group("Math")
class TriplanarParams extends ShaderNodeHxsl {
	@prop() var LOCAL : Bool = false;

	static var SRC = {
		@sginput(2.0) var sharpness : Float;
		@sgconst var LOCAL : Int = 0;
		@sgoutput var weight : Vec3;
		@sgoutput var uvX : Vec2;
		@sgoutput var uvY : Vec2;
		@sgoutput var uvZ : Vec2;

		@input var input : {
			var normal : Vec3;
        };

		var transformedNormal : Vec3;
		var transformedPosition : Vec3;
		var relativePosition : Vec3;
		function fragment() {
			if ( LOCAL == 0 ) {
				weight = pow(abs(transformedNormal), vec3(sharpness));
				weight = weight / (weight.x + weight.y + weight.z);
				uvX = transformedPosition.zy;
				uvY = transformedPosition.xz;
				uvZ = transformedPosition.xy;
			} else {
				weight = pow(abs(input.normal), vec3(sharpness));
				weight = weight / (weight.x + weight.y + weight.z);
				uvX = relativePosition.zy;
				uvY = relativePosition.xz;
				uvZ = relativePosition.xy;
			}
		}
	};

	override function getConstValue(name: String) : Null<Int> {
		switch (name) {
			case "LOCAL":
				return this.LOCAL ? 1 : 0;
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
		var localEl = new hide.Element('<input type="checkbox" id="local"></input>');
		localEl.prop('checked', this.LOCAL);
		localEl.css("float","");
		container.append('<span>LOCAL&nbsp</span>');
		container.append(localEl);
		element.append(container);

		localEl.on("change", function(e) {
			this.LOCAL = localEl.is(':checked');
		});

		elements.push(element);
		element.height(70);
		return elements;
	}
	#end
}