package hrt.prefab.pbr;

import hrt.shader.AnisotropicForward;

enum abstract AnisotropyMode(String) {
	var Flat;
	var NoiseTexture;
	var Vertex;
	var Frequency;
	var FlowMap;
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

	@:s public var flowMapPath : String = null;

	@:s public var debugDirection : Bool = false;

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
		var nt = new NoiseTextureValue();
		var ff = new FrequencyValue();
		var vv = new VertexValue();
		var fm = new FlowmapValue();

		var as = new AnisotropicForward();
		var dd = new DebugDir();

		var noiseIntensityTexture = noiseIntensityPath != null ? shared.loadTexture(noiseIntensityPath) : null;
		var noiseDirectionTexture = noiseDirectionPath != null ? shared.loadTexture(noiseDirectionPath) : null;

		var mat = getMaterials();

		for( m in mat ) {
			m.mainPass.removeShader(m.mainPass.getShader(NoiseTextureValue));
			m.mainPass.removeShader(m.mainPass.getShader(FlatValue));
			m.mainPass.removeShader(m.mainPass.getShader(FrequencyValue));
			m.mainPass.removeShader(m.mainPass.getShader(VertexValue));
			m.mainPass.removeShader(m.mainPass.getShader(FlowmapValue));

			m.mainPass.removeShader(m.mainPass.getShader(AnisotropicForward));
			m.mainPass.removeShader(m.mainPass.getShader(DebugDir));
		}

		for( m in mat ) {

			if( m.mainPass.name != "forward" )
				continue;

			if( mode == NoiseTexture && noiseIntensityTexture != null && noiseDirectionTexture != null ) {
				m.mainPass.addShader(nt);
			}
			else {
				switch mode {
					case NoiseTexture,Flat: m.mainPass.addShader(fv);
					case Vertex : m.mainPass.addShader(vv);
					case Frequency:	m.mainPass.addShader(ff);
					case FlowMap: m.mainPass.addShader(fm);
					default:
				}
			}

			if( debugDirection )
				m.mainPass.addShader(dd);
			else 
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

			var nt = m.mainPass.getShader(NoiseTextureValue);
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

			var fm = m.mainPass.getShader(FlowmapValue);
			if( fm != null ) {
				fm.intensity = intensity;
				fm.rotation = hxd.Math.degToRad(rotationOffset);
				fm.flowmap = flowMapPath != null ? shared.loadTexture(flowMapPath) : null;
			}

			var as = m.mainPass.getShader(AnisotropicForward);
			if(as != null){
				if(fm != null){
					as.localDirection = false;
				} else {
					as.localDirection = true;
				}
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
					<file label="Flowmap" field={flowMapPath} type="texture" if(mode == FlowMap)/>
					<range(0, 1) field={intensity} if(mode == Flat || mode == Frequency || mode == Vertex || mode == FlowMap)/>
					<range(0, 360) field={direction} if(mode == Flat || mode == Frequency)/>
					<range(0, 1) label="Factor" field={intensityFactor} if(mode == NoiseTexture)/>
					<range(0, 360) field={rotationOffset} if(mode == NoiseTexture || mode == FlowMap)/>
					<file label="Intensity" field={noiseIntensityPath} type="texture" if(mode == NoiseTexture)/>
					<file label="Direction" field={noiseDirectionPath} type="texture" if(mode == NoiseTexture)/>
					<range(0, 1) field={noiseIntensity} if(mode == Frequency)/>
					<range(0, 100) field={noiseFrequency} if(mode == Frequency)/>
				</category>
				<checkbox label="Debug Direction" field={debugDirection} onValueChange={rebuild}/>
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