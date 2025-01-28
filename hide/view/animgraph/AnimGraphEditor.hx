package hide.view.animgraph;
using Lambda;
import hide.view.GraphInterface;
import hrt.animgraph.*;

@:structInit
@:build(hrt.prefab.Macros.buildSerializable())
class AnimGraphEditorPreviewState {
    @:s public var providerIndex: Int = 0;
}

@:access(hrt.animgraph.AnimGraph)
@:access(hrt.animgraph.AnimGraphInstance)
@:access(hrt.animgraph.Node)
class AnimGraphEditor extends GenericGraphEditor {

    var animGraph : hrt.animgraph.AnimGraph;
    public var previewPrefab : hrt.prefab.Prefab;

    var parametersList : hide.comp.FancyArray<hrt.animgraph.AnimGraph.Parameter>;
    var previewAnimation : AnimGraphInstance = null;

    var previewNode : hrt.animgraph.nodes.AnimNode = null;
    var queuedPreview : hrt.animgraph.nodes.AnimNode = null;

    var previewState: AnimGraphEditorPreviewState;

    override function reloadView() {
        loadPreviewState();

        previewNode = null;
        animGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);

        if (animGraph.animFolder == null) {
            element.html('');
            element.append(createChooseFolderPrompt(new haxe.io.Path(this.state.path).dir, (path: String) -> {
                animGraph.animFolder = path;
                save();
                reloadView();
            }));
            return;
        }

        super.reloadView();

        var parameters = new Element("<graph-parameters></graph-parameters>").appendTo(propertiesContainer);
        new Element("<h1>Parameters</h1>").appendTo(parameters);
        var addParameterBtn = new Element("<button>Add Parameter</button>").appendTo(parameters);

        addParameterBtn.click((e) -> {
            addParameter();
        });

        parametersList = new hide.comp.FancyArray<hrt.animgraph.AnimGraph.Parameter>(parameters, "Parameters", saveDisplayKey);
        parametersList.getItems = () -> animGraph.parameters;
        parametersList.getItemName = (param) -> param.name;
        parametersList.setItemName = (param, name) -> {
            var prev = param.name;
            param.name = name;
            undo.change(Field(param, "name", prev), () ->  {
                var toRefresh = animGraph.nodes.filter((n) -> Std.downcast(n, hrt.animgraph.nodes.FloatParameter)?.parameter == param);
                for (node in toRefresh) {
                    graphEditor.refreshBox(node.id);
                }
                parametersList.refresh();
            });
            var toRefresh = animGraph.nodes.filter((n) -> Std.downcast(n, hrt.animgraph.nodes.FloatParameter)?.parameter == param);
            for (node in toRefresh) {
                graphEditor.refreshBox(node.id);
            }
        }
        parametersList.reorderItem = (oldIndex: Int, newIndex: Int) -> {
            execMoveParameterTo(oldIndex, newIndex);
        }
        parametersList.removeItem = (index: Int) -> {
            execRemoveParam(index);
        }
        parametersList.getItemContent = (param: hrt.animgraph.AnimGraph.Parameter) -> {
            if (previewAnimation != null) {
                var props = new Element("<ul>");
                var slider = new Element('<li><dd>Preview</dd><input type="range" min="-1.0" max="1.0" step="0.01" value="${param.runtimeValue}"></input></li>').appendTo(props).find("input");
                var range = new hide.comp.Range(null,slider);

                range.setOnChangeUndo(undo, () -> param.runtimeValue, (v:Float) -> {
                    param.runtimeValue = v;
                    var runtimeParam = previewAnimation.parameterMap.get(param.name);
                    if (runtimeParam != null) {
                        runtimeParam.runtimeValue = param.runtimeValue;
                    }
                });

                var def = new Element('<li><dd>Default</dd><input type="range" min="-1.0" max="1.0" step="0.01" value="${param.defaultValue}"></input></li>').appendTo(props).find("input");
                var range = new hide.comp.Range(null,def);
                range.setOnChangeUndo(undo, () -> param.defaultValue, (v:Float) -> param.defaultValue = v);
                return props;
            }
            return null;
        }

        refreshPamamList();

        var dl = new Element("<dl></dl>").appendTo(propertiesContainer);
        addAnimSetSelector(dl, {animDirectory: animGraph.animFolder, assetPath: state.path}, undo, () -> previewState.providerIndex, (i: Int) -> {
			previewState.providerIndex = i;
            savePreviewState();
			refreshPreview();
		});


