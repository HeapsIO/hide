package hrt.ui;

#if hui

class HuiScene extends HuiElement {
	static var SRC =
	<hui-scene>
		<bitmap public id="display"/>
	</hui-scene>

	public var s3d : h3d.scene.Scene;
	var renderTexture : h3d.mat.Texture;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		s3d = new h3d.scene.Scene();
	}

	override function onAfterReflow() {
		var textureWidth = hxd.Math.iclamp(hxd.Math.round(calculatedWidth), 1, 4096);
		var textureHeight = hxd.Math.iclamp(hxd.Math.round(calculatedHeight), 1, 4096);

		if (renderTexture == null) {
			renderTexture = new h3d.mat.Texture(1,1, [Target]);
			renderTexture.depthBuffer = new h3d.mat.Texture(1,1, hxd.PixelFormat.Depth24Stencil8);
			display.tile = h2d.Tile.fromTexture(renderTexture);
		}

		if(renderTexture.width != textureWidth || renderTexture.height != textureHeight) {
			renderTexture.resize(textureWidth, textureHeight);
			renderTexture.depthBuffer.resize(textureWidth, textureHeight);
		}

		display.width = maxWidth;
		display.height = maxHeight;
	}

	override function onRemove() {
		super.onRemove();

		s3d.dispose();
		if (renderTexture != null) {
			renderTexture.dispose();
			renderTexture = null;
		}
	}

	override function draw(ctx:h2d.RenderContext) {
		renderTexture.clear(0xff00FF, 1);
		s3d.setOutputTarget(ctx.engine, renderTexture);
		s3d.setElapsedTime(hxd.Timer.dt);
		s3d.render(ctx.engine);
		s3d.setOutputTarget();

		@:privateAccess ctx.initShaders(ctx.baseShaderList);
		ctx.setCurrent();
	}
}

#end
