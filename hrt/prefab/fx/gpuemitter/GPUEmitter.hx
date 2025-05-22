package hrt.prefab.fx.gpuemitter;

enum Mode {
	World;
	Local;
	Camera;
}

enum Align {
	FaceCam;
	Speed;
}

enum SpeedMode {
	Normal;
	None;
}

typedef Data = {
	var maxCount : Int;
	var rate : Int;
	var infinite : Bool;
	var maxLifeTime : Float;
	var minLifeTime : Float;
	var maxSize : Float;
	var minSize : Float;
	var startSpeed : Float;
	var trs : h3d.Matrix;
	var mode : Mode;
	var cameraModeDistance : Float;
	var align : Align;
	var speedMode : SpeedMode;
	var maxStartSpeed : Float;
	var minStartSpeed : Float;
}

class EditorParticleShader extends hxsl.Shader {
	static var SRC = {

		var particleLife : Float;
		var particleLifeTime : Float;
		var particleRandom : Float;

		function __init__vertex() {
			particleLife = 0.0;
			particleLifeTime = 0.0;
			particleRandom = 0.0;
		}
	}
}

@:access(hrt.prefab.fx.gpuemitter.GPUEmitterObject)
class GPUEmitter extends Object3D {

	static function getDefaultPrimitive() {
		return h3d.prim.Cube.defaultUnitCube();
	}

	@:s var rate : Int = 0;
	@:s var maxCount : Int = 512;
	@:s var minLifeTime : Float = 0.5;
	@:s var maxLifeTime : Float = 1.0;
	@:s var minStartSpeed : Float = 0.5;
	@:s var maxStartSpeed : Float = 1.0;
	@:s var minSize : Float = 0.5;
	@:s var maxSize : Float = 1.5;
	@:s var startSpeed : Float = 1.0;
	@:s var infinite : Bool = false;
	@:s var mode : Mode = World;
	@:s var cameraModeDistance : Float = 50.0;
	@:s var align : Align = FaceCam;
	@:s var speedMode : SpeedMode = Normal;

	override function makeObject(parent3d : h3d.scene.Object) {
		return new h3d.scene.Object(parent3d);
	}

