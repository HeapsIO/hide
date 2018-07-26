package hide.prefab.l3d;

class VolumetricLightmap extends Object3D {

	var voxelsize_x : Float = 1.0;
	var voxelsize_y : Float = 1.0;
	var voxelsize_z : Float = 1.0;
	var strength :  Float = 1.0;
	var order : Int = 1;
	var displaySH_field = false;

	public var volumetricLightmap : h3d.scene.pbr.VolumetricLightmap;
	var useWorldAlignedProbe = false;
	var displaySH = false;

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

		var pixels : hxd.Pixels.PixelsFloat = null;
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
			var shader = new h3d.shader.pbr.SHDisplay();
			shader.order = volumetricLightmap.shOrder;
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

	override function applyPos( o : h3d.scene.Object ) {
		super.applyPos(o);
		resetLightmap();
	}

	override function makeInstance(ctx:Context):Context {

		ctx = ctx.clone(this);
		var obj = new h3d.scene.Object(ctx.local3d);
		volumetricLightmap = new h3d.scene.pbr.VolumetricLightmap(obj);
		volumetricLightmap.ignoreCollide = true;
		volumetricLightmap.setPosition(-0.5, -0.5, 0);
		ctx.local3d = obj;
		ctx.local3d.name = name;
		applyPos(ctx.local3d);

		volumetricLightmap.voxelSize = new h3d.Vector(voxelsize_x,voxelsize_y,voxelsize_z);
		volumetricLightmap.shOrder = order;
		volumetricLightmap.useAlignedProb = false;
		volumetricLightmap.strength = strength;
		var bytes = ctx.shared.loadBakedBytes(name+".vlm");
		if( bytes != null ) volumetricLightmap.load(bytes);

		#if editor
		initProbes();
		#end
		return ctx;
	}

	#if editor

	override function getHideProps() : HideProps {
		return { icon : "map-o", name : "VolumetricLightmap" };
	}

	override function setSelected( ctx : Context, b : Bool ) {
		if( b ) {
			var obj = ctx.shared.contexts.get(this).local3d;
			var wire = new h3d.scene.Box(volumetricLightmap.lightProbeTexture == null ? 0xFFFF0000 : 0xFFFFFFFF,h3d.col.Bounds.fromValues(-0.5,-0.5,0,1,1,1),obj);
			wire.name = "_highlight";
			wire.material.setDefaultProps("ui");
			wire.ignoreCollide = true;
			wire.material.shadows = false;
		} else {
			for( o in ctx.shared.getObjects(this,h3d.scene.Box) )
				if( o.name == "_highlight" ) {
					o.remove();
					return;
				}
		}
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

	public function startBake(ctx : EditContext, ?onEnd){
		maxOrderBaked = order;
		volumetricLightmap.lastBakedProbeIndex = 0;
		var s3d = @:privateAccess ctx.rootContext.local3d.getScene();
		baker = new hide.view.l3d.ProbeBakerProcess(s3d, this);
		baker.onEnd = function() {
			if( onEnd != null ) onEnd();
			var bytes = volumetricLightmap.save();
			ctx.rootContext.shared.saveBakedBytes(name+".vlm", bytes);
		}
	}

	#end

	static var _ = hxd.prefab.Library.register("volumetricLightmap", VolumetricLightmap);
}