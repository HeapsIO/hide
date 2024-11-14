package hide.comp;

class StreamTable extends hide.comp.Component {

    var table : js.html.TableElement;
    var pageRowCount : Int = 100;
    var scrollElem: js.html.Element;
    var customScrollWrapper: js.html.DivElement;

    var customScrollbar: js.html.Element;
    var scrollbarCursor: js.html.Element;


    var defaultPageHeight : Float;
    var defaultPageCount : Int;

    var pageStatus : Array<{wantVisible: Bool, currentVisible: Bool, firstLoad: Bool}> = [];

    var intersectionObserver : js.html.IntersectionObserver;

    var updateHeight = false;

    var pageCount(get, never) : Int;
    function get_pageCount() : Int {
        return Math.ceil(getRowCounts() / pageRowCount);
    }

    public function new(parent:hide.Element,el:hide.Element, scrollRoot: hide.Element) {
        if (el != null) {
            if (el.get(0).nodeName != "TABLE") {
                throw "el must be a table";
            }
        }
        else {
            el = new hide.Element("<table>");
        }
        var scrollWrapper = new hide.Element("<div class='custom-scroll-wrapper'></div>");
        scrollWrapper.append(el);
        super(parent, scrollWrapper);
        el.addClass("stream-table");
        table = cast el.get(0);
        customScrollWrapper = cast scrollWrapper.get(0);

        customScrollbar = js.Browser.document.createDivElement();
        customScrollbar.classList.add("custom-scrollbar");
        customScrollWrapper.appendChild(customScrollbar);

        scrollbarCursor = js.Browser.document.createDivElement();
        scrollbarCursor.classList.add("cursor");
        customScrollbar.appendChild(scrollbarCursor);

        var capture = false;
        customScrollbar.onpointerdown = (e:js.html.PointerEvent) -> {
            var pos = e.offsetY;
            var height = customScrollbar.getBoundingClientRect().height;
            var rel = pos / height;

            scrollToRowCenter(rel * getRowCounts());

            capture = true;
            customScrollbar.setPointerCapture(e.pointerId);
        }

        customScrollbar.onpointermove = (e:js.html.PointerEvent) -> {
            if (capture == false)
                return;
            targetScroll = e.offsetY;
            js.Browser.window.requestAnimationFrame(onAnimationFrame);
        }

        customScrollbar.onpointerup = (e:js.html.PointerEvent) -> {
            capture = false;
            customScrollbar.releasePointerCapture(e.pointerId);
        }

        /*table.onscroll = (e: js.html.Event) -> {
            var scrollPos =
            customScrollbar.style.top =
        }*/

        scrollElem = scrollRoot.get(0);
    }

    var targetScroll : Float = 0.0;

    public function onAnimationFrame(_: Float) {
        scrollToRowCenter(targetScroll);

        var height = customScrollbar.getBoundingClientRect().height;
        var rel = targetScroll / height;

        scrollToRowCenter(rel * getRowCounts());
    }

    public static function createTableHeader(row: js.html.TableRowElement) : js.html.TableRowElement {
        var th = js.Browser.document.createElement("th");
        row.appendChild(th);
        th.setAttribute("scope", "column");
        return cast th;
    }

    public function refreshTable(wantedRowsPerPage: Int = 30, pageHeight: Float = 2000) {
        pageStatus.resize(0);

        pageRowCount = wantedRowsPerPage;
        defaultPageHeight = pageHeight;
        defaultPageCount = 0;

        table.innerHTML = "";

        var thead : js.html.TableSectionElement = cast table.createTHead();
        genTableHeader(cast thead.insertRow());

        if (intersectionObserver == null) {
            initIntersectionObserver();
        }
        else {
            intersectionObserver.disconnect();
        }

        for (i in 0...pageCount) {
            var tbody = table.createTBody();
            tbody.style.height = '${hxd.Math.max(defaultPageHeight, 100)}px';

            // mitigate ficker on refresh
            if (i == 0) {
                pageStatus[i] = {wantVisible: true, currentVisible: true, firstLoad: true};
                addPage(i);
            }
            else {
                pageStatus[i] = {wantVisible: false, currentVisible: false, firstLoad: true};
            }

            intersectionObserver.observe(tbody);
            Reflect.setField(tbody, "pageId", i);
        }
    }

    /**
        Return the row in the table if it is currently displayed
    **/
    public function getRow(rowId : Int) : Null<js.html.TableRowElement> {
        var pageId = Math.floor(rowId / pageRowCount);
        var pageRowId = rowId - pageId * pageRowCount;

        if (!pageStatus[pageId].currentVisible)
            return null;

        return cast (cast table.tBodies[pageId]:js.html.TableSectionElement).rows[pageRowId];
    }

