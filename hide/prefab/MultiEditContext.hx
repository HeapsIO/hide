package hide.prefab;

using hrt.tools.MapUtils;

class MultiEditContext extends hide.comp.SceneEditor.SceneEditorContext {
    #if editor

    var onChangeLock : Int = 0;

    var propsValueSave : Map<String, Map<hrt.prefab.Prefab, Dynamic>> = [];

    static function refreshPrefab(prefab: hrt.prefab.Prefab, propName: String) {

        // can't call super from inside a local function so we paste the onChange verbatim here :/
        prefab.updateInstance(propName);

        var parent = prefab.parent;
        while( parent != null ) {
            var pr = parent.getHideProps();
            if( pr.onChildUpdate != null ) pr.onChildUpdate(prefab);
            parent = parent.parent;
        }
    }

    override function onChange(p: hrt.prefab.Prefab, propName: String) {
        // no super
        for (prefab in elements) {
            super.onChange(prefab, propName);
        }
        // if (onChangeLock > 0)
        //     return;

        // var undoFns : Array<(isUndo: Bool) -> Void> = [];

        // if (!properties.isTempChange) {
        //     var alternateHistory = new hide.ui.UndoHistory();
        //     @:privateAccess
        //     {
        //         var undo = properties.undo.undoElts.pop();
        //         alternateHistory.undoElts.push(undo);
        //     }

        //     undoFns.push((isUndo) -> {
        //         onChangeLock ++;
        //         if (isUndo) {
        //             alternateHistory.undo();
        //         } else {
        //             alternateHistory.redo();
        //         }
        //         onChangeLock --;
        //     });
        // }

        // var valueSave = propsValueSave.getOrPut(propName, []);

        // var newValue = Reflect.getProperty(p, propName);
        // for (prefab in elements) {
        //     var oldValue = Reflect.getProperty(prefab, propName);
        //     if (properties.isTempChange) {
        //         if (!valueSave.exists(prefab)) {
        //             valueSave.set(prefab, oldValue);
        //         }
        //         Reflect.setProperty(prefab, propName, newValue);
        //         refreshPrefab(prefab, propName);
        //     }
        //     else {
        //         var oldValue = valueSave.get(prefab) ?? Reflect.getProperty(prefab, propName);
        //         var exec = (isUndo) -> {
        //             if (!isUndo) {
        //                 Reflect.setProperty(prefab, propName, newValue);
        //             } else {
        //                 Reflect.setProperty(prefab, propName, oldValue);
        //             }
        //             trace(isUndo ? "undo" : "redo", propName, newValue);

        //             refreshPrefab(prefab, propName);
        //         }
        //         exec(false);
        //         undoFns.push(exec);
        //     }
        // }

        // if (!properties.isTempChange) {
        //     var exec = (isUndo:Bool) -> {
        //         if (!isUndo) {
        //             for (f in undoFns) {
        //                 f(false);
        //             }
        //         } else {
        //             for (i in 0...undoFns.length) {
        //                 undoFns[undoFns.length - i - 1](true);
        //             }
        //         }
        //     }

        //     properties.undo.change(Custom(exec));
        //     valueSave.clear();
        //     propsValueSave.remove(propName);
        // }
    }

    #end
}

class MultiPropsEditor extends hide.comp.PropsEditor {

    public var hashToContext : Map<String, {context: Dynamic, onChange: String -> Void}> = [];

    override function add(e : Element, ?context : Dynamic, ?onChange : String -> Void) : Element {
        // we do not call super because we are completely overriding the add() behavior
        return build(element, context, onChange);
    }

    override function build(e: Element, ?context: Dynamic, ?onChange: String -> Void) {
        var multiEdit = Std.downcast(currentEditContext, MultiEditContext);
        if (multiEdit == null)
            throw "currentEditContext must be a MultiEditContext";
        var hash = hide.comp.PropsEditor.getBuildLocationHash();
        hashToContext.set(hash, {context: context, onChange: onChange});
        return e;
    }
}