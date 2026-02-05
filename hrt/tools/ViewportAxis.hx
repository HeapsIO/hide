package hrt.tools;

class ViewportAxis extends h2d.Object {
	public static final X_COLOR = new h3d.Vector4(0.96, 0.21, 0.32, 1);
	public static final Y_COLOR = new h3d.Vector4(0.43, 0.64, 0.10, 1);
	public static final Z_COLOR = new h3d.Vector4(0.18, 0.51, 0.89, 1);

	var parentSceneCam : h3d.Camera;
	var parentSceneCamCtrl : h3d.scene.CameraController;
	var parentScene : h2d.Scene;

	var bmp : h2d.Bitmap;
	var int : h2d.Interactive;
	var renderTexture : h3d.mat.Texture;
	var s3d : h3d.scene.Scene;
	var s2d : h2d.Scene;
	var backgroundColor : Int = 0;
	var gizmo : h3d.scene.Object;

	public function new(parentSceneCam : h3d.Camera, parentSceneCamCtrl : h3d.scene.CameraController, ?parent : h2d.Object) {
		super(parent);
		this.parentSceneCam = parentSceneCam;
		this.parentScene = getScene();
		this.parentSceneCamCtrl = parentSceneCamCtrl;

		renderTexture = new h3d.mat.Texture(128, 128, [ Target ]);
		renderTexture.depthBuffer = new h3d.mat.Texture(128, 128, h3d.mat.Data.TextureFormat.Depth32);
		bmp = new h2d.Bitmap(h2d.Tile.fromTexture(renderTexture), this);
		bmp.smooth = true;

		s2d = new h2d.Scene();
		s2d.scaleMode = Stretch(128, 128);
		s3d = new h3d.scene.Scene(false);
		s3d.renderer = new h3d.scene.fwd.Renderer();
		s3d.camera.pos.set(-10, 0, 0);
		s3d.camera.target.load(s3d.camera.pos + new h3d.Vector(1, 0, 0));

		gizmo = hxd.res.Embed.getResource("hrt/tools/res/viewportAxisGizmo.hmd").toModel().toHmd().makeObject();
		gizmo.getObjectByName("Axis_X").culled = true;
		gizmo.getObjectByName("Axis_Y").culled = true;
		gizmo.getObjectByName("Axis_Z").culled = true;
		gizmo.getObjectByName("Axis_MinusX").culled = true;
		gizmo.getObjectByName("Axis_MinusY").culled = true;
		gizmo.getObjectByName("Axis_MinusZ").culled = true;
		gizmo.getObjectByName("Axis_X_Branch").getMaterials()[0].color.set(X_COLOR.x, X_COLOR.y, X_COLOR.z);
		gizmo.getObjectByName("Axis_Y_Branch").getMaterials()[0].color.set(Y_COLOR.x, Y_COLOR.y, Y_COLOR.z);
		gizmo.getObjectByName("Axis_Z_Branch").getMaterials()[0].color.set(Z_COLOR.x, Z_COLOR.y, Z_COLOR.z);
		s3d.addChild(gizmo);

		var xTile = h2d.Tile.fromTexture(hxd.res.Embed.getResource("hrt/tools/res/X.png").toTexture());
		var yTile = h2d.Tile.fromTexture(hxd.res.Embed.getResource("hrt/tools/res/Y.png").toTexture());
		var zTile = h2d.Tile.fromTexture(hxd.res.Embed.getResource("hrt/tools/res/Z.png").toTexture());
		var xTileMinus = h2d.Tile.fromTexture(hxd.res.Embed.getResource("hrt/tools/res/XMinus.png").toTexture());
		var yTileMinus = h2d.Tile.fromTexture(hxd.res.Embed.getResource("hrt/tools/res/YMinus.png").toTexture());
		var zTileMinus = h2d.Tile.fromTexture(hxd.res.Embed.getResource("hrt/tools/res/ZMinus.png").toTexture());
		xTile = xTile.center();
		yTile = yTile.center();
		zTile = zTile.center();
		xTileMinus = xTileMinus.center();
		yTileMinus = yTileMinus.center();
		zTileMinus = zTileMinus.center();
		var xFollow = new h2d.ObjectFollower(gizmo.getObjectByName("Axis_X"), s2d);
		var yFollow = new h2d.ObjectFollower(gizmo.getObjectByName("Axis_Y"), s2d);
		var zFollow = new h2d.ObjectFollower(gizmo.getObjectByName("Axis_Z"), s2d);
		var xFollowMinus = new h2d.ObjectFollower(gizmo.getObjectByName("Axis_MinusX"), s2d);
		var yFollowMinus = new h2d.ObjectFollower(gizmo.getObjectByName("Axis_MinusY"), s2d);
		var zFollowMinus = new h2d.ObjectFollower(gizmo.getObjectByName("Axis_MinusZ"), s2d);
		xFollow.offsetX = yFollow.offsetY = zFollow.offsetZ = 1.25;
		xFollow.depthMask = yFollow.depthMask = zFollow.depthMask = true;
		xFollow.depthBias = yFollow.depthBias = zFollow.depthBias = 0.25;
		xFollowMinus.offsetX = yFollowMinus.offsetY = zFollowMinus.offsetZ = -1.25;
		xFollowMinus.depthMask = yFollowMinus.depthMask = zFollowMinus.depthMask = true;
		xFollowMinus.depthBias = yFollowMinus.depthBias = zFollowMinus.depthBias = 0.25;
		var bmpX = new h2d.Bitmap(xTile, xFollow);
		bmpX.scale(0.15);
		var bmpY = new h2d.Bitmap(yTile, yFollow);
		bmpY.scale(0.15);
		var bmpZ = new h2d.Bitmap(zTile, zFollow);
		bmpZ.scale(0.15);
		var bmpXMinus = new h2d.Bitmap(xTileMinus, xFollowMinus);
		bmpXMinus.scale(0.15);
		var bmpYMinus = new h2d.Bitmap(yTileMinus, yFollowMinus);
		bmpYMinus.scale(0.15);
		var bmpZMinus = new h2d.Bitmap(zTileMinus, zFollowMinus);
		bmpZMinus.scale(0.15);

		int = new h2d.Interactive(128, 128, bmp);
		int.propagateEvents = true;
		int.cancelEvents = false;
		int.cursor = Default;
		int.onPush = function(e) {
			for (idx => b in [bmpX, bmpY, bmpZ, bmpXMinus, bmpYMinus, bmpZMinus]) {
				if (e.relX > b.absX - (b.tile.width * b.scaleX) / 2 && e.relX < b.absX + (b.tile.width * b.scaleX) / 2
				&& e.relY > b.absY - (b.tile.height * b.scaleY) / 2 && e.relY < b.absY + (b.tile.height * b.scaleY) / 2) {
					switch (idx) {
						case 0:
							parentSceneCamCtrl.set(null, 0, hxd.Math.PI / 2, null);
						case 1:
							parentSceneCamCtrl.set(null, hxd.Math.PI / 2, hxd.Math.PI / 2, null);
						case 2:
							parentSceneCamCtrl.set(null, 0, 0, null);
						case 3:
							parentSceneCamCtrl.set(null, hxd.Math.PI, hxd.Math.PI / 2, null);
						case 4:
							parentSceneCamCtrl.set(null, -hxd.Math.PI / 2, hxd.Math.PI / 2, null);
						case 5:
							parentSceneCamCtrl.set(null, 0, hxd.Math.PI, null);
					}
				}
			}
		};
	}

