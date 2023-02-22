package hrt.prefab2.vlm;

class VolumetricLightmap extends Object3D {

	@:s var voxelsize_x : Float = 1.0;
	@:s var voxelsize_y : Float = 1.0;
	@:s var voxelsize_z : Float = 1.0;
	@:s var strength :  Float = 1.0;
	@:s var order : Int = 1;

	public var volumetricLightmap : VolumetricMesh;
	@:s var useWorldAlignedProbe = false;
	@:s var displaySH = false;
	@:s var resolution : Int = 16;
	var useGPU = true;

	#if editor
	@:c var displaySH_field = false;
	var maxOrderBaked = 0;
	var baker : hide.view2.l3d.ProbeBakerProcess;
	#end

	public function new(?parent) {
		super(parent);
	}

	#if editor
	override function load( obj : Dynamic ) {
		super.load(obj);
		displaySH_field = displaySH;
	}
	#end

	function initProbes(){
		createDebugPreview();
	}

	function resetLightmap(){
		if(volumetricLightmap.lightProbeTexture != null) volumetricLightmap.lightProbeTexture.dispose();
		volumetricLightmap.lightProbeTexture = null;
		volumetricLightmap.updateProbeCount();
		createDebugPreview();
	}

	function updateVolumetricLightmap(){
		#if editor

		if(volumetricLightmap == null) return;

		if(volumetricLightmap.voxelSize.x != voxelsize_x || volumetricLightmap.voxelSize.y != voxelsize_y ||volumetricLightmap.voxelSize.z != voxelsize_z){
			volumetricLightmap.voxelSize = new h3d.Vector(voxelsize_x,voxelsize_y,voxelsize_z);
			resetLightmap();
		}

		if(volumetricLightmap.shOrder != order){
			if(maxOrderBaked >= order){
				volumetricLightmap.shOrder = order;
				createDebugPreview();
			}
			else{
				volumetricLightmap.shOrder = order;
				resetLightmap();
			}
		}

		if(volumetricLightmap.useAlignedProb != useWorldAlignedProbe){
			volumetricLightmap.useAlignedProb = useWorldAlignedProbe;
			resetLightmap();
		}

		if(volumetricLightmap.strength != strength){
			volumetricLightmap.strength = strength;
		}

		if(displaySH != displaySH_field){
			displaySH = displaySH_field;
			if(!displaySH) clearDebugPreview();
			else createDebugPreview();
		}
		#end
	}

	function clearDebugPreview(){
		var previewSpheres = volumetricLightmap.findAll(c -> if(c.name == "_previewSphere") c else null);
		if (previewSpheres != null) {
			while(previewSpheres.length > 0){
				previewSpheres[previewSpheres.length- 1].remove();
				previewSpheres.pop();
			}
		}
	}

	public function createDebugPreview(){

		if(!displaySH) return;

		clearDebugPreview();

		if(volumetricLightmap == null) return;

		var pixels : hxd.Pixels = null;
		if(volumetricLightmap.lightProbeTexture != null)
			pixels = volumetricLightmap.lightProbeTexture.capturePixels();

		for( i in 0...volumetricLightmap.getProbeCount()){
			var previewSphere = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), volumetricLightmap );
			previewSphere.name = "_previewSphere";
			previewSphere.material.setDefaultProps("ui");
			var size = 0.1;
			previewSphere.scaleX = size/volumetricLightmap.parent.scaleX;
			previewSphere.scaleY = size/volumetricLightmap.parent.scaleY;
			previewSphere.scaleZ = size/volumetricLightmap.parent.scaleZ;
			var probePos = volumetricLightmap.getProbePosition(volumetricLightmap.getProbeCoords(i));
			volumetricLightmap.globalToLocal(probePos);
			previewSphere.setPosition(probePos.x, probePos.y, probePos.z);
			var shader = new hrt.shader.DisplaySH();
			shader.order = volumetricLightmap.shOrder;
			shader.strength = volumetricLightmap.strength;
			var coefCount = volumetricLightmap.getCoefCount();
			shader.SIZE = coefCount;

			var sh = volumetricLightmap.getProbeSH(volumetricLightmap.getProbeCoords(i), pixels);
			shader.shCoefsRed = sh.coefR.slice(0, coefCount);
			shader.shCoefsGreen = sh.coefG.slice(0, coefCount);
			shader.shCoefsBlue = sh.coefB.slice(0, coefCount);

