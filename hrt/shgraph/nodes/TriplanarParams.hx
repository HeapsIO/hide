package hrt.shgraph.nodes;

using hxsl.Ast;

enum abstract TriplanarMode(String) from String to String {
	var World;
	var Local;
	var LocalRotation;
}
var modes = [World, Local, LocalRotation];

@name("Triplanar params")
@description("Returns parameters useful to sample a texture using triplanar mapping")
@width(160)
@group("Math")
class TriplanarParams extends ShaderNodeHxsl {
	@prop() var mode : TriplanarMode = "World";

	static var SRC = {
		@sginput(2.0) var sharpness : Float;
		@sginput(1.0) var tiling : Vec3;
		@sginput(0.0) var offset : Vec3;
		@sgconst var MODE : Int = 0;
		@sgoutput var weight : Vec3;
		@sgoutput var uvX : Vec2;
		@sgoutput var uvY : Vec2;
		@sgoutput var uvZ : Vec2;

		@input var input : {
			var normal : Vec3;
		};

		@global var global : { @perObject var modelViewInverse : Mat4;  @perObject var modelView : Mat4;};
		var transformedNormal : Vec3;
		var transformedPosition : Vec3;
		var relativePosition : Vec3;
		function fragment() {
			var normal = MODE == 0 ? transformedNormal : input.normal;
			var position = MODE == 1 ? relativePosition.xyz : transformedPosition.xyz;
			if ( MODE == 2 ) {
				var scaleX = length(vec3(global.modelView[0].x,global.modelView[1].x,global.modelView[2].x));
				var scaleY = length(vec3(global.modelView[0].y,global.modelView[1].y,global.modelView[2].y));
				var scaleZ = length(vec3(global.modelView[0].z,global.modelView[1].z,global.modelView[2].z));
				var scale = vec3(scaleX, scaleY, scaleZ);
				position -= vec3(global.modelView[0].w, global.modelView[1].w, global.modelView[2].w);
				position = position * global.modelViewInverse.mat3x4();
				position *= scale;
			}
			weight = pow(abs(normal), vec3(sharpness));
			weight = weight / (weight.x + weight.y + weight.z);
			var tiledAndOffsetPos = position * tiling + offset;
			uvX = tiledAndOffsetPos.zy;
			uvY = tiledAndOffsetPos.xz;
			uvZ = tiledAndOffsetPos.xy;
		}
	};

	override function getConstValue(name: String) : Null<Int> {
		switch (name) {
			case "MODE":
				switch ( mode ) {
					case "World": return 0;
					case "Local": return 1;
					case "LocalRotation": return 2;
					default: return 0;
				}
			default:
				return 0;
		}
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);

		{
			var element = new hide.Element('<div style="width: ${width * 0.8}px; height: 40px"></div>');
			element.append('<span>Mode</span>');
			element.append(new hide.Element('<select id="mode"></select>'));

			if (this.mode == null) {
				this.mode = modes[0];
			}
			var input = element.children("#mode");
			var indexOption = 0;
			for (i => currentMode in modes) {
				input.append(new hide.Element('<option value="${i}">${currentMode}</option>'));
				if (this.mode == currentMode) {
					input.val(i);
				}
				indexOption++;
			}

			input.on("change", function(e) {
				var value = input.val();
				this.mode = modes[value];
			});

			elements.push(element);
		}

		return elements;
	}
	#end
}