	override function sync(ctx : h2d.RenderContext) {
		super.sync(ctx);

		setPosition(parentScene.width - 128, 0);

		s3d.camera.target = gizmo.getPosition();
		s3d.camera.pos = parentSceneCam.getForward() * -10;
	}

	override function draw(ctx: h2d.RenderContext) {
		super.draw(ctx);

		if (renderTexture != null) {
			var prevRZ = ctx.getCurrentRenderZone();
			@:privateAccess ctx.clearRZ();

			var engine = ctx.engine;
			s3d.setOutputTarget(ctx.engine, renderTexture);
			engine.clear(backgroundColor, 1.0);
			s3d.setElapsedTime(hxd.Timer.dt);
			s3d.render(ctx.engine);
			s2d.setElapsedTime(hxd.Timer.dt);
			s2d.render(ctx.engine);
			s3d.setOutputTarget();

			if( prevRZ != null )
				@:privateAccess ctx.setRZ(prevRZ.x, prevRZ.y, prevRZ.width, prevRZ.height);

			@:privateAccess ctx.initShaders(ctx.baseShaderList);
			ctx.setCurrent();
		}
	}

	override function onRemove() {
		super.onRemove();

		s3d.dispose();
		s2d.dispose();
		int.remove();

		if (renderTexture != null) {
			renderTexture.dispose();
			renderTexture = null;
		}
	}
}