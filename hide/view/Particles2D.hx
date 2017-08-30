package hide.view;

@:access(hide.view.Particles2D)
private class Particles extends h2d.Particles {

	var parts : Particles2D;

	public function new(parts, parent) {
		this.parts = parts;
		super(parent);
	}

	override function loadTexture( path : String ) {
		return parts.scene.loadTexture(parts.state.path, path);
	}

}

class Particles2D extends FileView {

	var scene : hide.comp.Scene;
	var parts : Particles;
	var background : h2d.Bitmap = null;
	var bgPos : h2d.col.Point;
	var properties : hide.comp.PropsEditor;

	override function getDefaultContent() {
		var p = new Particles(this,null);
		p.addGroup().name = "Default";
		return haxe.io.Bytes.ofString(ide.toJSON(p.save()));
	}

	override function onDisplay() {
		root.html('
			<div class="flex">
				<div class="scene"></div>
				<div class="props"></div>
			</div>
		');
		properties = new hide.comp.PropsEditor(root.find(".props"), undo);
		properties.saveDisplayKey = "particles2D";
		scene = new hide.comp.Scene(root.find(".scene"));
		scene.onReady = init;
	}

	override function save() {
		sys.io.File.saveContent(getPath(), ide.toJSON(parts.save()));
	}

	function addGroup( g : h2d.Particles.ParticleGroup ) {
		var e = new Element('
			<div class="section">
				<h1><span>${g.name}</span> &nbsp;<input type="checkbox" field="enable"/></h1>
				<div class="content">

					<div class="group" name="Display">
						<dl>
							<dt>Name</dt><dd><input field="name" onchange="$(this).closest(\'.section\').find(\'>h1 span\').text($(this).val())"/></dd>
							<dt>Blend Mode</dt><dd><select field="blendMode"/></dd></dd>
							<dt>Texture</dt><dd><input type="texture" field="texture"/></dd>
							<dt>Color Gradient</dt><dd><input type="texture" field="colorGradient"/></dd>
							<dt>Sort Mode</dt><dd><select field="sortMode"/></dd></dd>
						</dl>
					</div>

					<div class="group" name="Emit">
						<dl>
							<dt>Mode</dt><dd><select field="emitMode"/></dd>
							<dt>Count</dt><dd><input type="range" field="nparts" min="0" max="300" step="1"/></dd>
							<dt>Distance</dt><dd><input type="range" field="emitDist" min="0" max="1000"/></dd>
							<dt>Angle</dt><dd><input type="range" field="emitAngle" min="${-Math.PI/2}" max="${Math.PI}"/></dd>
							<dt>Sync</dt><dd><input type="range" field="emitSync" min="0" max="1"/></dd>
							<dt>Delay</dt><dd><input type="range" field="emitDelay" min="0" max="10"/></dd>
							<dt>Loop</dt><dd><input type="checkbox" field="emitLoop"/></dd>
						</dl>
					</div>

					<div class="group" name="Life">
						<dl>
							<dt>Initial</dt><dd><input type="range" field="life" min="0" max="10"/></dd>
							<dt>Randomness</dt><dd><input type="range" field="lifeRand" min="0" max="1"/></dd>
							<dt>Fade In</dt><dd><input type="range" field="fadeIn" min="0" max="1"/></dd>
							<dt>Fade Out</dt><dd><input type="range" field="fadeOut" min="0" max="1"/></dd>
							<dt>Fade Power</dt><dd><input type="range" field="fadePower" min="0" max="3"/></dd>
						</dl>
					</div>

					<div class="group" name="Speed">
						<dl>
							<dt>Initial</dt><dd><input type="range" field="speed" min="0" max="1000"/></dd>
							<dt>Randomness</dt><dd><input type="range" field="speedRand" min="0" max="1"/></dd>
							<dt>Acceleration</dt><dd><input type="range" field="speedIncr" min="-1" max="1"/></dd>
							<dt>Gravity</dt><dd><input type="range" field="gravity" min="-250" max="250"/></dd>
						</dl>
					</div>

					<div class="group" name="Size">
						<dl>
							<dt>Initial</dt><dd><input type="range" field="size" min="0.01" max="2"/></dd>
							<dt>Randomness</dt><dd><input type="range" field="sizeRand" min="0" max="1"/></dd>
							<dt>Growth</dt><dd><input type="range" field="sizeIncr" min="-1" max="1"/></dd>
						</dl>
					</div>

					<div class="group" name="Rotation">
						<dl>
							<dt>Initial</dt><dd><input type="range" field="rotInit" min="0" max="1"/></dd>
							<dt>Speed</dt><dd><input type="range" field="rotSpeed" min="0" max="20"/></dd>
							<dt>Randomness</dt><dd><input type="range" field="rotSpeedRand" min="0" max="1"/></dd>
							<dt>Auto orient</dt><dd><input type="checkbox" field="rotAuto"/></dd>
						</dl>
					</div>

					<div class="group" name="Animation">
						<dl>
							<dt>Animation Repeat</dt><dd><input type="range" field="animationRepeat" min="0" max="10"/></dd>
							<dt>Frame Division</dt><dd>
								X <input type="number" style="width:30px" field="frameDivisionX" min="1" max="16"/>
								Y <input type="number" style="width:30px" field="frameDivisionY" min="1" max="16"/>
								# <input type="number" style="width:30px" field="frameCount" min="0" max="32"/>
							</dd>
						</dl>
					</div>

				</div>
			</div>
		');

		e.find("h1").contextmenu(function(ev) {
			var groups = @:privateAccess parts.groups;
			var index = groups.indexOf(g);
			function moveIndex(d:Int,history=true) {
				var index = groups.indexOf(g);
				parts.removeGroup(g);
				parts.addGroup(g, index + d);
				if( history ) undo.change(Custom(function(undo) moveIndex(undo ? -d : d,false)));
				initProperties();
			}
			new hide.comp.ContextMenu([
				{ label : "Enable", checked : g.enable, click : function() { g.enable = !g.enable; e.find("[field=enable]").prop("checked", g.enable); } },
				{ label : "MoveUp", enabled : index > 0, click : function() moveIndex(-1) },
				{ label : "MoveDown", enabled : index < groups.length - 1, click : function() moveIndex(1) },
				{ label : "Delete", click : function() { parts.removeGroup(g); e.remove(); } },
			]);
			ev.preventDefault();
		});
		properties.add(e, g);
	}

	function init() {
		parts = new Particles(this, scene.s2d);
		parts.smooth = true;
		parts.load(haxe.Json.parse(sys.io.File.getContent(getPath())));
		initProperties();
		scene.init(props);
		scene.onResize = onResize;
	}

	override function onResize() {
		if( parts == null ) return;
		parts.x = scene.width >> 1;
		parts.y = scene.height >> 1;
		if (background != null) {
			background.setPos(parts.x - background.tile.width / 2, parts.y - background.tile.height / 2);
			background.tile.dx = Std.int(bgPos.x);
			background.tile.dy = Std.int(bgPos.y);
		}
	}

	function initProperties() {

		properties.clear();

		for( g in parts.getGroups() )
			addGroup(g);

		var bgParams = addBackgroundParams();

		var extra = new Element('
			<div class="section">
				<h1>Manage</h1>
				<div class="content">
					<dl>
					<dt></dt><dd><input type="button" class="new" value="New Group"/></dd>
					</dl>
				</div>
			</div>
		');

		extra = properties.add(extra);
		extra.find(".new").click(function(_) {
			var g = parts.addGroup();
			g.name = "Group#" + Lambda.count({ iterator : parts.getGroups });
			addGroup(g);
			bgParams.appendTo(properties.root);
			extra.appendTo(properties.root);
		}, null);
	}

	function addBackgroundParams() {
		var bgParams = new Element('
			<div class="section">
				<h1>Background</h1>
				<div class="content">
					<dl>
						<dt>Texture</dt><dd><input type="texture" class="bgTex"/></dd>
						<dt>X</dt><dd><input type="range" class="bgX" min="-200" max="200"/></dd>
						<dt>Y</dt><dd><input type="range" class="bgY" min="-200" max="200"/></dd>
					</dl>
				</div>
			</div>
		');

		bgParams = properties.add(bgParams);

		var newBg = new hide.comp.TextureSelect(bgParams.find("[class=bgTex]"));
		var newX = bgParams.find("[class=bgX]");
		var newY = bgParams.find("[class=bgY]");

		var props : { ?backgroundPath : String, ?dx : Float, ?dy : Float } = @:privateAccess parts.hideProps;
		if( props == null ) {
			props = {};
			@:privateAccess parts.hideProps = props;
		}
		else {
			if (props.backgroundPath != null) {
				newBg.path = props.backgroundPath;
				var tile = h2d.Tile.fromTexture(scene.loadTexture(state.path, props.backgroundPath));
				background = new h2d.Bitmap(tile);
				scene.s2d.add(background, 0);
				scene.s2d.addChild(parts);
				if (props.dx != null) {
					bgPos.x = props.dx;
					newX.prop("value", props.dx);
				}
				if (props.dy != null) {
					bgPos.y = props.dy;
					newX.prop("value", props.dy);
				}
				onResize();
			}
		}
		newBg.onChange = function() {
			props.backgroundPath = newBg.path;
			if (background != null)
				background.remove();
			if (newBg.value == null)
				background = null;
			else {
				background = new h2d.Bitmap(h2d.Tile.fromTexture(newBg.value));
				scene.s2d.add(background, 0);
				scene.s2d.addChild(parts);
			}
			onResize();
		};


		newX.change(function(_) {
			bgPos.x = newX.prop("value");
			props.dx = newX.prop("value");
			onResize();
		});

		newY.change(function(_) {
			bgPos.y = newY.prop("value");
			props.dy = newY.prop("value");
			onResize();
		});

		return bgParams;
	}

	static var _ = FileTree.registerExtension(Particles2D, ["json.particles2D"], { icon : "snowflake-o", createNew: "Particle 2D" });

}