        new AnimList(propertiesContainer, null, getAnims(scenePreview, {animDirectory: animGraph.animFolder, assetPath: state.path}));

        graphEditor.element.get(0).addEventListener("dragover", (e: js.html.DragEvent) -> {
            if (e.dataTransfer.types.contains(parametersList.getDragKeyName()))
                e.preventDefault(); // prevent default to allow drop

            if (e.dataTransfer.types.contains(AnimList.dragEventKey))
                e.preventDefault();
        });

        graphEditor.element.get(0).addEventListener("drop", (e: js.html.DragEvent) -> {
            var posCursor = new h2d.col.Point(graphEditor.lX(e.clientX - 25), graphEditor.lY(e.clientY - 10));

            // Handle drag from Parameters list


            var paramIndex = Std.parseInt(e.dataTransfer.getData(parametersList.getDragKeyName()));
            if (paramIndex != null) {
                e.preventDefault();
                var inst = new hrt.animgraph.nodes.FloatParameter();
                animGraph.nodeIdCount += 1;
                inst.id = animGraph.nodeIdCount;
                inst.parameter = animGraph.parameters[paramIndex];
                inst.setPos(posCursor);

                graphEditor.opBox(inst, true, graphEditor.currentUndoBuffer);
                graphEditor.commitUndo();
                return;
            }

            // Handle drag from anim list
            var path = e.dataTransfer.getData(AnimList.dragEventKey);
            if (path.length > 0) {
                if (StringTools.endsWith(path, ".fbx") || !StringTools.contains(path,".")) {
                    e.preventDefault();
                    var inst = new hrt.animgraph.nodes.Input();
                    animGraph.nodeIdCount += 1;
                    inst.id = animGraph.nodeIdCount;
                    inst.path = path;
                    inst.setPos(posCursor);

                    graphEditor.opBox(inst, true, graphEditor.currentUndoBuffer);
                    graphEditor.commitUndo();
                    return;
                }
                else if (StringTools.endsWith(path, ".bs2d")) {
                    e.preventDefault();
                    var inst = new hrt.animgraph.nodes.BlendSpace2D();
                    animGraph.nodeIdCount += 1;
                    inst.id = animGraph.nodeIdCount;
                    inst.path = path;
                    inst.setPos(posCursor);

                    graphEditor.opBox(inst, true, graphEditor.currentUndoBuffer);
                    graphEditor.commitUndo();
                    return;
                }
            }
        });