			previewSphere.material.mainPass.culling = Back;
			previewSphere.material.shadows = false;
			previewSphere.material.mainPass.addShader(shader);
		}
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		if(propName ==  "strength" && displaySH){
			var previewSpheres = volumetricLightmap.findAll(c -> if(c.name == "_previewSphere") c else null);
			for(ps in previewSpheres){
				var mesh = Std.downcast(ps, h3d.scene.Mesh);
				var shader = mesh.material.mainPass.getShader(hrt.shader.DisplaySH);
				if(shader != null) shader.strength = volumetricLightmap.strength;
			}
		}
		if( propName != "visible" && propName != "strength" && propName != "order" && propName != "displaySH_field" && propName != "useGPU" &&  propName != "resolution")
			resetLightmap();
	}

	override function makeInstance(ctx: hrt.prefab2.Prefab.InstanciateContext) : Void{
		var obj = new h3d.scene.Object(ctx.local3d);
		volumetricLightmap = new hrt.prefab2.vlm.VolumetricMesh(obj);
		volumetricLightmap.ignoreCollide = true;
		volumetricLightmap.setPosition(-0.5, -0.5, 0);
		ctx.local3d = obj;
		ctx.local3d.name = name;
		updateInstance();

		volumetricLightmap.voxelSize = new h3d.Vector(voxelsize_x,voxelsize_y,voxelsize_z);
		volumetricLightmap.shOrder = order;
		volumetricLightmap.useAlignedProb = false;
		volumetricLightmap.strength = strength;

		var res = loadPrefabDat("sh", "bake", name);
		if(res != null) volumetricLightmap.load(res.entry.getBytes());

		#if editor
		initProbes();
		#end
	}

	#if editor

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "map-o", name : "VolumetricLightmap" };
	}

	override function setSelected(b : Bool ) {
		if( b ) {
			var obj = local3d;
			var wire = new h3d.scene.Box(volumetricLightmap.lightProbeTexture == null ? 0xFFFF0000 : 0xFFFFFFFF,h3d.col.Bounds.fromValues(-0.5,-0.5,0,1,1,1),obj);
			wire.name = "_highlight";
			wire.material.setDefaultProps("ui");
			wire.ignoreCollide = true;
			wire.material.shadows = false;
		} else {
			for( o in getObjects(h3d.scene.Box) )
				if( o.name == "_highlight" ) {
					o.remove();
					return false;
				}
		}
		return true;
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);
		var props = new hide.Element('
			<div class="group" name="Light Params">
				<dl>
				<dt>Strength</dt><dd><input type="range" min="0" max="2" value="0" field="strength"/></dd>
				<dt>Display SH</dt><dd><input type="checkbox" field="displaySH_field"/></dd>
				</dl>
			</div>
			<div class="group" name="Bake">
				<dt>SH Order</dt><dd><input type="range" min="1" max="3" value="0" step="1" field="order"/></dd>
				<dt>Resolution</dt><dd><input type="range" min="1" max="1024" value="0" step="1" field="resolution"/></dd>
				<dt>Use GPU</dt><dd><input type="checkbox" field="useGPU"/></dd>
				<dt></dt><dd><input type="button" value="Bake" class="bake"/></dd>
				<div class="progress">
					<dt>Baking Process</dt><dd><progress class="bakeProgress" max="1"></progress></dd>
				</div>
			</dl></div>
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
				ctx.rebuildProperties();
			}
			else{
				baker.update(dt);
				if( baker == null ) return;
				var props = ctx.getCurrentProps(this);
				props.find(".bakeProgress").val(baker.progress);
			}
		}

		function cancel() {
			ctx.removeUpdate(bakeUpdate);
			baker = null;
			ctx.rebuildProperties();
		}

		function startedBake() {
			//var props = ctx.getCurrentProps(this);
			props.find(".progress").show();
			props.find(".bake").attr("value","Cancel").off("click").click(function(_) cancel());
			bakeUpdate(0);
		}

		props.find(".progress").hide();
		props.find(".bake").click(function(_) {
			startBake(ctx, cancel);
			startedBake();
			ctx.addUpdate(bakeUpdate);
		});

		if( baker != null ){
			startedBake();
			ctx.addUpdate(bakeUpdate);
		}

	}

	public function startBake(ctx : hide.prefab2.EditContext, ?onEnd){
		maxOrderBaked = order;
		volumetricLightmap.lastBakedProbeIndex = -1;
		var s3d = @:privateAccess local3d.getScene();
		baker = new hide.view2.l3d.ProbeBakerProcess(this, resolution, useGPU, 0.032);

		var pbrRenderer = Std.downcast(s3d.renderer, h3d.scene.pbr.Renderer);
		if(pbrRenderer != null) {
			if( pbrRenderer.env == null || pbrRenderer.env.env == null || pbrRenderer.env.env.isDisposed() )
					trace("Environment missing");
		} else
			trace("Invalid renderer");

		var sceneData = @:privateAccess ctx.scene.editor.sceneData;
		baker.init(pbrRenderer.env, sceneData.copyDefault(), ctx.scene);

		baker.onEnd = function() {
			if( onEnd != null ) onEnd();
			var bytes = volumetricLightmap.save();
			sceneData.savePrefabDat("sh", "bake", name, bytes);
			createDebugPreview();
		}
	}

	#end

	static var _ = Prefab.register("volumetricLightmap", VolumetricLightmap);
}