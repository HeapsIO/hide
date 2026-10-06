package hide.view;

/**
	Undo stack of the prefab editor : each action lists the prefabs it modified
**/
class PrefabUndo extends hrt.tools.Undo {

	public function new() {
		super();
		onRecord = (info) -> onPrefabsRecorded(cast info);
	}

	/**
		Called once when a new action is recorded (not on undo/redo). mergeWithLast can be called from here
		to apply the side effects of the action in the same undo step.
	**/
	public dynamic function onPrefabsRecorded(prefabs: Null<Array<hrt.prefab.Prefab>>) {
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
}
