package hrt.prefab.pbr;

import hrt.shader.AnisotropicForward;

enum abstract AnisotropyMode(String) {
	var Flat;
	var Texture;
	var Vertex;
	var Frequency;
}

@:prefabIcon(HuiRes.ui.icons.prefab.anisotropy)
class Anisotropy extends Prefab {

	@:s public var mode : AnisotropyMode = Flat;

	@:s public var intensity : Float = 0.0;
	@:s public var direction : Float = 0.0;

	@:s public var noiseFrequency : Float = 0.0;
	@:s public var noiseIntensity : Float = 1.0;

	@:s public var intensityFactor = 1.0;
	@:s public var noiseIntensityPath : String = null;
	@:s public var noiseDirectionPath : String = null;
	@:s public var rotationOffset : Float = 0.0;

	public function new(parent, shared: ContextShared) {
		super(parent,shared);
	}

	function getMaterials() {
		if( Std.isOfType(parent, Material) ) {
			var material : Material = cast parent;
			return material.getMaterials();
		}
		else {
			return findFirstLocal3d().getMaterials();
		}
	}

	override function makeInstance():Void {
		refreshShaders();
		updateInstance();
	}

	function refreshShaders() {
		var fv = new FlatValue();
		var nt = new NoiseTexture();
		var ff = new FrequencyValue();
		var vv = new VertexValue();

		var as = new AnisotropicForward();

		var noiseIntensityTexture = noiseIntensityPath != null ? shared.loadTexture(noiseIntensityPath) : null;
		var noiseDirectionTexture = noiseDirectionPath != null ? shared.loadTexture(noiseDirectionPath) : null;

		var mat = getMaterials();

		for( m in mat ) {
			m.mainPass.removeShader(m.mainPass.getShader(NoiseTexture));
			m.mainPass.removeShader(m.mainPass.getShader(FlatValue));
			m.mainPass.removeShader(m.mainPass.getShader(FrequencyValue));
			m.mainPass.removeShader(m.mainPass.getShader(VertexValue));

			m.mainPass.removeShader(m.mainPass.getShader(AnisotropicForward));
		}

		for( m in mat ) {

			if( m.mainPass.name != "forward" )
				continue;

			if( mode == Texture && noiseIntensityTexture != null && noiseDirectionTexture != null ) {
				m.mainPass.addShader(nt);
			}
			else {
				switch mode {
					case Texture,Flat: m.mainPass.addShader(fv);
					case Vertex : m.mainPass.addShader(vv);
					case Frequency:	m.mainPass.addShader(ff);
					default:
				}
			}

			m.mainPass.addShader(as);
		}
	}

	override function updateInstance(?propName : String ) {
		for( m in getMaterials() ) {

			var fv = m.mainPass.getShader(FlatValue);
			if( fv != null ) {
				fv.intensity = intensity;
				var angle = hxd.Math.degToRad(direction);
				fv.dirVector.set(hxd.Math.cos(angle), hxd.Math.sin(angle), 0);
			}

			var ff = m.mainPass.getShader(FrequencyValue);
			if( ff != null ) {
				ff.intensity = intensity;
				ff.noiseFrequency = noiseFrequency;
				ff.noiseIntensity = noiseIntensity;
				var angle = hxd.Math.degToRad(direction);
				ff.dirVector.set(hxd.Math.cos(angle), hxd.Math.sin(angle), 0);
			}

			var nt = m.mainPass.getShader(NoiseTexture);
			if( nt != null ) {
				nt.noiseIntensityTexture = noiseIntensityPath != null ? shared.loadTexture(noiseIntensityPath) : null;
				nt.noiseDirectionTexture = noiseDirectionPath != null ? shared.loadTexture(noiseDirectionPath) : null;
				nt.intensityFactor = intensityFactor;
				nt.rotationOffset = hxd.Math.degToRad(rotationOffset);
			}

			var vv = m.mainPass.getShader(VertexValue);
			if( vv != null ) {
				vv.intensity = intensity;
			}
		}
	}

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		super.edit2(ctx);

		function rebuild( isTemp : Bool){
			ctx.rebuildInspector();
			refreshShaders();
		}

		ctx.build(
			<root>
				<category("Anisotropy")>
					<select field={mode} onValueChange={rebuild}/>
					<range(0, 1) field={intensity} if(mode == Flat || mode == Frequency || mode == Vertex)/>
					<range(0, 360) field={direction} if(mode == Flat || mode == Frequency)/>
					<range(0, 1) label="Factor" field={intensityFactor} if(mode == Texture)/>
					<range(0, 360) field={rotationOffset} if(mode == Texture)/>
					<file label="Intensity" field={noiseIntensityPath} type="texture" if(mode == Texture)/>
					<file label="Direction" field={noiseDirectionPath} type="texture" if(mode == Texture)/>
					<range(0, 1) field={noiseIntensity} if(mode == Frequency)/>
					<range(0, 100) field={noiseFrequency} if(mode == Frequency)/>
				</category>
			</root>
		);
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		return { 	icon : "cube",
					name : "Anisotropy",
					allowParent : function(p) return p.to(Material) != null  };
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<p style="color: red;"> Use new editor </p>
		'), this);
	}
	#end

	static var _ = Prefab.register("anisotropy", Anisotropy);
}