    public function scrollToRow(rowId : Int) : Void {
        var pageId = Math.floor(rowId / pageRowCount);
        var pageRowId = rowId - pageId * pageRowCount;
        if (pageStatus[pageId].currentVisible == false) {
            addPage(pageId);
        }

        var row = getRow(rowId);
        row.scrollIntoView({ block: cast "nearest", behavior: cast "auto"});
    }

    public function scrollToRowCenter(rowFloat : Float) : Void {

        var rowId = Std.int(rowFloat);
        if (rowId < 0) rowId = 0;
        if (rowId > getRowCounts() - 1) rowId = getRowCounts() - 1;
        var remainder = rowFloat - rowId;
        var pageId = Math.floor(rowId / pageRowCount);
        var pageRowId = rowId - pageId * pageRowCount;
        if (pageStatus[pageId].currentVisible == false) {
            addPage(pageId);
        }

        var row = getRow(rowId);
        var tableRect = table.getBoundingClientRect();
        var rowRect = row.getBoundingClientRect();
        table.scrollTo(0, row.offsetTop + rowRect.height * remainder - tableRect.height);
    }

    public function setTableColWidths(widths: Array<String>) {
        table.style.gridTemplateColumns = widths.join(" ");
    }

    public dynamic function getRowCounts() : Int {
        return 0;
    }

    public dynamic function genTableRow(index: Int, row: js.html.TableRowElement ) {

    }

    public dynamic function genTableHeader(row: js.html.TableRowElement) {

    }

    // =============== Private api below =================

    function initIntersectionObserver() {
        var init : js.html.IntersectionObserverInit = {
            root: scrollElem,
            threshold: [0],
            rootMargin: "500px",
        };

        intersectionObserver = new js.html.IntersectionObserver(onIntersection, init);
    }

    function onIntersection(items : Array<js.html.IntersectionObserverEntry>, observer: js.html.IntersectionObserver) : Void {
        for (item in items) {
            var id = Reflect.getProperty(item.target, "pageId");
            pageStatus[id].wantVisible = item.isIntersecting;
        }

        js.Browser.window.requestAnimationFrame(onAnimFrame);
    }

    function onAnimFrame(dt: Float) {
        for (id => page in pageStatus) {
            if (page.currentVisible != page.wantVisible) {
                if (page.wantVisible) {
                    addPage(id);
                }
                else {
                    removePage(id);
                }
                if (page.currentVisible != page.wantVisible) {
                    throw "inconsistent behavior";
                }
            }
        }

        if (updateHeight) {
            updateHeight = false;
            var height = '${defaultPageHeight}px';
            for (id => page in pageStatus) {
                if (page.firstLoad) {
                    var body : js.html.TableSectionElement = cast table.tBodies[id];
                    body.style.height = height;
                }
            }
        }
    }

    function addPage(pageId: Int) {
        var body : js.html.TableSectionElement = cast table.tBodies[pageId];
        var firstId = pageId * pageRowCount;
        var lastId = hxd.Math.imin((pageId+1) * pageRowCount, getRowCounts());
        for (rowId in firstId...lastId) {
            var row : js.html.TableRowElement = cast body.insertRow();
            genTableRow(rowId, row);
        }
        body.style.height = "unset";

        if (pageStatus[pageId].firstLoad) {
            var prevHeight = defaultPageHeight;
            var rect = body.getBoundingClientRect();
            // rect.height might be = 0 if our container is not visible
            if (rect.height > 0) {
                defaultPageCount ++;
                defaultPageHeight = defaultPageHeight * (defaultPageCount - 1) / defaultPageCount + rect.height / defaultPageCount;
                pageStatus[pageId].firstLoad = false;
                updateHeight = true;

                // note : scrollTop is a float in modern JS, but it is treated as Int in haxe for some reason, so we untyped it
                if (untyped table.scrollTop > rect.bottom) {
                    untyped table.scrollTop += (rect.height - prevHeight);
                }
            }
        }

        pageStatus[pageId].currentVisible = true;
    }

    function removePage(pageId: Int) {
        var body : js.html.TableSectionElement = cast table.tBodies[pageId];
        var rect = body.getBoundingClientRect();

        body.style.height = '${rect.height}px';
        body.innerHTML = "";
        updateHeight = true;
        pageStatus[pageId].currentVisible = false;
    }

}