package hide.prefab.l3d;

class VolumetricLightmap extends Object3D {

	var voxelsize_x : Float = 1.0;
	var voxelsize_y : Float = 1.0;
	var voxelsize_z : Float = 1.0;
	var strength :  Float = 1.0;
	var order : Int = 1;
	var displaySH_field = false;

	var useWorldAlignedProbe = false;
	public var volumetricLightmap : h3d.scene.pbr.VolumetricLightmap;
	var displaySH = false;

	var sceneObject : h3d.scene.Object;

	#if editor
	var maxOrderBaked = 0;
	var baker : hide.view.l3d.ProbeBakerProcess;
	#end

	public function new(?parent) {
		super(parent);
		type = "volumetricLightmap";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		voxelsize_x =  obj.voxelsize_x == null ? 1 : obj.voxelsize_x;
		voxelsize_y =  obj.voxelsize_y == null ? 1 : obj.voxelsize_y;
		voxelsize_z =  obj.voxelsize_z == null ? 1 : obj.voxelsize_z;
		strength =  obj.strength == null ? 1 : obj.strength;
		order =  obj.order == null ? 1 : obj.order;
		displaySH = obj.displaySH == null ? false : obj.displaySH;
		displaySH_field = displaySH;
		useWorldAlignedProbe = obj.useWorldAlignedProbe == null ? false : obj.useWorldAlignedProbe;
	}

	override function save() {
		var o : Dynamic = super.save();
		if( voxelsize_x > 0 ) o.voxelsize_x = voxelsize_x;
		if( voxelsize_y > 0 ) o.voxelsize_y = voxelsize_y;
		if( voxelsize_z > 0 ) o.voxelsize_z = voxelsize_z;
		o.strength = strength;
		o.order = order;
		o.displaySH = displaySH;
		o.useWorldAlignedProbe = useWorldAlignedProbe;
		return o;
	}

	function initProbes(){
		if(!displaySH) clearPreview();
		else resetProbes();
	}

	function resetProbes(){
		volumetricLightmap.updateProbeCount();
		volumetricLightmap.generateProbes();
		for( i in 0...volumetricLightmap.lightProbes.length){
			volumetricLightmap.lightProbes[i].sh = new h3d.scene.pbr.SphericalHarmonic(order);
		}
		volumetricLightmap.packDataInsideTexture();
		createPreview();
	}

	function updateVolumetricLightmap(){

		if(volumetricLightmap == null) return;

		if(volumetricLightmap.voxelSize.x != voxelsize_x || volumetricLightmap.voxelSize.y != voxelsize_y ||volumetricLightmap.voxelSize.z != voxelsize_z){
			volumetricLightmap.voxelSize = new h3d.Vector(voxelsize_x,voxelsize_y,voxelsize_z);
			resetProbes();
		}

		if(volumetricLightmap.shOrder != order){
			if(maxOrderBaked >= order){
				volumetricLightmap.shOrder = order;
				volumetricLightmap.packDataInsideTexture();
				createPreview();
			}
			else{
				volumetricLightmap.shOrder = order;
				resetProbes();
			}
		}

		if(volumetricLightmap.useAlignedProb != useWorldAlignedProbe){
			volumetricLightmap.useAlignedProb = useWorldAlignedProbe;
			resetProbes();
		}

		if(volumetricLightmap.strength != strength){
			volumetricLightmap.strength = strength;
		}

		if(displaySH != displaySH_field){
			displaySH = displaySH_field;
			if(!displaySH) clearPreview();
			else createPreview();
		}
	}

	function clearPreview(){
		var previewSpheres = volumetricLightmap.findAll(c -> if(c.name == "_previewSphere") c else null);
		if (previewSpheres != null) {
			while(previewSpheres.length > 0){
				previewSpheres[previewSpheres.length- 1].remove();
				previewSpheres.pop();
			}
		}
	}

	public function createPreview(){

		if(!displaySH) return;

		clearPreview();

		if(volumetricLightmap == null) return;

		for( i in 0...volumetricLightmap.lightProbes.length){
			var previewSphere = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), volumetricLightmap );
			previewSphere.name = "_previewSphere";
			previewSphere.material.setDefaultProps("ui");
			var size = 0.1;
			previewSphere.scaleX = size/volumetricLightmap.scaleX;
			previewSphere.scaleY = size/volumetricLightmap.scaleY;
			previewSphere.scaleZ = size/volumetricLightmap.scaleZ;
			var probePos = new h3d.Vector(volumetricLightmap.lightProbes[i].position.x, volumetricLightmap.lightProbes[i].position.y, volumetricLightmap.lightProbes[i].position.z);
			volumetricLightmap.globalToLocal(probePos);
			previewSphere.setPosition(probePos.x, probePos.y, probePos.z);
			var shader = new h3d.shader.pbr.SHDisplay();
			shader.order = volumetricLightmap.shOrder;
			var coefCount =volumetricLightmap.shOrder * volumetricLightmap.shOrder;
			shader.SIZE = coefCount;

