package hide.view;

/**
	Undo stack of the prefab editor : each action lists the prefabs it modified
**/
class PrefabUndo extends hrt.tools.Undo {

	public function new() {
		super();
		onStep = (info, isUndo) -> onPrefabsChanged(cast info, isUndo);
	}

	/**
		Record an already applied action that modified `prefabs`. Pass an empty array for actions
		that don't modify any prefab (selection, display settings...)
	**/
	public function recordPrefabs(action: hrt.tools.Undo.Action, hasDataChanges: Bool, prefabs: Array<hrt.prefab.Prefab>) {
		record(action, hasDataChanges, prefabs);
	}

	public function runPrefabs(action: hrt.tools.Undo.Action, hasDataChanges: Bool, prefabs: Array<hrt.prefab.Prefab>) {
		run(action, hasDataChanges, prefabs);
	}

	/**
		Called after an action has been recorded, undone or redone. `prefabs` is null if the action
		didn't specify which prefabs it modified (any prefab may have changed)
	**/
	public dynamic function onPrefabsChanged(prefabs: Null<Array<hrt.prefab.Prefab>>, isUndo: Bool) {
	}
}