	function updateEmitters() : Array<{meshes : Array<h3d.scene.Mesh>, prefab : hrt.prefab.Prefab, emitters : Array<GPUEmitterObject>}> {
		#if editor
		return [];
		#end
		for ( emitter in local3d.findAll(o -> Std.downcast(o, GPUEmitterObject)) )
			emitter.remove();

		var templates = [];
		for ( c in children ) {
			if ( Std.isOfType(c, hrt.prefab.Shader) )
				continue;
			var obj = new h3d.scene.Object();
			var cloned = c.make(new ContextShared(obj));
			var clonedMeshes = obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh));
			templates.push({meshes : clonedMeshes, prefab : cloned, emitters : []});
		}
		inline function createEmitter(data, prim, materials) {
			return new GPUEmitterObject(data, prim, materials, local3d);
		}
		inline function getData(trs : h3d.Matrix) : Data {
			return {
				rate : rate,
				maxCount : maxCount,
				minLifeTime : minLifeTime,
				maxLifeTime : maxLifeTime,
				minSize : minSize,
				maxSize : maxSize,
				startSpeed : startSpeed,
				trs : trs,
				infinite : infinite,
				mode : mode,
				cameraModeDistance : cameraModeDistance,
				align : align,
				speedMode : speedMode,
				minStartSpeed : minStartSpeed,
				maxStartSpeed : maxStartSpeed,
			}
		}

		for ( t in templates ) {
			for ( mesh in t.meshes ) {
				var multimat = Std.downcast(mesh, h3d.scene.MultiMaterial);
				var materials : Array<h3d.mat.Material>;
				if ( multimat == null )
					materials = [mesh.material];
				else
					materials = multimat.materials;
				var emitter = createEmitter(getData(mesh.getAbsPos().clone()), cast(mesh.primitive, h3d.prim.MeshPrimitive), materials);
				t.emitters.push(emitter);
				mesh.visible = false;
				mesh.ignoreCollide = true;
			}
		}

		return templates;
	}

	function init() {
		var templates = updateEmitters();

		for ( t in templates ) {
			for ( emitter in t.emitters ) {
				emitter.customAnimations = [];
				var shaders = t.prefab.findAll(hrt.prefab.Shader);
				for ( shader in shaders ) {
					if( !shader.enabled ) continue;
					hrt.prefab.fx.BaseFX.BaseFXTools.getCustomAnimations(shader, emitter.customAnimations, emitter.find(o -> Std.downcast(o, h3d.scene.MeshBatch)));
				}
				emitter.init();
				emitter.bakeAnimations();
			}
		}
	}

	override function makeChild(c : hrt.prefab.Prefab) {
		if ( !Std.isOfType(c, hrt.prefab.Shader) )
			return;
		super.makeChild(c);
	}

	override function updateInstance(?propName : String) {
		super.updateInstance(propName);

		init();
		#if editor
		for (m in local3d.getMaterials() ) {
			var s = m.mainPass.getShader(EditorParticleShader);
			if ( s != null )
				m.mainPass.removeShader(s);
			m.mainPass.addShader(new EditorParticleShader());
		}
		#end
	}

	#if editor
	override function setSelected(b : Bool) {
		return false;
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "asterisk",
		name : "GPUEmitter",
		allowParent : function(p) return p.to(FX) != null || p.findParent(FX) != null,
		onChildUpdate : function(p : hrt.prefab.Prefab) return updateEmitters(),
		};
	}

	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		var properties = new hide.Element('
		<div class="group" name="Emitter">
			<dl>
				<dt>Rate</dt><dd><input type="range" step="1" min="1" max="8192" field="rate"/></dd>
				<dt>Max count</dt><dd><input type="range" step="1" min="1" max="8192" field="maxCount"/></dd>
				<dt>Min life time</dt><dd><input type="range" min="0.1" max="10" field="minLifeTime"/></dd>
				<dt>Max life time</dt><dd><input type="range" min="0.1" max="10" field="maxLifeTime"/></dd>
				<dt>Min size</dt><dd><input type="range" min="0.1" max="10" field="minSize"/></dd>
				<dt>Max size</dt><dd><input type="range" min="0.1" max="10" field="maxSize"/></dd>
				<dt>Infinite</dt><dd><input type="checkbox" field="infinite"/></dd>
				<dt>Mode</dt>
				<dd>
					<select field="mode">
						<option value="World">World</option>
						<option value="Local">Local</option>
						<option value="Camera">Camera</option>
					</select>
				</dd>
				<div id="modeCamera">
					<dt>Camera distance</dt><dd><input type="range" min="0" field="cameraModeDistance"/></dd>
				</div>
				<dt>Align</dt>
				<dd>
					<select field="align">
						<option value="FaceCam">Face cam</option>
						<option value="Speed">Speed</option>
					</select>
				</dd>
				<dt>Speed</dt>
				<dd>
					<select field="speedMode">
						<option value="Normal">Normal</option>
						<option value="None">None</option>
					</select>
				</dd>
				<dt>Min start speed</dt><dd><input type="range" min="0.1" max="10" field="minStartSpeed"/></dd>
				<dt>Max start speed</dt><dd><input type="range" min="0.1" max="10" field="maxStartSpeed"/></dd>
			</dl>
		</div>
		');

		inline function refreshOptParams(name : String, condition : Bool) {
			var params = properties.find(name);
			if (condition)
				params.show();
			else
				params.hide();
		}

		refreshOptParams("#modeCamera", mode == Camera);
		ctx.properties.add(properties, this, function(pname) {
				ctx.onChange(this, pname);
				if (pname == "mode")
					refreshOptParams("#modeCamera", mode == Camera);
		});
	}
	#end

	static var _ = Prefab.register("gpuemitter", GPUEmitter);
}