			if(i < volumetricLightmap.lastBakedProbeIndex+1){
				shader.shCoefsRed = volumetricLightmap.lightProbes[i].sh.coefR.slice(0, coefCount);
				shader.shCoefsGreen = volumetricLightmap.lightProbes[i].sh.coefG.slice(0, coefCount);
				shader.shCoefsBlue = volumetricLightmap.lightProbes[i].sh.coefB.slice(0, coefCount);
			}
			else{
				shader.shCoefsRed = [for (value in 0...coefCount) 0];
				shader.shCoefsGreen = [for (value in 0...coefCount) 0];
				shader.shCoefsBlue = [for (value in 0...coefCount) 0];
			}

			previewSphere.material.mainPass.culling = Back;
			previewSphere.material.shadows = false;
			previewSphere.material.mainPass.addShader(shader);
		}
	}

	override function applyPos( o : h3d.scene.Object ) {

		var needReset = (this.scaleX != o.scaleX || this.scaleY != o.scaleY || this.scaleZ != o.scaleZ);

		super.applyPos(o);

		volumetricLightmap.setTransform(sceneObject.getAbsPos());
		volumetricLightmap.scaleX = o.scaleX;
		volumetricLightmap.scaleY = o.scaleY;
		volumetricLightmap.scaleZ = o.scaleZ;

		resetProbes();
	}

	override function makeInstance(ctx:Context):Context {

		ctx = ctx.clone(this);
		var obj = new h3d.scene.Object(ctx.local3d);
		sceneObject = new h3d.scene.Object(obj);
		sceneObject.setPosition(-0.5, -0.5, -0.5);

		volumetricLightmap = new h3d.scene.pbr.VolumetricLightmap(ctx.local3d);
		ctx.local3d = obj;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);

		volumetricLightmap.voxelSize = new h3d.Vector(voxelsize_x,voxelsize_y,voxelsize_z);
		volumetricLightmap.shOrder = order;
		volumetricLightmap.useAlignedProb = false;
		volumetricLightmap.strength = strength;

		#if editor

		var wire = new h3d.scene.Box(0xFFFFFFFF,obj);
		wire.name = "_highlight";
		wire.material.setDefaultProps("ui");
		wire.ignoreCollide = true;
		wire.material.shadows = false;
		wire.material.castShadows = false;
		wire.visible = false;

		initProbes();

		#end

		return ctx;
	}

	#if editor

	override function getHideProps() : HideProps {
		return { icon : "map-o", name : "VolumetricLightmap" };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		var props = new hide.Element('
			<div class="group" name="Light Params">
				<dl>
				<dt>Strength</dt><dd><input type="range" min="0" max="2" value="0" field="strength"/></dd>
				<dt>SH Order</dt><dd><input type="range" min="1" max="3" value="0" step="1" field="order"/></dd>
				<dt>Use World Aligned Probes</dt><dd><input type="checkbox" field="useWorldAlignedProbe"/></dd>
				<dt>Display SH</dt><dd><input type="checkbox" field="displaySH_field"/></dd>
				<dt></dt><dd><input type="button" value="Bake" class="bake"/></dd>
				<div class="progress">
					<dt>Baking Process</dt><dd><progress class="bakeProgress" max="1"></progress></dd>
				</div>
				</dl>
			</div>
			<div class="group" name="Voxel Size">
				<dl>
					<dt>X</dt><dd><input type="range" min="1" max="10" value="0" field="voxelsize_x"/></dd>
					<dt>Y</dt><dd><input type="range" min="1" max="10" value="0" field="voxelsize_y"/></dd>
					<dt>Z</dt><dd><input type="range" min="1" max="10" value="0" field="voxelsize_z"/></dd>
				</dl>
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			updateVolumetricLightmap();
			ctx.onChange(this, pname);
		});

		function bakeUpdate(dt:Float){
			if(baker == null || baker.progress == 1){
				ctx.removeUpdate(bakeUpdate);
				baker = null;
				ctx.rebuild();
			}
			else{
				baker.update(dt);
				var props = ctx.getCurrentProps(this);
				props.find(".bakeProgress").val(baker.progress);
			}
		}

		function cancel() {
			ctx.removeUpdate(bakeUpdate);
			baker = null;
			ctx.rebuild();
		}

		function startBake() {
			//var props = ctx.getCurrentProps(this);
			props.find(".progress").show();
			props.find(".bake").attr("value","Cancel").off("click").click(function(_) cancel());
		}

		props.find(".progress").hide();
		props.find(".bake").click(function(_) {
			maxOrderBaked = order;
			volumetricLightmap.lastBakedProbeIndex = 0;
			var s3d = @:privateAccess ctx.rootContext.local3d.getScene();
			baker = new hide.view.l3d.ProbeBakerProcess(s3d, this);
			startBake();
			bakeUpdate(0);
			ctx.addUpdate(bakeUpdate);
		});

		if( baker != null ){
			startBake();
			bakeUpdate(0);
			ctx.addUpdate(bakeUpdate);
		}

	}

	public function startBake(ctx : EditContext, ?onEnd){
		maxOrderBaked = order;
		volumetricLightmap.lastBakedProbeIndex = 0;
		var s3d = @:privateAccess ctx.rootContext.local3d.getScene();
		baker = new hide.view.l3d.ProbeBakerProcess(s3d, this);
		baker.onEnd = function() if( onEnd != null ) onEnd();
	}

	#end

	static var _ = hxd.prefab.Library.register("volumetricLightmap", VolumetricLightmap);
}