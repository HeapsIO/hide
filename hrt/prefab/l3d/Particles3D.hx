package hrt.prefab.l3d;

// NOTE(ces) : Not Tested

class Particles3D extends Object3D {

	@:s var data : Any;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
	}

	override function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
		var parts = new h3d.parts.GpuParticles(parent3d);
		if( source != null ) {
			var src = null;
			try {
				src = hxd.res.Loader.currentInstance.load(source).toText();
			} catch(e : Dynamic) { }
			if(src != null)
				parts.load(haxe.Json.parse(src));
		}
		if( data != null )
			parts.load(data);
		else if( !parts.getGroups().hasNext() )
			parts.addGroup().isRelative = true;
		return parts;
	}

	#if editor

	override function setSelected(b:Bool):Bool {
		return true;
	}

	override function edit(ectx:hide.prefab.EditContext) {
		super.edit(ectx);
		if(source == null) {
			var parts = cast(local3d,h3d.parts.GpuParticles);

			function undo(f) {
				ectx.properties.undo.change(Custom(function(redo) { f(redo); data = parts.save(); }));
				data = parts.save();
			}

			function addGroup( g : h3d.parts.GpuParticles.GpuPartGroup ) {
				var e = new hide.Element('
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
									<dt>Attach to cam</dt><dd><input type="checkbox" field="attachToCam"/></dd>
									<dt>Distance to cam</dt><dd><input type="range" min="0" max="10" field="distanceToCam"/></dd>
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
						if( history ) undo(function(undo) moveIndex(undo ? -d : d,false));
						ectx.rebuildProperties();
					}
					hide.comp.ContextMenu.createFromEvent(cast ev,[
						{ label : "Enable", checked : g.enable, click : function() { g.enable = !g.enable; e.find("[field=enable]").prop("checked", g.enable); } },
						{ label : "Copy", click : function() ectx.ide.setClipboard(g.save()) },
						{ label : "Paste", enabled : ectx.ide.getClipboard() != null, click : function() {
							var prev = g.save();
							var next = ectx.ide.getClipboard();
							g.load(@:privateAccess h3d.parts.GpuParticles.VERSION, next);
							undo(function(undo) {
								g.load(@:privateAccess h3d.parts.GpuParticles.VERSION, undo ? prev : next);
								ectx.rebuildProperties();
							});
							ectx.rebuildProperties();
						} },
						{ label : "MoveUp", enabled : index > 0, click : function() moveIndex(-1) },
						{ label : "MoveDown", enabled : index < groups.length - 1, click : function() moveIndex(1) },
						{ label : "Delete", click : function() {
							parts.removeGroup(g);
							e.remove();
							undo(function(undo) {
								if( undo )
									parts.addGroup(g, index);
								else
									parts.removeGroup(g);
								ectx.rebuildProperties();
							});
						}},
					]);
					ev.preventDefault();
				});
				e.find("[field=emitLoop]").change(function(_) parts.currentTime = 0);
				e = ectx.properties.add(e, g, function(_) {
					data = parts.save();
				});
				ectx.properties.addMaterial( parts.materials[Lambda.indexOf({ iterator : parts.getGroups }, g)], e.find(".material > .content") );
				return e;
			}

			for( g in parts.getGroups() )
				addGroup(g);

			var extra = new hide.Element('
				<div class="section">
					<h1>Manage</h1>
					<div class="content">
						<dl>
						<dt></dt><dd><input type="button" class="new" value="New Group"/></dd>
						</dl>
					</div>
				</div>
			');

			extra.find(".new").click(function(_) {
				var g = parts.addGroup();
				g.name = "Group#" + Lambda.count({ iterator : parts.getGroups });
				g.isRelative = true;
				addGroup(g);
				ectx.rebuildProperties();
				undo(function(undo) {
					if( undo )
						parts.removeGroup(g);
					else
						parts.addGroup(g);
					ectx.rebuildProperties();
				});
			}, null);
			ectx.properties.add(extra);
		}
		else {
			var element = new hide.Element('
			<div class="group" name="Reference">
				<dl>
					<dt>Reference</dt><dd><input type="fileselect" extensions="json" field="source"/></dd>
				</dl>
			</div>');
			ectx.properties.add(element, this, function(pname) {
				ectx.onChange(this, pname);
				if(pname == "source")
					ectx.rebuildPrefab(this);
			});
		}
	}
	#end

	static var _ = Prefab.register("particles3D", Particles3D);

}