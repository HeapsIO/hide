package hrt.animgraph.nodes;

class BlendPerBone extends AnimNode {
	@:input var a: AnimNode;
	@:input var b: AnimNode;

	@:s var targetBone : String = "Bip001 Spine1";

	override function getBones(ctx: hrt.animgraph.nodes.AnimNode.GetBoneContext) : Map<String, Int> {
		var map = super.getBones(ctx);

		for (bone => id in map.copy()) {
			var jointObject = Std.downcast(ctx.targetObject.getObjectByName(bone), h3d.scene.Skin.Joint);
			if (jointObject == null)
				continue;
			var skin = jointObject.skin.getSkinData();
			var joint = skin.namedJoints.get(jointObject.name);
			var found = false;
			while (joint != null) {
				if (joint.name == targetBone) {
					found = true;
					break;
				}
				joint = joint.parent;
			}

			// disable the bone in the first or second animation
			var inputId = found ? 0 : 1;
			boneIdToAnimInputBone[getInputBoneId(id, 1-inputId)] = -1;
			if (boneIdToAnimInputBone[getInputBoneId(id, inputId)] == -1) {
				map.remove(bone);
			}
		}
		return map;
	}

	override function getBoneTransform(boneId: Int, outMatrix: h3d.Matrix, ctx: AnimNode.GetBoneTransformContext) : Void {
		for (animId in 0...2) {

			var animBoneId = boneIdToAnimInputBone[getInputBoneId(boneId, animId)];
			if (animBoneId == -1)
				continue;
			var anim = animId == 0 ? a : b;
			if (anim == null) {
				continue;
			}
			anim.getBoneTransform(animBoneId, outMatrix, ctx);
			break;
		}
	}

	override function setupAnimEvents() {
		a.onEvent = (name:String) -> {
			onEvent(name);
		}
		b.onEvent = (name:String) -> {
			onEvent(name);
		}
	}

	#if editor
	override function getPropertiesHTML(width:Float):Array<hide.Element> {
		var arr =  super.getPropertiesHTML(width);

		var wrapper = new hide.Element("<div></div>");

		var button = new hide.comp.Button(wrapper, {hasDropdown: true});
		button.label = targetBone;

		button.onClick = () -> {
			var model = @:privateAccess getAnimEditor().scenePreview.prefab.findFirstLocal3d();
			if (model == null)
				return;

			var skins = model.findAll((o) -> Std.downcast(o, h3d.scene.Skin));

			var menu : Array<hide.comp.ContextMenu.MenuItem> = [];

			function gatherJoints(joint: h3d.anim.Skin.Joint, arr: Array<hide.comp.ContextMenu.MenuItem>) {
				var subList : Array<hide.comp.ContextMenu.MenuItem> = [];
				for (sub in joint.subs) {
					gatherJoints(sub, subList);
				}
				arr.push({
					label: joint.name,
					menu: subList.length > 0 ? subList : null,
					click: () -> {targetBone = joint.name; getAnimEditor().refreshPreview(); editor.refreshBox(this.id);},
				});
			}

			for (skin in skins) {
				var item : hide.comp.ContextMenu.MenuItem = {label: skin.name};

				var skinData =skin.getSkinData();
				var sub : Array<hide.comp.ContextMenu.MenuItem> = [];
				for (root in skinData.rootJoints) {
					gatherJoints(root, sub);
				}

				menu.push({
					label: skin.name,
					menu: sub,
				});
			}

			hide.comp.ContextMenu.createDropdown(button.element.get(0), menu, {flat: true});
		};

		wrapper.height(24);
		arr.push(wrapper);
		return arr;
	}
	#end
}