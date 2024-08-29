package hrt.prefab.l3d;

class PrefabSpray extends Spray {

	#if editor

	var PREFAB_SPRAY_CONFIG_FILE = "prefabSprayProps.json";
	var PREFAB_SPRAY_CONFIG_PATH(get, null) : String;
	function get_PREFAB_SPRAY_CONFIG_PATH() {
		return hide.Ide.inst.resourceDir + "/" + PREFAB_SPRAY_CONFIG_FILE;
	}

	override function save() : Dynamic {
		clearPreview();
		return super.save();
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "paint-brush", name : "PrefabSpray", hideChildren : p -> return Std.isOfType(p, Object3D) };
	}

	override function edit( ectx : hide.prefab.EditContext ) {

		invParent = getAbsPos().clone();
		invParent.invert();

		if (defaultConfig == null) defaultConfig = getDefaultConfig();
		if (sceneEditor == null) {
			allSetGroups = if( sys.FileSystem.exists(PREFAB_SPRAY_CONFIG_PATH) )
				try hide.Ide.inst.parseJSON(sys.io.File.getContent(PREFAB_SPRAY_CONFIG_PATH)) catch( e : Dynamic ) throw e+" (in "+PREFAB_SPRAY_CONFIG_PATH+")";
			else
				[];
		}
		sceneEditor = ectx.scene.editor;

		var props = new hide.Element('<div class="group" name="Prefabs"></div>');

		var preset = new hide.Element('<div class="btn-list" align="center" ></div>').appendTo(props);

		var presetChoice = new hide.Element('<div align="center" ></div>').appendTo(preset);

		var selectPresetElt = new hide.Element('<select style="width: 150px" ></select>').appendTo(presetChoice);

		function updateSelectPreset() {
			selectPresetElt.empty();
			var allSetGroupsName = [null];
			for (g in allSetGroups) allSetGroupsName.push(g.name);
			for (presetValue in allSetGroupsName) {
				var selected = (currentPresetName == presetValue);
				var presetName = (presetValue == null) ? "No preset" : presetValue;
				selectPresetElt.append(new hide.Element('<option ${(selected) ? 'selected=selected' : ''} value="${presetValue}"" >${presetName}</option>'));
			}
			selectPresetElt.append(new hide.Element('<option value="#add">-- Add preset --</option>'));
		}
		updateSelectPreset();

		var editPresetName = new hide.Element('<button>Edit</button>').appendTo(presetChoice);
		var deletePreset = new hide.Element('<button>Del.</button>').appendTo(presetChoice);

		var setsList = new hide.Element('<div align="center" ></div>').appendTo(preset);

		selectElement = new hide.Element('<select multiple size="6" style="width: 300px" ></select>').appendTo(props);
		function createPrefabElement(path: String) {
			var elt = new hide.Element('<option value="$path">${extractItemName(path)}</option>');
			elt.contextmenu(function(e) {
				e.preventDefault();
				new hide.comp.ContextMenu([
					{ label : "Swap Prefab", click : function() hide.Ide.inst.chooseFile(["prefab", "l3d"] , function (newPath) {
						removeSourcePath(elt.val());
						addSourcePath(newPath);
						for (child in children) {
							var prefab = child.to(hrt.prefab.Object3D);
							if (prefab != null && prefab.source == elt.val()) {
								prefab.source = newPath;
							}
						}
						elt.val(newPath);
						elt.html(extractItemName(newPath));
						sceneEditor.queueRebuild(this);
						undo.change(Custom(function(undo) {
							if(undo) {
								removeSourcePath(newPath);
								addSourcePath(path);
								for (child in children) {
									var prefab = child.to(hrt.prefab.Object3D);
									if (prefab != null && prefab.source == elt.val()) {
										prefab.source = path;
									}
								}
								elt.val(path);
								elt.html(extractItemName(path));
								sceneEditor.queueRebuild(this);
							}
							else {
								removeSourcePath(elt.val());
								addSourcePath(newPath);
								for (child in children) {
									var prefab = child.to(hrt.prefab.Object3D);
									if (prefab != null && prefab.source == elt.val()) {
										prefab.source = newPath;
									}
								}
								elt.val(newPath);
								elt.html(extractItemName(newPath));
								sceneEditor.queueRebuild(this);
							}
						}));
					}) },
				]);
				return false;
			});
			selectElement.append(elt);
		}

		function onChangeSet() {
			selectElement.empty();
			for (m in currentSources.copy()) {
				var path : String = null;
				if (Std.isOfType(m, String)) { // retro-compatibility
					path = cast m;
					currentSources.remove(m);
					addSourcePath(path);
				} else {
					path = m.path;
				}
				createPrefabElement(path);
			}
			updateConfig();
		}

		var selectedSetElt : hide.Element = null;
		function setSet(set: Spray.Set, setElt : hide.Element) {
			currentSetName = (set != null) ? set.name : null;
			currentSet = set;
			if (selectedSetElt != null)
				selectedSetElt.css("border-color", "#444444");
			selectedSetElt = setElt;
			if (selectedSetElt != null)
				selectedSetElt.css("border-color", "green");
			onChangeSet();
		}

		function onChangePreset(init : Bool = false) {
			if (currentPresetName != null) {
				var tmp = allSetGroups.filter(g -> g.name == currentPresetName);
				if (tmp.length > 0)
					setGroup = tmp[0];
				else
					return;
			} else {
				setGroup = null;
				setSet(null, null);
			}
			setsList.empty();
			if (setGroup != null) {
				if (!init)
					currentSetName = setGroup.sets[0].name;
				for (s in setGroup.sets) {
					var setElt = new hide.Element('<div style="margin: 5px; padding: 10px; border: solid 1px #444444; display: inline-block;" ></div>').appendTo(setsList);
					var inputSetElt = new hide.Element('<input type="text" style="width: 75px; border: none; padding: 0; text-align: center;" value="${s.name}" />').appendTo(setElt);
					setElt.on("click", function(e) {
						setSet(s, setElt);
					});
					inputSetElt.on("change", function(e) {
						var value : String = inputSetElt.val();
						if (value != null && value.length > 0) {
							s.name = value;
						} else {
							inputSetElt.val(s.name);
						}
					});
					if (s.name == currentSetName) setSet(s, setElt);
				}
				var addSet = new hide.Element('<div style="margin: 5px; padding: 10px; border: solid 1px #444444; display: inline-block;" >Add set</div>').appendTo(setsList);
				addSet.on("click", function(e) {
					var name = hide.Ide.inst.ask("Name set:");
					if (name == null || name.length == 0) return;
					setGroup.sets.push({
						name: name,
						sources: [],
						config: getDefaultConfig()
					});
					currentSetName = name;
					onChangePreset();
				});
			}
		}
		selectPresetElt.on("change", function() {
			var value = selectPresetElt.val();
			if (value == "null") value = null;
			if (value == "#add") {
				var name = hide.Ide.inst.ask("Name preset:");
				var groups = allSetGroups.filter(g -> g.name == name);
				if (name == null || name.length == 0 || groups.length > 0)
					return;
				allSetGroups.push({
					name: name,
					sets: [{
						name: "SetName",
						sources: [],
						config: getDefaultConfig()
					}]
				});
				currentPresetName = name;
				currentSetName = "SetName";
				updateSelectPreset();
				onChangePreset();
				return;
			}
			currentPresetName = value;
			onChangePreset();
		});

		editPresetName.on("click", function() {
			if (currentPresetName == null) return;
			var preset = allSetGroups.filter(s -> s.name == currentPresetName);
			if (preset.length == 0) return;
			var name = hide.Ide.inst.ask("New name preset:");
			if (name == null || name.length == 0) return;
			preset[0].name = name;
			currentPresetName = name;
			updateSelectPreset();
			onChangePreset();
		});

		deletePreset.on("click", function() {
			if (currentPresetName == null) return;
			var preset = allSetGroups.filter(s -> s.name == currentPresetName);
			if (preset.length == 0) return;
			if(hide.Ide.inst.confirm("Are-you sure ?")) {
				allSetGroups.remove(preset[0]);
				currentPresetName = null;
				currentSetName = null;
				updateSelectPreset();
				onChangePreset();
			}
		});

		onChangePreset(true);

		var options = new hide.Element('
		<div>
			<div class="btn-list" align="center">
				<input type="button" value="Select all" id="select"/>
				<input type="button" value="Add" id="add"/>
				<input type="button" value="Remove" id="remove"/>
				<input type="button" value="Remove all prefabs" id="clean"/>
				<input type="button" value="Set to Ground" id="toground"/>
			</div>
			<p align="center">
				<label><input type="checkbox" id="repeatPrefab" style="margin-right: 5px;"/> Don\'t repeat same prefab in a row</label>
			</p>
			<p>
				<b><i>
				Hold down SHIFT to remove prefabs
				<br/>Push R to randomize preview
			</p>
			<p align="center">
				<label><input type="checkbox" id="enableBrush" style="margin-right: 5px;"/> Enable Brush</label>
			</p>

		</div>
		').appendTo(props);

		var repeat = options.find("#repeatPrefab");
		repeat.on("change", function() {
			currentConfig.dontRepeatItem = repeat.is(":checked");
		}).prop("checked", currentConfig.dontRepeatItem);

		var enableBrush = options.find("#enableBrush");
		enableBrush.on("change", function() {
			currentConfig.enableBrush = enableBrush.is(":checked");
			sceneEditor.setLock([this], currentConfig.enableBrush, false);
			removeInteractiveBrush();
			if (currentConfig.enableBrush)
				createInteractiveBrush(ectx);
			else {
				interactive.cancelEvents = true;
			}

		}).prop("checked", currentConfig.enableBrush);

		options.find("#select").click(function(_) {
			var options = selectElement.children().elements();
			for (opt in options) {
				opt.prop("selected", true);
			}
		});
		options.find("#add").click(function(_) {
			hide.Ide.inst.chooseFiles(["prefab", "l3d"], function(paths) {
				for( path in paths ) {
					addSourcePath(path);
					createPrefabElement(path);
				}
			});
		});

		options.find("#toground").click(function(_) {
			var mso = cast(local3d, Spray.SprayObject);
			undo.change(Custom(function(undo) {
			}));
			for( c in this.children ) {
				var obj = c.to(Object3D);
				if( obj == null ) continue;
				setGroundPos(obj);
				obj.applyTransform();
				wasEdited = true;
			}
			mso.redraw();
		});

		options.find("#remove").click(function(_) {
			var options = selectElement.children().elements();
			for (opt in options) {
				if (opt.prop("selected")) {
					removeSourcePath(opt.val());
					opt.remove();
				}
			}
		});
		options.find("#clean").click(function(_) {
			if (hide.Ide.inst.confirm("Are you sure to remove all prefabs for this PrefabSpray ?")) {
				var prefabs = [];
				for( c in children ) {
					prefabs.push(c);
				}
				sceneEditor.deleteElements(prefabs);
				cast(local3d, Spray.SprayObject).redraw();
			}
		});


		ectx.properties.add(props, this, function(pname) {});

		var optionsGroup = new hide.Element('<div class="group" id="groupConfig" name="Options"><dl></dl></div>');
		optionsGroup.append(hide.comp.PropsEditor.makePropsList([
				{ name: "density", t: PInt(1, 25), def: currentConfig.density },
				{ name: "step", t: PFloat(0, 50), def: currentConfig.step },
				{ name: "densityOffset", t: PInt(0, 10), def: currentConfig.densityOffset },
				{ name: "radius", t: PFloat(0, 50), def: currentConfig.radius },
				{ name: "deleteRadius", t: PFloat(0, 50), def: currentConfig.deleteRadius },
				{ name: "scale", t: PFloat(0, 10), def: currentConfig.scale },
				{ name: "scaleOffset", t: PFloat(0, 1), def: currentConfig.scaleOffset },
				{ name: "rotation", t: PFloat(0, 180), def: currentConfig.rotation },
				{ name: "rotationOffset", t: PFloat(0, 30), def: currentConfig.rotationOffset },
				{ name: "zOffset", t: PFloat(0, 10), def: currentConfig.zOffset },
				{ name: "orientTerrain", t: PFloat(0, 1), def: currentConfig.orientTerrain },
				{ name: "tiltAmount", t: PFloat(0, 1), def: currentConfig.tiltAmount },
			]));
		ectx.properties.add(optionsGroup, this, function(pname) {
			var value = sceneEditor.properties.element.find("input[field="+ pname + "]").val();
			Reflect.setField(currentConfig, pname, Std.parseFloat(value));
		});

		sceneEditor.setLock([this], currentConfig.enableBrush, false);
		removeInteractiveBrush();
		if (currentConfig.enableBrush)
			createInteractiveBrush(ectx);
		super.edit(ectx);
	}

	function updateConfig() {
		var CONFIG = currentConfig;
		var defaultConfig = getDefaultConfig();
		var fields = Reflect.fields(defaultConfig);
		for (fieldName in fields) {
			var fieldValue = Reflect.field(CONFIG, fieldName);
			if (fieldValue == null) {
				fieldValue = Reflect.field(defaultConfig, fieldName);
				Reflect.setField(CONFIG, fieldName, fieldValue);
			}
			var input = sceneEditor.properties.element.find("input[field="+ fieldName + "]");
			input.val(fieldValue);
			input.change();
		}

		sceneEditor.properties.element.find("#repeatPrefab").prop("checked", CONFIG.dontRepeatItem);
	}

	override function flatten<T:Prefab>( ?cl : Class<T>, ?arr: Array<T> ) : Array<T> {
		return flattenSpray(cl, arr);
	}

	override function addSourcePath(path : String) {
		var source = { path: path, isRef : true };
		if (currentSources.filter(p -> p.path == path).length == 0)
			currentSources.push(source);
	}

	#end

	static var _ = Prefab.register("prefabSpray", PrefabSpray);

}