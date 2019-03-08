package hide.view;

class Particles3D extends FileView {

	var scene : hide.comp.Scene;
	var parts : h3d.parts.GpuParticles;
	var properties : hide.comp.PropsEditor;
	var bounds : h3d.scene.Box;
	var model : h3d.scene.Object;
	var tf : h2d.Text;

	override function getDefaultContent() {
		var p = new h3d.parts.GpuParticles();
		p.addGroup().name = "Default";
		return haxe.io.Bytes.ofString(ide.toJSON(p.save()));
	}

	override function onDisplay() {
		element.html('
			<div class="flex-elt">
				<div class="scene"></div>
				<div class="props"></div>
			</div>
		');
		properties = new hide.comp.PropsEditor(undo, null, element.find(".props"));
		properties.saveDisplayKey = "particles3D";
		scene = new hide.comp.Scene(config, null,element.find(".scene"));
		scene.onReady = init;
		scene.onUpdate = update;
	}

	override function save() {
		sys.io.File.saveContent(getPath(), ide.toJSON(parts.save()));
		super.save();
	}

	function addGroup( g : h3d.parts.GpuParticles.GpuPartGroup ) {
		var e = new Element('
			<div class="section">
				<h1><span>${g.name}</span> &nbsp;<input type="checkbox" field="enable"/></h1>
				<div class="content">

					<div class="group" name="Display">
						<dl>
							<dt>Name</dt><dd><input field="name" onchange="$(this).closest(\'.section\').find(\'>h1 span\').text($(this).val())"/></dd>
							<dt>Texture</dt><dd><input type="texture" field="texture"/></dd>
							<dt>Color Gradient</dt><dd><input type="texture" field="colorGradient"/></dd>
							<dt>Sort</dt><dd><select field="sortMode"></select></dd>
							<dt>3D&nbsp;Transform</dt><dd><input type="checkbox" field="transform3D"/></dd>
							<dt>Relative position</dt><dd><input type="checkbox" field="isRelative"/></dd>
						</dl>
					</div>

					<div class="group material" name="Material">
					</div>

					<div class="group" name="Emit">
						<dl>
							<dt>Mode</dt><dd><select field="emitMode"/></dd>
							<dt>Count</dt><dd><input type="range" field="nparts" min="0" max="1000" step="1"/></dd>
							<dt>Distance</dt><dd><input type="range" field="emitDist" min="0" max="10"/></dd>
							<dt>Angle</dt><dd><input type="range" field="emitAngle" min="${-Math.PI/2}" max="${Math.PI}"/></dd>
							<dt>Sync</dt><dd><input type="range" field="emitSync" min="0" max="1"/></dd>
							<dt>Delay</dt><dd><input type="range" field="emitDelay" min="0" max="10"/></dd>
							<dt>Loop</dt><dd><input type="checkbox" field="emitLoop"/></dd>
							<dt>Border</dt><dd><input type="checkbox" field="emitOnBorder"/></dd>
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
							<dt>Initial</dt><dd><input type="range" field="speed" min="0" max="10"/></dd>
							<dt>Randomness</dt><dd><input type="range" field="speedRand" min="0" max="1"/></dd>
							<dt>Acceleration</dt><dd><input type="range" field="speedIncr" min="-1" max="1"/></dd>
							<dt>Gravity</dt><dd><input type="range" field="gravity" min="-5" max="5"/></dd>
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
							<dt>Speed</dt><dd><input type="range" field="rotSpeed" min="0" max="5"/></dd>
							<dt>Randomness</dt><dd><input type="range" field="rotSpeedRand" min="0" max="1"/></dd>
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
				{ label : "Copy", click : function() setClipboard(g.save()) },
				{ label : "Paste", enabled : hasClipboard(), click : function() {
					var prev = g.save();
					var next = getClipboard();
					g.load(@:privateAccess h3d.parts.GpuParticles.VERSION, next);
					undo.change(Custom(function(undo) {
						g.load(@:privateAccess h3d.parts.GpuParticles.VERSION, undo ? prev : next);
						initProperties();
					}));
					initProperties();
				} },
				{ label : "MoveUp", enabled : index > 0, click : function() moveIndex(-1) },
				{ label : "MoveDown", enabled : index < groups.length - 1, click : function() moveIndex(1) },
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
				}},
			]);
			ev.preventDefault();
		});
		e.find("[field=emitLoop]").change(function(_) parts.currentTime = 0);
		e = properties.add(e, g);
		properties.addMaterial( parts.materials[Lambda.indexOf({ iterator : parts.getGroups }, g)], e.find(".material > .content") );
		return e;
	}

	function init() {
		parts = new h3d.parts.GpuParticles(scene.s3d);
		parts.load(haxe.Json.parse(sys.io.File.getContent(getPath())));
		bounds = new h3d.scene.Box(0x808080, parts.bounds, parts);
		bounds.visible = false;
		initProperties();
		haxe.Timer.delay(function() {
			scene.resetCamera(2);
		}, 0);
		new h3d.scene.CameraController(scene.s3d).loadFromCamera();
		scene.init();

		tf = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		tf.alpha = 0.2;
		tf.x = tf.y = 5;
	}

	function update(dt:Float) {
		tf.text = Math.floor(parts.currentTime)+"."+(Math.floor(Math.abs(parts.currentTime)*10)%10) + "s " + parts.count + " parts";
	}

	function initProperties() {

		properties.clear();

		for( g in parts.getGroups() )
			addGroup(g);

		var props : { ?model : String, ?attach : String, ?anim : String } = @:privateAccess parts.hideProps;
		if( props == null ) {
			props = {};
			@:privateAccess parts.hideProps = props;
		}

		var extra = new Element('
			<div class="section">
				<h1>Manage</h1>
				<div class="content">
					<dl>
					<dt>Model</dt><dd><input type="model" field="model"/></dd>
					<dt class="attach">Attach</dt><dd class="attach"><select field="attach"/></dd>
					<dt class="anim">Anim</dt><dd class="anim"><select field="anim"/></dd>
					<dt>Show Bounds</dt><dd><input type="checkbox" class="bounds"/></dd>
					<dt>Enable Lights</dt><dd><input type="checkbox" class="lights" checked="checked"/></dd>
					<dt></dt><dd><input type="button" class="new" value="New Group"/></dd>
					<dt></dt><dd><input type="button" class="reset" value="Reset Camera"/></dd>
					</dl>
				</div>
			</div>
		');

		var anim = extra.find(".anim select");
		var attach = extra.find(".attach select");

		function syncProps() {

			extra.find(".attach").toggle(props.model != null);
			extra.find(".anim").toggle(props.model != null);

			parts.rebuild();

			if( props.anim == '' )
				props.anim = null;
			if( props.attach == '' )
				props.attach = '';

			if( model != null ) {
				model.remove();
				model = null;
			}

			if( props.model == null ) {
				props.anim = null;
				props.attach = null;
				anim.val('');
				attach.val('');
			} else {
				try {
					model = scene.loadModel(props.model);
				} catch( e : Dynamic ) {
					ide.error(e);
					props.model = null;
				}
				if( model != null && props.anim != null ) {
					try {
						var anim = scene.loadAnimation(props.anim);
						model.playAnimation(anim);
					} catch( e : Dynamic ) {
						ide.error(e);
						props.anim = null;
					}
				}
				if( model != null ) {
					scene.s3d.addChild(model);
					scene.init(model);

					var prev = attach.val();
					attach.empty();
					function addRec(o:h3d.scene.Object) {
						if( o.name != null )
							new Element('<option value="${o.name}" ${o.name == prev ? "selected='selected'" : ""}>${o.name}</option>').appendTo(attach);
						var s = Std.instance(o, h3d.scene.Skin);
						if( s != null )
							for( j in s.getSkinData().allJoints )
								new Element('<option value="${j.name}" ${j.name == prev ? "selected='selected'" : ""}>${j.name}</option>').appendTo(attach);
						for( s in o )
							addRec(s);
					}
					addRec(model);

					var prev = anim.val();
					anim.empty();
					var anims = scene.listAnims(props.model);
					new Element('<option value="">-- none --</option>').appendTo(anim);
					for( a in anims ) {
						var a = ide.makeRelative(a);
						var name = scene.animationName(a);
						new Element('<option value="$a" ${a == prev ? "selected='selected'" : ""}>$name</option>').appendTo(anim);
					}
					if( anims.length == 0 )
						extra.find(".anim").hide();
				}
			}

			var parent : h3d.scene.Object = null;
			if( model != null ) {
				parent = model;
				if( props.attach != null )
					parent = model.getObjectByName(props.attach);
			}
			parts.follow = parent;
			ide.cleanObject(props);
		}
		syncProps();
		extra = properties.add(extra, props, function(_) syncProps());

		extra.find(".bounds").change(function(e) bounds.visible = e.getThis().prop("checked"));
		var defAmbient = scene.s3d.lightSystem.ambientLight.clone();
		extra.find(".lights").change(function(e) {
			var ls = scene.s3d.lightSystem;
			var lfw = Std.instance(ls, h3d.scene.fwd.LightSystem);
			var enable = e.getThis().prop("checked");
			if( lfw != null ) lfw.maxLightsPerObject = enable ? 6 : 0;
			if( enable ) ls.ambientLight.load(defAmbient) else ls.ambientLight.set(1, 1, 1);
		});
		extra.find(".new").click(function(_) {
			var g = parts.addGroup();
			g.name = "Group#" + Lambda.count({ iterator : parts.getGroups });
			addGroup(g);
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

	static var _ = FileTree.registerExtension(Particles3D, ["json.particles3D"], { icon : "snowflake-o", createNew: "Particle 3D" });

}