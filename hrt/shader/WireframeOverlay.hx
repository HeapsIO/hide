package hrt.shader;

class WireframeOverlayShader extends hxsl.Shader {
	static var SRC = {

		@param var color : Vec3;
		@param var alpha : Float;
		@param var thickness : Float;

		@input var input : {
			var normal : Vec3;
		};

		var relativePosition : Vec3;
		var pixelColor : Vec4;

		function vertex() {
			relativePosition += thickness * input.normal;
		}

		function fragment() {
			pixelColor = vec4(color, alpha);
		}
	}
}

class WireframeOverlay extends hrt.prefab.Shader {

	@:s public var color : Int = 0xFFFFFF;
	@:s public var alpha : Float = 0.5;
	@:s public var thickness : Float = 0.01;

	public function new(parent, shared) {
		super(parent, shared);

		shader = new WireframeOverlayShader();
	}

	override function makeInstance() {
		updateInstance();
	}

	function getMaterials() {
		if( Std.isOfType(parent, hrt.prefab.Material) ) {
			var material : hrt.prefab.Material = cast parent;
			return material.getMaterials();
		}
		else {
			return findFirstLocal3d().getMaterials();
		}
	}

	override function updateInstance(?propName : String ) {

		var wireframeShader = Std.downcast(shader, WireframeOverlayShader);
		if( wireframeShader != null ){
			wireframeShader.color.load(h3d.Vector.fromColor(color));
			wireframeShader.alpha = alpha;
			wireframeShader.thickness = thickness;
		}

		for( m in getMaterials() ) {
			var existingPass = m.getPass("wireframeOverlay");
			if( existingPass != null ) {
				m.removePass(existingPass);
			}
			var p = m.allocPass("wireframeOverlay");
			p.setBlendMode(Alpha);
			p.wireframe = true;
			p.addShader(shader);
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<p style="color: red;"> Use new editor </p>
		'), this);
	}
	#end


	override function edit2( ctx: hrt.prefab.EditContext2 ) {
		ctx.build(
			<root>
				<color field={color}/>
				<range(0.0,1.0) field={alpha}/>
				<range(0.0,0.1) step="0.0001" field={thickness}/>
			</root>
		);
	}

	static var _ = hrt.prefab.Prefab.register("wireframeOverlay", WireframeOverlay);
}