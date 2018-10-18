package hide.view;
import h2d.Graphics in Graphics;
import h2d.Particles.ParticleGroup in ParticleGroup;

class Particles2D extends FileView {

	var scene : hide.comp.Scene;
	var parts : h2d.Particles;
	var partsProps : { ?backgroundPath : String, ?dx : Int, ?dy : Int };

	var uiProps : { showBounds : Bool };
	var debugBounds : Array<Graphics> = [];
	var background : h2d.Bitmap = null;
	var properties : hide.comp.PropsEditor;

	override function getDefaultContent() {
		var p = new h2d.Particles(null);
		p.addGroup().name = "Default";
		return haxe.io.Bytes.ofString(ide.toJSON(p.save()));
	}

	override function onDisplay() {
		element.html('
			<div class="flex">
				<div class="scene"></div>
				<div class="props"></div>
			</div>
		');
		properties = new hide.comp.PropsEditor(undo, null, element.find(".props"));
		properties.saveDisplayKey = "particles2D";
		scene = new hide.comp.Scene(config, null,element.find(".scene"));
		scene.onReady = init;
	}

	override function save() {
		sys.io.File.saveContent(getPath(), ide.toJSON(parts.save()));
	}

	function init() {
		parts = new h2d.Particles(scene.s2d);
		parts.smooth = true;
		parts.load(haxe.Json.parse(sys.io.File.getContent(getPath())));
		uiProps = { showBounds: false };

		initProperties();
		scene.init();
		scene.onUpdate = update;
		scene.onResize = onResize;
	}

	override function onResize() {
		if (parts != null) {
			parts.x = scene.width >> 1;
			parts.y = scene.height >> 1;
		}
		if (background != null) {
			background.setPosition(parts.x - background.tile.width / 2, parts.y - background.tile.height / 2);
			background.tile.dx = partsProps.dx;
			background.tile.dy = partsProps.dy;
		}
	}

	function addGroup( g : ParticleGroup ) {
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
							<dt></dt><dd>
								X <input type="number" style="width:59px" field="dx"/>
								Y <input type="number" style="width:59px" field="dy"/>
							</dd>
							<dt>Count</dt><dd><input type="range" field="nparts" min="0" max="300" step="1"/></dd>
							<dt>Distance</dt><dd><input type="range" field="emitDist" min="0" max="1000" step="1"/></dd>
							<dt>Distance Y</dt><dd><input type="range" field="emitDistY" min="0" max="1000" step="1"/></dd>
							<dt>Angle</dt><dd><input type="range" field="emitAngle" min="-1" max="1" step="0.1"/></dd>
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
							<dt>Gravity</dt><dd><input type="range" field="gravity" min="-500" max="500" step="1"/></dd>
							<dt>Gravity Angle</dt><dd><input type="range" field="gravityAngle" min="0" max="1" step="0.1"/></dd>
						</dl>
					</div>

					<div class="group" name="Size">
						<dl>
							<dt>Initial</dt><dd><input type="range" field="size" min="0.01" max="2"/></dd>
							<dt>Randomness</dt><dd><input type="range" field="sizeRand" min="0" max="1"/></dd>
							<dt>Growth</dt><dd><input type="range" field="sizeIncr" min="-1" max="1"/></dd>
							<dt></dt><dd>
								Grow u <input type="checkbox" field="incrX"/>
								Grow v <input type="checkbox" field="incrY"/>
							</dd>
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
				{ label : "Enable", checked : g.enable, click : function() {
					g.enable = !g.enable;
					e.find("[field=enable]").prop("checked", g.enable);
				} },
				{ label : "Copy", click : function() setClipboard(g.save()) },
				{ label : "Paste", enabled : hasClipboard(), click : function() {
					var prev = g.save();
					var next = getClipboard();
					g.load(@:privateAccess h2d.Particles.VERSION, next);
					undo.change(Custom(function(undo) {
						g.load(@:privateAccess h2d.Particles.VERSION, undo ? prev : next);
						initProperties();
					}));
					initProperties();
				} },
				{ label : "MoveUp", enabled : index > 0, click : function() { moveIndex( -1); } },
				{ label : "MoveDown", enabled : index < groups.length - 1, click : function() { moveIndex(1); } },
				{ label : "Delete", click : function() {
					parts.removeGroup(g);
					e.remove();
					undo.change(Custom(function(undo) {
						if( undo )
							parts.addGroup(g, index);
						else
							parts.removeGroup(g);
						initProperties();
					}));
				} },
			]);
			ev.preventDefault();
		});
		properties.add(e, g);
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
					<dt>Show bounds</dt><dd><input type="checkbox" field="showBounds"/></dt>
					</dl>
				</div>
			</div>
		');

		extra = properties.add(extra, uiProps);
		extra.find(".new").click(function(_) {
			var g = parts.addGroup();
			g.name = "Group#" + Lambda.count({ iterator : parts.getGroups });
			addGroup(g);
			bgParams.appendTo(properties.element);
			extra.appendTo(properties.element);
			undo.change(Custom(function(undo) {
				if( undo )
					parts.removeGroup(g);
				else
					parts.addGroup(g);
				initProperties();
			}));
		}, null);
	}

	function addBackgroundParams() {
		partsProps = @:privateAccess parts.hideProps;
		if( partsProps == null ) {
			partsProps = {dx: 0, dy: 0};
			@:privateAccess parts.hideProps = partsProps;
		}

		function createBackground() {
			if (partsProps.backgroundPath != null) {
				var tile = h2d.Tile.fromTexture(scene.loadTexture(state.path, partsProps.backgroundPath));
				background = new h2d.Bitmap(tile);
				scene.s2d.add(background, 0);
				scene.s2d.addChild(parts);
			}
		}
		createBackground();

		var bgParams = new Element('
			<div class="section">
				<h1>Background</h1>
				<div class="content">
					<dl>
						<dt>Texture</dt><dd><input type="texturepath" field="backgroundPath"/></dd>
						<dt>X</dt><dd><input type="range" field="dx" min="-500" max="500" step="1"/></dd>
						<dt>Y</dt><dd><input type="range" field="dy" min="-500" max="500" step="1"/></dd>
					</dl>
				</div>
			</div>
		');

		function onChange(propName) {
			if (propName == "backgroundPath") {
				if (background != null) {
					background.remove();
					background = null;
				}

				createBackground();
			}

			onResize();
		}

		bgParams = properties.add(bgParams, partsProps, onChange);

		return bgParams;
	}

	function update(dt : Float) {
		for (l in debugBounds)
			l.remove();
		debugBounds = [];
		if (uiProps.showBounds) {
			for (g in parts.getGroups())
				drawBounds(g);
		}
	}

	function drawBounds(pGroup : ParticleGroup) {
		var g = new Graphics(parts.parent);
		g.lineStyle(3, getBoundsColor(pGroup), 1.);
		debugBounds.push(g);
		var x = parts.x + pGroup.dx;
		var y = parts.y + pGroup.dy;

		switch(pGroup.emitMode) {
			case Point:
				g.drawCircle(x, y, pGroup.emitDist);

			case Cone:
				var angle = Math.PI * pGroup.emitAngle;
				var startAngle : Float = (Math.PI - angle) * 0.5;
				if (angle < 0) startAngle -= Math.PI;
				g.drawPie(x, y, pGroup.emitDist, startAngle, angle);

			case Box:
				var w = pGroup.emitDist;
				var h = pGroup.emitDistY;
				g.drawRect(x - w, y - h, w * 2, h * 2);
			case Direction:
				var angle = Math.PI * pGroup.emitAngle;
				g.moveTo(x, y);
				g.lineTo(x + Math.cos(angle) * pGroup.emitDist, y + Math.sin(angle) * pGroup.emitDist);
		}
	}

	function getBoundsColor(pGroup : ParticleGroup) : Int {
		return 1000 + @:privateAccess parts.groups.indexOf(pGroup) * 30000;
	}

	static var _ = FileTree.registerExtension(Particles2D, ["json.particles2D"], { icon : "snowflake-o", createNew: "Particle 2D" });

}