        scenePreview.listLoadableMeshes = () -> {
            return [ for (p in gatherAllPreviewModels(animGraph.animFolder)) {label: StringTools.replace(p, animGraph.animFolder + "/", ""), path: p} ];
        }

    }

    static public function getAnims(scene: hide.comp.Scene, ctx: hrt.animgraph.AnimGraph.EditorProviderContext ) : Array<String> {
        var anims : Array<String> = [];

        if (AnimGraph.customAnimNameLister != null) {
            anims = anims.concat(AnimGraph.customAnimNameLister(ctx));
        }

        anims = anims.concat(scene.listAnims(ctx.animDirectory));
        return anims;
    }

    public static function createChooseFolderPrompt(baseDir: String, onSet: (path: String) -> Void) : Element {
        var element = new Element("<center-content>
                <div class='basic-border' style='width: 600px'>
                    <h1>Choose a folder containing the models to animate</h1>
                    <p>Note : For the editor to work with prefabs, the chosen folder must include the .fbx used by the prefabs in its hierarchy.</p>
                    <button-2></button-2>
                <div>
            </center-content>
        ");

        var button = new hide.comp.Button(null, element.find("button-2"), "Choose folder");
        button.onClick = () -> {
            hide.Ide.inst.chooseFileOptions((paths) -> {
                if (paths != null) {
                    if (gatherAllPreviewModels(paths[0]).length <= 0) {
                        hide.Ide.inst.quickError("Folder doesn't contain any valid model");
                        return;
                    }
                    onSet(paths[0]);
                }
            },
            {
                workingDir: hide.Ide.inst.getPath(baseDir),
                onlyDirectory: true,
                allowNull: false,
                multiple: false,
            }
            );
        }

        return element;
    }

    override function buildTabMenu():Array<hide.comp.ContextMenu.MenuItem> {
        var menu = super.buildTabMenu();
        menu.push({isSeparator: true});
        menu.push({label: "Reset Model Folder", click: () -> {
            if (ide.confirm("Warning, resetting the model folder could lead to incorrect animations. Are you sure you want to proceed ?")) {
                animGraph.animFolder = null;
                save();
                reloadView();
            }
        }});

        return menu;
    }

    public function loadPreviewState() : Void {
        var settingsSer = haxe.Json.parse(getDisplayState("previewState") ?? "{}");
        previewState = {};
        @:privateAccess previewState.copyFromDynamic(settingsSer);
    }

    public function savePreviewState() : Void {
        saveDisplayState("previewState", haxe.Json.stringify(@:privateAccess previewState.copyToDynamic({})));
    }

    static public function gatherAllPreviewModels(basePath : String) : Array<String> {
        var paths = [];

        function rec(dirPath: String) {
            var files = sys.FileSystem.readDirectory(hide.Ide.inst.getPath(dirPath));
            for (path in files) {
                if (sys.FileSystem.isDirectory(hide.Ide.inst.getPath(dirPath + "/" + path))) {
                    rec(dirPath + "/" + path);
                } else {
                    var filename = path.split("/").pop();
                    var ext = filename.split(".").pop();

                    if (ext == "prefab") {
                        paths.push(dirPath + "/" + path);
                    }
                    if (ext == "fbx" && !StringTools.startsWith(filename, "Anim_")) {
                        paths.push(dirPath + "/" + path);
                    }
                }
            }
        }

        rec(basePath);
        return paths;
    }

    override function getPreviewOptionsMenu() : Array<hide.comp.ContextMenu.MenuItem> {
        var options = super.getPreviewOptionsMenu();

        var models : Array<hide.comp.ContextMenu.MenuItem> = [];
        var paths = gatherAllPreviewModels(animGraph.animFolder);
        for (path in paths) {
            var basePath = StringTools.replace(path, animGraph.animFolder + "/", "");
            models.push({label: basePath, click: () -> {
                scenePreview.setObjectPath(path);
            }});
        }

        options.push({label: "Set Model", menu: models});
        return options;
    }

    static public function addAnimSetSelector(target: Element, context:hrt.animgraph.AnimGraph.EditorProviderContext, undo: hide.ui.UndoHistory, getIndex: () -> Int, setIndex:(Int) -> Void) {
        if (hrt.animgraph.AnimGraph.customEditorResolverProvider != null)
        {
            var div = new Element("<div></div>").appendTo(target);
            div.append(new Element("<dt>Anim Set</dt>"));

            var providers = hrt.animgraph.AnimGraph.customEditorResolverProvider(context);

            var button = new hide.comp.Button(div, null, null, {hasDropdown: true});
            button.label = providers[getIndex()].name;

            var options : Array<hide.comp.ContextMenu.MenuItem> = [];
            for (i => provider in providers) {
                options.push({
                    label: provider.name,
                    click: () -> {
                        var old = getIndex();
                        function exec(isUndo: Bool) {
                            if (!isUndo) {
                                setIndex(i);
                            } else {
                                setIndex(old);
                            }
                            button.label = providers[getIndex()].name;
                        }
                        exec(false);
                        undo.change(Custom(exec));
                    }
                });
            }

            button.onClick = () -> {
                hide.comp.ContextMenu.createDropdown(button.element.get(0), options, {search: Visible, autoWidth: true});
            }
        }
    }

    public function refreshPreview() {
        if (previewNode != null)
            setPreview(previewNode);
    }

    public function setPreview(newOutput: hrt.animgraph.nodes.AnimNode) {
        queuedPreview = newOutput;
    }

    public function setPreviewInternal(newOutput: hrt.animgraph.nodes.AnimNode) {
        previewNode = newOutput;

        // refresh animation
        {
            var previewModel = scenePreview.prefab?.find(hrt.prefab.Model, (f) -> StringTools.startsWith(f.source, animGraph.animFolder))?.local3d;
            if (previewModel == null) {
                ide.quickError("Couldn't setup preview animation : no suitable model in loaded prefab matches this animgraph folder");
                return;
            }

            var resolver = null;
            if (AnimGraph.customEditorResolverProvider != null) {
                var providers = AnimGraph.customEditorResolverProvider({animDirectory: animGraph.animFolder, assetPath: state.path});
                if (providers != null && previewState.providerIndex > providers.length) {
                    previewState.providerIndex = 0;
                    savePreviewState();
                }
                resolver = providers != null ? providers[previewState.providerIndex]?.resolver : null;
            }
            var anim = animGraph.getAnimation(previewNode, resolver);
            previewModel.playAnimation(anim);
            previewAnimation = cast previewModel.currentAnimation;
            refreshPamamList();
        }

        //copy runtime parameters
        for (index => param in animGraph.parameters) {
            var animParam = @:privateAccess previewAnimation.parameterMap[param.name];
            if (animParam != null) {
                animParam.runtimeValue = param.runtimeValue;
            }
        }
        graphEditor.refreshPreviewButtons();
    }

    function refreshPamamList() {
        parametersList.refresh();
        // for (paramIndex => param in animGraph.parameters) {
        //     var paramElement = new Element('<graph-parameter>
        //         <header>
        //             <div class="reorder ico ico-reorder" draggable="true"></div>
        //             <div class="ico ico-chevron-down toggle-open"></div>
        //             <input type="text" value="${param.name}" class="fill"></input>
        //             <button-2 class="menu"><div class="ico ico-ellipsis-v"/></button-2>
        //         </header>
        //     </graph-parameter>').appendTo(parametersList);

        //     var open : Bool = getDisplayState('param.${paramIndex}') ?? false;
        //     paramElement.toggleClass("folded", open);

        //     var name = paramElement.find("input");
        //     name.on("change", (e) -> {
        //         var prev = param.name;
        //         var curr = name.val();

        //         function exec(isUndo: Bool) {
        //             if (!isUndo) {
        //                 param.name = curr;
        //             } else {
        //                 param.name = prev;
        //             }
        //             name.val(param.name);
        //             var toRefresh = animGraph.nodes.filter((n) -> Std.downcast(n, hrt.animgraph.nodes.FloatParameter)?.parameter == param);
        //             for (node in toRefresh) {
        //                 graphEditor.refreshBox(node.id);
        //             }
        //         }

        //         exec(false);
        //         undo.change(Custom(exec));
        //     });

        //     name.on("contextmenu", (e) -> {
        //         e.stopPropagation();
        //     });

        //     var toggleOpen = paramElement.find(".toggle-open");
        //     toggleOpen.on("click", (e) -> {
        //         open = !open;
        //         saveDisplayState('param.${paramIndex}', open);
        //         paramElement.toggleClass("folded", open);
        //     });

        //     var reorder = paramElement.find(".reorder");
        //     reorder.get(0).ondragstart = (e: js.html.DragEvent) -> {
        //         e.dataTransfer.setDragImage(paramElement.get(0), Std.int(paramElement.width()), 0);

        //         e.dataTransfer.setData(parametersList.getDragKeyName(), '${paramIndex}');
        //         e.dataTransfer.dropEffect = "move";
        //     }

        //     inline function isAfter(e) {
        //         return e.clientY > (paramElement.offset().top + paramElement.outerHeight() / 2.0);
        //     }

        //     paramElement.get(0).addEventListener("dragover", function(e : js.html.DragEvent) {
        //         if (!e.dataTransfer.types.contains(parametersList.getDragKeyName()))
        //             return;
        //         var after = isAfter(e);
        //         paramElement.toggleClass("hovertop", !after);
        //         paramElement.toggleClass("hoverbot", after);
        //         e.preventDefault();
        //     });

        //     paramElement.get(0).addEventListener("dragleave", function(e : js.html.DragEvent) {
        //         if (!e.dataTransfer.types.contains(parametersList.getDragKeyName()))
        //             return;
        //         paramElement.toggleClass("hovertop", false);
        //         paramElement.toggleClass("hoverbot", false);
        //     });

        //     paramElement.get(0).addEventListener("dragenter", function(e : js.html.DragEvent) {
        //         if (!e.dataTransfer.types.contains(parametersList.getDragKeyName()))
        //             return;
        //         e.preventDefault();
        //     });

        //     paramElement.get(0).addEventListener("drop", function(e : js.html.DragEvent) {
        //         var toMoveIndex = Std.parseInt(e.dataTransfer.getData(parametersList.getDragKeyName()));
        //         paramElement.toggleClass("hovertop", false);
        //         paramElement.toggleClass("hoverbot", false);
        //         if (paramIndex == null)
        //             return;
        //         var after = isAfter(e);
        //         execMoveParameterTo(toMoveIndex, paramIndex, after);
        //     });


        //     var content = new Element("<content></content>").appendTo(paramElement);
        //     var props = new Element("<ul>").appendTo(content);
        //     if (previewAnimation != null) {
        //         var slider = new Element('<li><dd>Preview</dd><input type="range" min="-1.0" max="1.0" step="0.01" value="${param.runtimeValue}"></input></li>').appendTo(props).find("input");
        //         var range = new hide.comp.Range(null,slider);

        //         range.setOnChangeUndo(undo, () -> param.runtimeValue, (v:Float) -> {
        //             param.runtimeValue = v;
        //             var runtimeParam = previewAnimation.parameterMap.get(param.name);
        //             if (runtimeParam != null) {
        //                 runtimeParam.runtimeValue = param.runtimeValue;
        //             }
        //         });

        //         var def = new Element('<li><dd>Default</dd><input type="range" min="-1.0" max="1.0" step="0.01" value="${param.defaultValue}"></input></li>').appendTo(props).find("input");
        //         var range = new hide.comp.Range(null,def);
        //         range.setOnChangeUndo(undo, () -> param.defaultValue, (v:Float) -> param.defaultValue = v);
        //     }

        //     paramElement.find("header").get(0).addEventListener("contextmenu", function (e : js.html.MouseEvent) {
        //         e.preventDefault();
        //         hide.comp.ContextMenu.createFromEvent(e, [
        //             {label: "Delete", click: () -> execRemoveParam(paramIndex)}
        //         ]);
        //     });

        //     var menu = paramElement.find(".menu");
        //     menu.on("click", (e) -> {
        //         e.preventDefault();
        //         hide.comp.ContextMenu.createDropdown(menu.get(0), [
        //             {label: "Delete", click: () -> execRemoveParam(paramIndex)}
        //         ]);
        //     });
        // }

        scenePreview.onObjectLoaded = () -> {
            setPreview(cast animGraph.nodes.find((f) -> Std.downcast(f, hrt.animgraph.nodes.Output) != null));
        }
    }

    function execRemoveParam(index: Int) {
        var save = @:privateAccess animGraph.parameters[index].copyToDynamic({});
        function exec(isUndo : Bool) {
            if (!isUndo) {
                animGraph.parameters.splice(index, 1);
            } else {
                var param = new hrt.animgraph.AnimGraph.Parameter();
                @:privateAccess param.copyFromDynamic(save);
                animGraph.parameters.insert(index, param);
            }
            refreshPamamList();
        }
        exec(false);
        undo.change(Custom(exec));
    }

    function execMoveParameterTo(oldIndex: Int, newIndex: Int) {
		function exec(isUndo: Bool) {
            if (!isUndo) {
                var param = animGraph.parameters.splice(oldIndex, 1)[0];
                animGraph.parameters.insert(newIndex, param);
            } else {
                var param = animGraph.parameters.splice(newIndex, 1)[0];
                animGraph.parameters.insert(oldIndex, param);
            }
            refreshPamamList();
		}
		exec(false);
		undo.change(Custom(exec));
	}

    override function getDefaultContent() : haxe.io.Bytes {
        var inst = new hrt.animgraph.AnimGraph(null, null);
        inst.nodes.push(new hrt.animgraph.nodes.Output());
        @:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(inst.serialize()));
    }

    override function save() {
        js.Browser.document.activeElement.blur();
        var content = ide.toJSON(animGraph.save());
        currentSign = ide.makeSignature(content);
		sys.io.File.saveContent(getPath(), content);
        super.save();
    }

    override function onScenePreviewReady() {
        super.onScenePreviewReady();

        if (scenePreview.getObjectPath() == null) {
            scenePreview.setObjectPath(gatherAllPreviewModels(animGraph.animFolder)[0]);
        }
        scenePreview.resetPreviewCamera();
    }

    override function getNodes() : Iterator<IGraphNode> {
        return animGraph.nodes.iterator();
    }

    override function getEdges():Iterator<Edge> {
        var edges : Array<Edge> = [];
        for (node in animGraph.nodes) {
            for (inputToId => edge in node.inputEdges) {
                if (edge == null)
                    continue;
                edges.push({
                    nodeToId: node.id,
                    inputToId: inputToId,
                    nodeFromId: edge.target.id,
                    outputFromId: edge.outputIndex,
                });
            }
        }
        return edges.iterator();
    }

    override function getAddNodesMenu():Array<AddNodeMenuEntry> {
        var menu : Array<AddNodeMenuEntry> = [];
        for (nodeInternalName => type in hrt.animgraph.Node.registeredNodes) {
            var info = Type.createEmptyInstance(type);
            if (!info.canCreateManually())
                continue;

            var entry : AddNodeMenuEntry = {
                name: info.getDisplayName(),
                description: "",
                group: "Group",
                onConstructNode: () -> {
                    var node : Node = cast Type.createInstance(type, []);
                    animGraph.nodeIdCount ++;
                    node.id = animGraph.nodeIdCount;
                    return node;
                }
            };

            menu.push(entry);
        }
        return menu;
    }

    override function addNode(node: IGraphNode) {
        animGraph.nodes.push(cast node);
    }

    override function removeNode(id: Int) {
        var removedNode = null;
        for (pos => node in animGraph.nodes) {
            if (node.id == id) {
                removedNode = node;
                animGraph.nodes.splice(pos, 1);
                break;
            }
        }

        // Sanity check, normally the graphEditor should remove the edges for us
        // before calling removeNode
        for (node in animGraph.nodes) {
            for (input in node.inputEdges) {
                if (input == null)
                    continue;
                if (input.target == removedNode) {
                    throw "assert";
                }
            }
        }
    }

    override function serializeNode(node : IGraphNode) : Dynamic {
        var node : hrt.animgraph.Node = cast node;
        var ser = node.serializeToDynamic();
        ser.id = node.id;
        var param = Std.downcast(node, hrt.animgraph.nodes.FloatParameter);
        if (param != null) {
            ser.paramId = animGraph.parameters.indexOf(param.parameter);
        }
        return ser;
    }

    override function unserializeNode(data: Dynamic, newId: Bool) : IGraphNode {
        var node = hrt.animgraph.Node.createFromDynamic(data);
        if (newId) {
            animGraph.nodeIdCount ++;
            node.id = animGraph.nodeIdCount;
        } else {
            node.id = data.id;
        }

        var param = Std.downcast(node, hrt.animgraph.nodes.FloatParameter);
        if (param != null) {
            param.parameter = animGraph.parameters[data.paramId];
        }
        return node;
    }

    override function canAddEdge(edge : Edge) : Bool {
        var input = animGraph.getNodeByEditorId(edge.nodeToId).getInputs()[edge.inputToId];
        var output = animGraph.getNodeByEditorId(edge.nodeFromId).getOutputs()[edge.outputFromId];

        return (Node.areOutputsCompatible(input.type, output.type));
    }

    override function addEdge(edge : Edge) : Void {
        var inputNode = animGraph.getNodeByEditorId(edge.nodeToId);
        inputNode.inputEdges[edge.inputToId] = {target: animGraph.getNodeByEditorId(edge.nodeFromId), outputIndex: edge.outputFromId};

        refreshPreview();
    }

    override function removeEdge(nodeToId: Int, inputToId : Int) : Void {
        var inputNode = animGraph.getNodeByEditorId(nodeToId);
        inputNode.inputEdges[inputToId] = null;

        refreshPreview();
    }

    override function onScenePreviewUpdate(dt:Float) {
        super.onScenePreviewUpdate(dt);

        if (queuedPreview != null) {
            setPreviewInternal(queuedPreview);
            queuedPreview = null;
        }
    }

    function addParameter() {
        var newParam = new hrt.animgraph.AnimGraph.Parameter();
        newParam.name = "New Parameter";
        newParam.defaultValue = 0.0;

        var disctictNameId = 0;

        while (true) {
            var retry = false;
            for (param in animGraph.parameters) {
                if (newParam.name == param.name) {
                    disctictNameId += 1;
                    newParam.name = 'New Parameter ($disctictNameId)';
                    retry = true;
                    break;
                }
            }
            if (retry)
                continue;
            break;
        }

        var index = animGraph.parameters.length;
        function exec(isUndo: Bool) {
            if (!isUndo) {
                animGraph.parameters.insert(index, newParam);
            } else {
                animGraph.parameters.splice(index, 1);
            }
            refreshPamamList();
        }

        undo.change(Custom(exec));
        exec(false);
    }

    static var _ = FileTree.registerExtension(AnimGraphEditor,["animgraph"],{ icon : "play-circle-o", createNew: "Anim Graph" });
}