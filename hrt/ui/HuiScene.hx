package hrt.ui;

#if hui

class HuiScene extends HuiElement {
	static var SRC =
	<hui-scene>
		<bitmap public id="display"/>
	</hui-scene>

	/**Clear color of the 3d scene. Must include the alpha component in order to be visible**/
	@:p var backgroundColor : Int = 0;

	public var s2d : h2d.Scene;
	public var s3d : h3d.scene.Scene;
	public var s3dinter: Hui3DInteractiveScene;
	var renderTexture : h3d.mat.Texture;

	override function set_enableInteractive(b:Bool):Bool {
		if( enableInteractive == b )
			return b;
		if( b ) {
			if( interactive == null ) {
				var interactive = new Interactive2(0, 0);
				addChildAt(interactive,0);
				this.interactive = interactive;
				interactive.cursor = Default;
				getProperties(interactive).isAbsolute = true;
				if( !needReflow ) {
					interactive.width = calculatedWidth;
					interactive.height = calculatedHeight;
				}
				interactive.onWheel = onMouseWheel;
			}
		} else {
			if( interactive != null ) {
				interactive.remove();
				interactive = null;
			}
		}
		return enableInteractive = b;
	}

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();



		s2d = new h2d.Scene();
		s3d = new h3d.scene.Scene();
		// new h3d.scene.Box(0x000000, s3d);
		// var t = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		// t.text = "Hello scene";

		// enableInteractive = true;
		// (cast interactive:Interactive2).huiScene = this;

		// new h3d.scene.CameraController(s3d);
		// @:privateAccess new hrt.ui.HuiButtonMenu(() -> [], base);
	}

	var wasVisible = false;
	override function sync(ctx) {
		var currentVisible = true;
		var current : h2d.Object = this;
		while(current != null) {
			if (!current.visible) {
				currentVisible = false;
				break;
			}
			current = current.parent;
		}

		if (currentVisible != wasVisible) {
			wasVisible = currentVisible;
			var base = uiBase;

			if (currentVisible) {
				s3dinter = new Hui3DInteractiveScene(this);
				base.app.sevents.addScene(s3dinter,0);
				base.app.sevents.addScene(s2d,0);
			} else {
				base.app.sevents.removeScene(s3dinter);
				base.app.sevents.removeScene(s2d);
			}
		}

		if (currentVisible) {
			s3d.scenePosition = s3d.scenePosition ?? {offsetX: 0, offsetY: 0, width: 0, height: 0};
			s3d.scenePosition.offsetX = display.absX;
			s3d.scenePosition.offsetY = display.absY;
			s3d.scenePosition.width = Std.int(display.width);
			s3d.scenePosition.height = Std.int(display.height);
		}

		super.sync(ctx);
	}

	override function onAfterReflow() {
		var textureWidth = hxd.Math.iclamp(hxd.Math.round(innerWidth), 1, 4096);
		var textureHeight = hxd.Math.iclamp(hxd.Math.round(innerHeight), 1, 4096);

		if (renderTexture == null) {
			renderTexture = new h3d.mat.Texture(1,1, [Target]);
			renderTexture.depthBuffer = new h3d.mat.Texture(1,1, hxd.PixelFormat.Depth24Stencil8);

		}

		if(renderTexture.width != textureWidth || renderTexture.height != textureHeight) {
			renderTexture.resize(textureWidth, textureHeight);
			renderTexture.depthBuffer.resize(textureWidth, textureHeight);
			display.tile = h2d.Tile.fromTexture(renderTexture);
		}

		display.width = innerWidth;
		display.height = innerHeight;

		s2d.scaleMode = Stretch(innerWidth, innerHeight);
		var pos = this.getAbsPos().getPosition();
		@:privateAccess s2d.offsetX = pos.x;
		@:privateAccess s2d.offsetY = pos.y;

		var scenePosition = {
			offsetX : pos.x,
			offsetY : pos.y,
			width : Std.int(innerWidth),
			height : Std.int(innerHeight)
		};
		s3d.scenePosition = scenePosition;
	}

	override function onRemove() {
		super.onRemove();

		s3d.dispose();
		s2d.dispose();

		var base = uiBase;
		base.app.sevents.removeScene(s2d);
		base.app.sevents.removeScene(s3dinter);

		if (renderTexture != null) {
			renderTexture.dispose();
			renderTexture = null;
		}
	}

	override function draw(ctx:h2d.RenderContext) {
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
}

@:access(hrt.ui.HuiScene)
@:access(h3d.scene.Scene)
class Hui3DInteractiveScene implements hxd.SceneEvents.InteractiveScene {
	var huiScene: HuiScene;
	var dummyInteractive : Hui3DInteractive;

	public function new(huiScene: HuiScene) {
		this.huiScene = huiScene;
		dummyInteractive = new Hui3DInteractive(this);
	}

	public function setEvents( s : hxd.SceneEvents ) : Void {
		huiScene.s3d.events = s;
	};
	public function handleEvent( e : hxd.Event, last : hxd.SceneEvents.Interactive ) : hxd.SceneEvents.Interactive {
		var i = huiScene.s3d.handleEvent(e, last);
		if (i == null) {
			var x = e.relX - huiScene.s3d.scenePosition?.offsetX;
			var y = e.relY - huiScene.s3d.scenePosition?.offsetY;

			var base = huiScene.uiBase;

			if (x >= 0 && y >= 0 && x < huiScene.s3d.scenePosition?.width && y < huiScene.s3d.scenePosition?.height) {

				dispatchListeners(e);
				e.propagate = false;

				return dummyInteractive;
			}
		}
		return i;
	};
	public function dispatchEvent( e : hxd.Event, to : hxd.SceneEvents.Interactive ) : Void {
		if (Std.downcast(to, Hui3DInteractive) != null) {
			return;
		}
		huiScene.s3d.dispatchEvent(e, to);
	};
	public function dispatchListeners( e : hxd.Event ) : Void {
		huiScene.s3d.dispatchListeners(e);
	};
	public function isInteractiveVisible( i : hxd.SceneEvents.Interactive ) : Bool {
		if (Std.downcast(i, Hui3DInteractive) != null) {
			return true;
		}
		return huiScene.s3d.isInteractiveVisible(i);
	};
}

class Hui3DInteractive implements hxd.SceneEvents.Interactive {
	public var propagateEvents : Bool;
	var interactiveScene: Hui3DInteractiveScene;

	public function new(interactiveScene: Hui3DInteractiveScene) {
		this.interactiveScene = interactiveScene;
		propagateEvents = false;
	}

	public var cursor(default, set) : hxd.Cursor;

	function set_cursor(v) {
		return cursor = v;
	}

	public function handleEvent( e : hxd.Event ) : Void {

	};

	public function getInteractiveScene() : hxd.SceneEvents.InteractiveScene {
		return interactiveScene;
	};
}

class Interactive2 extends h2d.Interactive {
	public var huiScene: HuiScene;
	override function handleEvent( e : hxd.Event ) {
		super.handleEvent(e);
		e.propagate = true;
		var i = huiScene.s3d.handleEvent(e, null);
		if (i == null) {
			huiScene.s3d.dispatchListeners(e);
		}
		e.propagate = false;
	}
}

#end
