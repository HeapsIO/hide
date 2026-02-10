package hrt.ui;

#if hui

class HuiProjectLayout extends HuiElement {
	static var SRC =
		<hui-project-layout>
			<hui-split-container id="app-panel-internal" direction={hrt.ui.HuiSplitContainer.Direction.Horizontal} save-display-key="left-panel-split">
				<hui-tab-view-container public id="left-panel"/>
				<hui-split-container id="right-panel-internal" direction={hrt.ui.HuiSplitContainer.Direction.Vertical} anchor-to={hrt.ui.HuiSplitContainer.AnchorTo.End} save-display-key="bottom-panel-split">
					<hui-tab-view-container public id="main-panel"/>
					<hui-tab-view-container public id="bottom-panel"/>
				</hui-split-container>
			</hui-split-container>
		</hui-project-layout>
}

#end