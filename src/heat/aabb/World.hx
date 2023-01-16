package heat.aabb;

using tink.CoreApi;
using heat.AllCore;

/**
    Kinds of collisions
**/
enum CollisionKind {
    SLIDE;
    BOUNCE;
    CROSS;
    TOUCH;
    NONE;
    OTHER(kind:String);
}

/**
    Represents a cell in the spatial map. Each cell owns a Map of the items contained within it.
**/
typedef Cell<T:EnumValue> = {itemCount:Int, cell:VectorInt2, items:Map<T, Bool>}

/**
    Defines an intersection between a rectangle and a line segment.
**/
typedef RectSegmentIntersection = {
    ti1:Float,
    ti2:Float,
    nx1:Int,
    ny1:Int,
    nx2:Int,
    ny2:Int
}

/**
    Data for a single collision instance.
**/
typedef Collision<T:EnumValue> = {
    overlaps:Bool,
    ti:Float,
    moveX:Float,
    moveY:Float,
    normalX:Int,
    normalY:Int,
    touchX:Float,
    touchY:Float,
    item:T,
    itemRect:Rect,
    other:T,
    otherRect:Rect,
    kind:CollisionKind,
    slideX:Option<Float>,
    slideY:Option<Float>,
    bounceX:Option<Float>,
    bounceY:Option<Float>
}

// grid_traverse* functions are based on "A Fast Voxel Traversal Algorithm for Ray Tracing",
// by John Amanides and Andrew Woo - http://www.cse.yorku.ca/~amana/research/grid.pdf
// It has been modified to include both cells when the ray "touches a grid corner",
// and with a different exit condition

typedef GridTraversalData = {
    step:Int,
    td:Float,
    tmax:Float
}

typedef ResponseData<T:EnumValue> = {
    goalX:Float,
    goalY:Float,
    cols:Array<Collision<T>>
}

/**
    Function signature for a collision response.
**/
typedef ResponseFunc<T:EnumValue> = (world:World<T>, col:Collision<T>, 
    rect:IRect, goal:IVector2<Float>, filter:ColFilterFunc<T>)->ResponseData<T>;

/**
    Function signature for a collision filter.
**/
typedef ColFilterFunc<T:EnumValue> = (item:T, other:T)->CollisionKind;

typedef ItemQueryInfo<T:EnumValue> = {item:T, ti1:Float, ti2:Float, weight:Float};

/**
    Result of an attempted move.
**/
typedef MoveResult<T:EnumValue> = {actualX:Float, actualY:Float, cols:Array<Collision<T>>}

class World<T:EnumValue> {
    var cellSize:Int;
    var rects = new Map<T, Rect>();
    var rows = new Map<Int, Map<Int, Cell<T>>>();
    var nonEmptyCells = new Map<Cell<T>, Bool>();
    var responses = new Map<CollisionKind, ResponseFunc<T>>();

    var collisionArrayPool:Pool<Array<Collision<T>>>;
    var rectSegmentIntersectionPool:Pool<RectSegmentIntersection>;
    var rectPool:Pool<MRect>;
    var pointPool:Pool<MVectorFloat2>;
    var pointIntPool:Pool<MVectorInt2>;
    var segmentPool:Pool<MLineSegment>;

    final originPoint = new VectorFloat2();

    public function new(cellSize:Int) {
        this.cellSize = cellSize;
        if (this.cellSize < 0) this.cellSize = 64;
        responses[SLIDE] = slide;
        responses[TOUCH] = touch;
        responses[CROSS] = cross;
        responses[BOUNCE] = bounce;

        collisionArrayPool = new Pool(collisionArrayConstructor, collisionArrayInit);
        rectSegmentIntersectionPool = new Pool(rectSegmentIntersectionConstructor);
        rectPool = new Pool(rectConstructor, rectInit);
        pointPool = new Pool(pointConstructor, pointInit);
        pointIntPool = new Pool(pointIntConstructor, pointIntInit);
        segmentPool = new Pool(segmentConstructor, segmentInit);
    }

    inline function collisionArrayConstructor<T:EnumValue>():Array<Collision<T>> {
        return [];
    }

    function collisionArrayInit<T:EnumValue>(x:Array<Collision<T>>):Array<Collision<T>> {
        while (x.length > 0) x.pop();
        return x;
    }

    inline function rectSegmentIntersectionConstructor():RectSegmentIntersection {
        return {
            ti1:0,
            ti2:0,
            nx1:0,
            ny1:0,
            nx2:0,
            ny2:0
        };
    }

    inline function rectConstructor():MRect {
        return new MRect();
    }

    inline function rectInit(rect:MRect):MRect {
        return rect.init();
    }

    inline function pointConstructor():MVectorFloat2 {
        return new MVectorFloat2();
    }

    inline function pointInit(point:MVectorFloat2):MVectorFloat2 {
        return point.init(0,0);
    }

    inline function pointIntConstructor():MVectorInt2 {
        return new MVectorInt2();
    }

    inline function pointIntInit(point:MVectorInt2):MVectorInt2 {
        return point.init(0,0);
    }

    inline function segmentConstructor():MLineSegment {
        return new MLineSegment();
    }

    inline function segmentInit(segment:MLineSegment):MLineSegment {
        return segment.init();
    }

    
    function defaultFilter(item:T, other:T):CollisionKind {
        return SLIDE;
    }
    
    function rectGetSegmentIntersectionIndices(rect:IRect, seg:ILineSegment, ?ti1:Float, 
    ?ti2:Float):haxe.ds.Option<RectSegmentIntersection>
    {
        if (ti1 == null) ti1 = 0.;
        if (ti2 == null) ti2 = 1.;
        var dx = seg.x2-seg.x1;
        var dy = seg.y2-seg.y1;
        var nx = 0;
        var ny = 0;
        var nx1 = 0;
        var ny1 = 0;
        var nx2 = 0;
        var ny2 = 0;
        var p = 0.;
        var q = 0.;
        var r = 0.;
    
        for (side in 1...5) {
            switch side {
                case 1: {
                    nx = -1;
                    ny = 0;
                    p = -dx;
                    q = seg.x1 - rect.leftX;
                }
                case 2: {
                    nx = 1;
                    ny = 0;
                    p = dx;
                    q = rect.rightX - seg.x1;
                }
                case 3: {
                    nx = 0;
                    ny = -1;
                    p = -dy;
                    q = seg.y1 - rect.topY;
                }
                case 4: {
                    nx = 0;
                    ny = 1;
                    p = dy;
                    q = rect.bottomY - seg.y1;
                }
            }
            if (p == 0) {
                if (q <= 0) return None;
            }
            else {
                r = q / p;
                if (p < 0) {
                    if (r > ti2) return None;
                    else if (r > ti1) {
                        ti1 = r;
                        nx1 = nx;
                        ny1 = ny;
                    }
                }
                else {
                    if (r < ti1) return None;
                    else if (r < ti2) {
                        ti2 = r;
                        nx2 = nx;
                        ny2 = ny;
                    }
                }
            }
        }
        
        var result = rectSegmentIntersectionPool.get();
        result.ti1 = ti1;
        result.ti2 = ti2;
        result.nx1 = nx1;
        result.ny1 = ny1;
        result.nx2 = nx2;
        result.ny2 = ny2;
        return Some(result);
    }
    
    function rectGetSquareDist(rect1:IRect, rect2:IRect):Float
    {
        var dx = rect1.leftX - rect2.leftX + (rect1.width - rect2.width)/2;
        var dy = rect1.topY - rect2.topY + (rect1.height - rect2.height)/2;
        return dx*dx + dy*dy;
    }
    
    function rectDetectCollision(rect1:Rect, rect2:Rect, goal:IVector2<Float>):haxe.ds.Option<Collision<T>>
    {
        var dx = goal.x - rect1.leftX;
        var dy = goal.y - rect1.topY;
        var rectDiff = rectPool.get()
            .initFrom(rect1);
        rectDiff.diffWith(rect2, rectDiff);
        var overlaps = false;
        var ti:Null<Float> = null;
        var nx = 0;
        var ny = 0;
        if (rectDiff.containsPoint(originPoint.x, originPoint.y)) {
            //item was intersecting other
            var point = pointPool.get();
            rectDiff.nearestCornerTo(originPoint.x, originPoint.y, point);
            var wi = Math.min(rect1.width, Math.abs(point.x));
            var hi = Math.min(rect1.height, Math.abs(point.y));
            ti = -wi * hi;
            overlaps = true;
            pointPool.put(point);
        }
        else {
            var seg = segmentPool.get();
            seg.init(0, 0, dx, dy);
            var segInt = rectGetSegmentIntersectionIndices(rectDiff, 
                seg, Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY);
            switch segInt {
                case Some(segInt): {
                    if (segInt.ti1 < 1 
                    && Math.abs(segInt.ti1 - segInt.ti2) >= Math.FP_ERR() 
                    && (0 < segInt.ti1 + Math.FP_ERR() || 0 == segInt.ti1 && segInt.ti2 > 0))
                    {
                        ti = segInt.ti1;
                        nx = segInt.nx1;
                        ny = segInt.ny1;
                        overlaps = false;
                    }
                    rectSegmentIntersectionPool.put(segInt);
                }
                case None: {}
            }
            segmentPool.put(seg);
        }
        if (ti == null) return None;
        var tx = 0.;
        var ty = 0.;
        if (overlaps) {
            if (dx == 0 && dy == 0) {
                //intersecting and not moving - use minimum displacement vector
                var point = pointPool.get();
                rectDiff.nearestCornerTo(originPoint.x, originPoint.y, point);
                if (Math.abs(point.x) < Math.abs(point.y)) {
                    point.y = 0;
                }
                else {
                    point.x = 0;
                }
                nx = Math.sign(point.x);
                ny = Math.sign(point.y);
                pointPool.put(point);
            }
            else {
                //intersecting and moving - move in opposite direction
                var seg = segmentPool.get();
                seg.init(0, 0, dx, dy);
                var segInt = rectGetSegmentIntersectionIndices(rectDiff, seg, 
                    Math.NEGATIVE_INFINITY, 1);
                segmentPool.put(seg);
                switch segInt {
                    case None: return None;
                    case Some(segInt): {
                        tx = rect1.leftX + dx * segInt.ti1;
                        ty = rect1.topY + dy * segInt.ti1;
                        rectSegmentIntersectionPool.put(segInt);
                    }
                }
            }
        }
        else {
            //tunnel
            tx = rect1.leftX + dx * ti;
            ty = rect1.topY + dy * ti;
        }

        rectPool.put(rectDiff);
    
        return Some({
            overlaps:overlaps,
            ti:ti,
            moveX:dx,
            moveY:dy,
            normalX:nx,
            normalY:ny,
            touchX:tx,
            touchY:ty,
            item:null,
            itemRect:rect1,
            other:null,
            otherRect:rect2,
            kind:NONE,
            slideX:None,
            slideY:None,
            bounceX:None,
            bounceY:None
        });
    }
    
    function gridToWorld(cellSize:Int, point:IVector2<Int>):MVectorFloat2 {
        return pointPool.get()
            .init((point.x-1)*cellSize, (point.y-1)*cellSize);
    }
    
    function gridToCell(cellSize:Int, point:IVector2<Float>):MVectorInt2 {
        return pointIntPool.get()
            .init(Math.floor(point.x / cellSize) + 1,
                Math.floor(point.y / cellSize) + 1);
    }

    function sortByWeight(a:ItemQueryInfo<T>, b:ItemQueryInfo<T>):Int {
        return a.weight < b.weight ? -1 : a.weight == b.weight ? 0 : 1;
    }

    function sortByTiAndDistance(a:Collision<T>, b:Collision<T>):Int {
        var ad = rectGetSquareDist(a.itemRect, a.otherRect);
        var bd = rectGetSquareDist(a.itemRect, b.otherRect);
        return ad < bd ? -1 : (ad == bd) ? 0 : 1;
    }

    function gridTraverseInitStep(cellSize:Int, ct:Float, t1:Float, t2:Float)
    :GridTraversalData
    {
        var v = t2 - t1;
        if (v > 0) {
            return {step:1, td:cellSize/v, tmax:((ct + v) * cellSize - t1) / v}
        }
        else if (v < 0) {
            return {step:-1, td:-cellSize/v, tmax:((ct + v - 1) * cellSize - t1) / v}
        }
        else {
            return {step:0, td:Math.POSITIVE_INFINITY, tmax:Math.NEGATIVE_INFINITY}
        }
    }
    
    function gridTraverse(cellSize:Int, p1:VectorFloat2, p2:VectorFloat2, f:(cell:MVectorInt2)->Void):Void {
        var cell1 = gridToCell(cellSize, p1);
        var cell2 = gridToCell(cellSize, p2);
        var tDataX = gridTraverseInitStep(cellSize, cell1.x, p1.x, p2.x);
        var tDataY = gridTraverseInitStep(cellSize, cell1.y, p1.y, p2.y);
        var cell = cell1.clone();
        f(cell);
        // The default implementation had an infinite loop problem when
        // approaching the last cell in some occassions. We finish iterating
        // when we are *next* to the last cell
        while (Math.abs(cell.x - cell2.x) + Math.abs(cell.y - cell2.y) > 1) {
            if (tDataX.tmax < tDataY.tmax) {
                tDataX.tmax += tDataX.td;
                cell.x += tDataX.step;
            }
            else {
                // Addition: include both cells when going through corners
                if (tDataX.tmax == tDataY.tmax) {
                    cell.x += tDataX.step;
                    f(cell);
                    cell.x -= tDataX.step;
                }
                tDataY.tmax += tDataY.td;
                cell.y += tDataY.step;
                f(cell);
            }
        }
    
        // If we have not arrived to the last cell, use it
        if (cell.x != cell2.x || cell.y != cell2.y) f(cell2);
    }
    
    function gridToCellRect(cellSize:Int, rect:IRect):Rect {

        var cell = gridToCell(cellSize, new VectorFloat2(rect.leftX, rect.topY));
        var cr = Math.ceil((rect.rightX) / cellSize);
        var cb = Math.ceil((rect.bottomY) / cellSize);
        return new Rect(cell.x, cell.y, cr - cell.x + 1, cb - cell.y + 1);
    }

    function touch(world:World<T>, col:Collision<T>, rect:IRect, goal:IVector2<Float>,
    filter:ColFilterFunc<T>):ResponseData<T>
    {
        return {goalX:col.touchX, goalY:col.touchY, cols:new Array<Collision<T>>()}
    }
    
    function cross(world:World<T>, col:Collision<T>, rect:IRect, goal:IVector2<Float>, 
    filter:ColFilterFunc<T>):ResponseData<T>
    {
        return {
            goal:new VectorFloat2(goal.x, goal.y),
            cols:world.project(col.item, rect, goal, filter)
        }
    }
    
    function slide(world:World<T>, col:Collision<T>, rect:IRect, goal:IVector2<Float>, 
    filter:ColFilterFunc<T>):ResponseData<T> 
    {
        var newGoal = {x:goal.x, y:goal.y};
        if (col.move.x != 0 || col.move.y != 0) {
            if (col.normal.x != 0) {
                newGoal.x = col.touch.x;
            }
            else {
                newGoal.y = col.touch.y;
            }
        }
        col.slide = {x:newGoal.x, y:newGoal.y}
        var newRect = {x:col.touch.x, y:col.touch.y, w:rect.width, h:rect.height}
        return {
            goal: newGoal,
            cols: world.project(col.item, newRect, newGoal, filter)
        }
    }
    
    function bounce(world:World<T>, col:Collision<T>, rect:IRect, goal:IVector2<Float>, 
    filter:ColFilterFunc<T>):ResponseData<T> 
    {
        var newGoal = {x:goal.x, y:goal.y};
        var bx = col.touch.x;
        var by = col.touch.y;
        if (col.move.x != 0 || col.move.y != 0) {
            var bnx = newGoal.x - col.touch.x;
            var bny = newGoal.y - col.touch.y;
            if (col.normal.x == 0) {
                bny *= -1;
            }
            else {
                bnx *= -1;
            }
            bx = col.touch.x + bnx;
            by = col.touch.y + bny;
        }
        col.bounce = {x:bx, y:by};
        var newRect = {x:col.touch.x, y:col.touch.y, w:rect.width, h:rect.height}
        newGoal.x = bx;
        newGoal.y = by;
        return {goal:newGoal, cols:world.project(col.item, newRect, newGoal, filter)}
    }

    function addItemToCell(item:T, cell:VectorInt2) {
        if (this.rows[cell.y] == null) this.rows[cell.y] = new Map<Int, Cell<T>>();
        var row = this.rows[cell.y];
        if (row[cell.x] == null) {
            row[cell.x] = {
                itemCount: 0,
                cell: {x:cell.x, y:cell.y},
                items: new Map<T, Bool>()
            }
        }
        var cell = row[cell.x];
        nonEmptyCells[cell] = true;
        if (!cell.items.exists(item)) {
            cell.items[item] = true;
            cell.itemCount += 1;
        }
    }

    function removeItemFromCell(item:T, cell:VectorInt2):Outcome<Noise, Error> {
        var row = rows[cell.y];
        if (row == null) return Failure(new Error("Row is empty"));
        if (!row.exists(cell.x)) return Failure(new Error("Column is empty"));
        var cell = row[cell.x];
        if (!cell.items.exists(item)) return Failure(new Error("Item not found in cell"));
        cell.items.remove(item);
        cell.itemCount -= 1;
        if (cell.itemCount <= 0) {
            nonEmptyCells.remove(cell);
        }
        return Success(Noise);
    }

    function getDictItemsInCellRect(cellRect:Rect):Map<T, Bool> {
        var itemsDict = new Map<T, Bool>();
        for (cy in Std.int(cellRect.y)...Std.int(cellRect.y+cellRect.height)) {
            if (!rows.exists(cy)) continue;
            var row = rows[cy];
            for (cx in Std.int(cellRect.x)...Std.int(cellRect.x+cellRect.width)) {
                if (!row.exists(cx)) continue;
                var cell = row[cx];
                if (cell.itemCount <= 0) continue;
                for (item => _ in cell.items) {
                    itemsDict[item] = true;
                }
            }
        }
        return itemsDict;
    }

    function getCellsTouchedBySegment(seg:LineSegment) {
        var visited = new Map<Cell<T>, Bool>();
        var cells = new Array<Cell<T>>();
        gridTraverse(cellSize, {x:seg.x1, y:seg.y1}, {x:seg.x2, y:seg.y2}, 
        (cell:VectorInt2)->{
            if (!rows.exists(cell.y)) return;
            var row = rows[cell.y];
            if (!row.exists(cell.x)) return;
            var visitedCell = row[cell.x];
            if (visited.exists(visitedCell)) return;
            visited[visitedCell] = true;
            cells.push(visitedCell);
        });
        return cells;
    }

    function getInfoAboutItemsTouchedBySegment(seg:LineSegment, 
    ?filter:(item:T)->Bool):Array<ItemQueryInfo<T>>
    {
        var cells = getCellsTouchedBySegment(seg);
        var rect:Rect;
        var visited = new Map<T, Bool>();
        var itemQueryInfos = new Array<ItemQueryInfo<T>>();
        for (i in 0...cells.length) {
            var cell = cells[i];
            for (item => _ in cell.items) {
                if (visited.exists(item)) continue;
                visited[item] = true;
                if (filter != null && !filter(item)) continue;
                var rect = rects[item];
                var interResult = rectGetSegmentIntersectionIndices(rect, seg,
                    0, 1);
                switch interResult {
                    case None: continue;
                    case Some(inter): {
                        var ti1InRange = 0 < inter.ti1 && inter.ti1 < 1;
                        var ti2InRange = 0 < inter.ti2 && inter.ti2 < 1;
                        if (!ti1InRange && !ti2InRange) continue;
                        var infInterResult = rectGetSegmentIntersectionIndices(
                            rect, seg, Math.NEGATIVE_INFINITY, 
                            Math.POSITIVE_INFINITY
                        );
                        switch infInterResult {
                            case None: continue;
                            case Some(infInter): {
                                itemQueryInfos.push({
                                    item: item,
                                    ti1: inter.ti1,
                                    ti2: inter.ti2,
                                    weight: Math.min(infInter.ti1, infInter.ti2)
                                });
                            }
                        }
                    }
                }
            }
        }
        itemQueryInfos.sort(sortByWeight);
        return itemQueryInfos;
    }

    public function addResponse(colKind:String, response:ResponseFunc<T>) {
        responses[OTHER(colKind)] = response;
    }

    public function project(item:T, rect:Rect, goal:VectorFloat2, 
    ?filter:ColFilterFunc<T>):Array<Collision<T>>
    {
        assertIsRect(rect.x, rect.y, rect.width, rect.height).sure();
        if (filter == null) filter = defaultFilter;
        var collisions = new Array<Collision<T>>();
        var visited = new Map<T, Bool>();
        visited[item] = true;
        var tl = Math.min(goal.x, rect.x);
        var tt = Math.min(goal.y, rect.y);
        var tr = Math.max(goal.x+rect.width, rect.x+rect.width);
        var tb = Math.max(goal.y+rect.height, rect.y+rect.height);
        var tw = tr-tl;
        var th = tb-tt;
        var tRect = {x:tl, y:tt, w:tw, h:th}
        var cellRect = gridToCellRect(cellSize, tRect);
        var itemsInCellRect = getDictItemsInCellRect(cellRect);
        for (other => _ in itemsInCellRect) {
            if (visited.exists(other)) continue;
            visited[other] = true;
            var colKind = filter(item, other);
            switch colKind {
                case NONE: continue;
                case SLIDE, BOUNCE, CROSS, TOUCH, OTHER(_): {
                    var otherRect = rects[other];
                    var col = rectDetectCollision(rect, otherRect, goal);
                    switch col {
                        case None: {}
                        case Some(col): {
                            col.other = other;
                            col.item = item;
                            col.kind = colKind;
                            collisions.push(col);
                        }
                    }
                }
            }
        }
        collisions.sort(sortByTiAndDistance);
        return collisions;
    }

    public function countCells():Int {
        var count = 0;
        for (_ => row in rows) {
            for (_ => _ in row) {
                count += 1;
            }
        }
        return count;
    }

    public function hasItem(item:T):Bool {
        return rects.exists(item);
    }

    public function getItems():Array<T> {
        var items = new Array<T>();
        for (item => _ in rects) {
            items.push(item);
        }
        return items;
    }

    public function countItems():Int {
        var count = 0;
        for (_ in rects) count += 1;
        return count;
    }

    public function getRect(item:T):Outcome<Rect, Error> {
        if (rects.exists(item)) {
            var _rect = rects[item];
            return Success({x:_rect.x, y:_rect.y, w:_rect.width, h:_rect.height});
        }
        else {
            return Failure(new Error('Item ${item} must be added to the world before getting its rect. Use World.add() to add it first.'));
        }
    }

    public function toWorld(cellPoint:VectorInt2):VectorFloat2 {
        return gridToWorld(cellSize, cellPoint);
    }

    public function toCell(point:VectorFloat2):VectorInt2 {
        return gridToCell(cellSize, point);
    }

    public function add(item:T, x:Float, y:Float, w:Float, h:Float)
    :Outcome<Noise, Error> 
    {
        if (rects.exists(item)) {
            return Failure(new Error("Item already added to world."));
        }
        switch assertIsRect(x, y, w, h) {
            case Failure(failure): return Failure(failure);
            case Success(_): {}
        }
        rects[item] = {x:x, y:y, w:w, h:h};
        var cellRect = gridToCellRect(cellSize, rects[item]);
        for (cy in Std.int(cellRect.y)...Std.int(cellRect.y+cellRect.height)) {
            for (cx in Std.int(cellRect.x)...Std.int(cellRect.x+cellRect.width)) {
                addItemToCell(item, {x:cx, y:cy});
            }
        }
        return Success(Noise);
    }

    public function remove(item:T):Outcome<Noise, Error> {
        if (!rects.exists(item)) return Failure(new Error("Item not in world."));
        var rect = getRect(item).sure();
        rects.remove(item);
        var cellRect = gridToCellRect(cellSize, rect);
        for (cy in Std.int(cellRect.y)...Std.int(cellRect.y+cellRect.height)) {
            for (cx in Std.int(cellRect.x)...Std.int(cellRect.x+cellRect.width)) {
                removeItemFromCell(item, {x:cx, y:cy});
            }
        }
        return Success(Noise);
    }

    public function update(item:T, x2:Float, y2:Float, ?w2:Float, ?h2:Float)
    :Outcome<Noise, Error>
    {
        var rect1:Rect;
        switch getRect(item) {
            case Failure(failure): return Failure(failure);
            case Success(_): rect1 = rects[item];
        }
        if (w2 == null) w2 = rect1.width;
        if (h2 == null) h2 = rect1.height;
        switch assertIsRect(x2, y2, w2, h2) {
            case Failure(failure): return Failure(failure);
            case Success(_): {}
        }
        if (rect1.x == x2 && rect1.y == y2 && rect1.width == w2 && rect1.height == h2) {
            return Success(Noise);
        }
        var cellRect1 = gridToCellRect(cellSize, rect1);
        var cellRect2 = gridToCellRect(cellSize, {x:x2, y:y2, w:w2, h:h2});
        if (cellRect1.x == cellRect2.x && cellRect1.y == cellRect2.y
        && cellRect1.width == cellRect2.width && cellRect1.height == cellRect2.height)
        {
            rect1.x = x2;
            rect1.y = y2;
            rect1.width = w2;
            rect1.height = h2;
            return Success(Noise);
        }
        var cr1 = cellRect1.x + cellRect1.width;
        var cb1 = cellRect1.y + cellRect1.height;
        var cr2 = cellRect2.x + cellRect2.width;
        var cb2 = cellRect2.y + cellRect2.height;
        var cyOut = false;
        for (cy in Std.int(cellRect1.y)...Std.int(cb1)) {
            cyOut = cy < cellRect2.y || cy > cb2;
            for (cx in Std.int(cellRect1.x)...Std.int(cr1)) {
                if (cyOut || cx < cellRect2.x || cx > cr2) {
                    removeItemFromCell(item, {x:cx, y:cy});
                }
            }
        }
        for (cy in Std.int(cellRect2.y)...Std.int(cb2)) {
            cyOut = cy < cellRect1.y || cy > cb1;
            for (cx in Std.int(cellRect2.x)...Std.int(cr2)) {
                if (cyOut || cx < cellRect1.x || cx > cr1) {
                    addItemToCell(item, {x:cx, y:cy});
                }
            }
        }
        rect1.x = x2;
        rect1.y = y2;
        rect1.width = w2;
        rect1.height = h2;
        return Success(Noise);
    }

    public function move(item:T, goalX:Float, goalY:Float, 
    ?filter:ColFilterFunc<T>):Outcome<MoveResult<T>, Error> {
        switch check(item, goalX, goalY, filter) {
            case Failure(failure): return Failure(failure);
            case Success(checkResult): {
                switch update(item, checkResult.actualX, checkResult.actualY) {
                    case Success(_): return Success(checkResult);
                    case Failure(failure): return Failure(failure);
                }
            }
        }
    }

    public function check(item:T, goalX:Float, goalY:Float,
    ?filter:ColFilterFunc<T>):Outcome<MoveResult<T>, Error>
    {
        if (filter == null) filter = defaultFilter;
        var visited = new Map<T, Bool>();
        visited[item] = true;
        var visitedFilter = function(itm:T, other:T):CollisionKind {
            if (visited.exists(other)) return NONE;
            return filter(itm, other);
        }
        var result:MoveResult<T> = {
            actualX: 0,
            actualY: 0,
            cols: []
        }
        var rectOutcome = getRect(item);
        var rect:Rect;
        switch rectOutcome {
            case Failure(failure): return Failure(failure);
            case Success(r): rect = r;
        }
        var goal = {x:goalX, y:goalY}
        var projectedCols = project(item, rect, goal, visitedFilter);
        while (projectedCols.length > 0) {
            var col = projectedCols[0];
            result.cols.push(col);
            visited[col.other] = true;
            var response = responses[col.kind];
            var responseData = response(this, col, rect, goal, visitedFilter);
            goal = responseData.goal;
            projectedCols = responseData.cols;
        }
        result.actualX = goal.x;
        result.actualY = goal.y;
        return Success(result);
    }
}

/*            
    
    function World:queryRect(x,y,w,h, filter)
    
      assertIsRect(x,y,w,h)
    
      local cl,ct,cw,ch = grid_toCellRect(self.cellSize, x,y,w,h)
      local dictItemsInCellRect = getDictItemsInCellRect(self, cl,ct,cw,ch)
    
      local items, len = {}, 0
    
      local rect
      for item,_ in pairs(dictItemsInCellRect) do
        rect = self.rects[item]
        if (not filter or filter(item))
        and rect_isIntersecting(x,y,w,h, rect.x, rect.y, rect.w, rect.h)
        then
          len = len + 1
          items[len] = item
        end
      end
    
      return items, len
    end
    
    function World:queryPoint(x,y, filter)
      local cx,cy = self:toCell(x,y)
      local dictItemsInCellRect = getDictItemsInCellRect(self, cx,cy,1,1)
    
      local items, len = {}, 0
    
      local rect
      for item,_ in pairs(dictItemsInCellRect) do
        rect = self.rects[item]
        if (not filter or filter(item))
        and rect_containsPoint(rect.x, rect.y, rect.w, rect.h, x, y)
        then
          len = len + 1
          items[len] = item
        end
      end
    
      return items, len
    end
    
    function World:querySegment(x1, y1, x2, y2, filter)
      local itemInfo, len = getInfoAboutItemsTouchedBySegment(self, x1, y1, x2, y2, filter)
      local items = {}
      for i=1, len do
        items[i] = itemInfo[i].item
      end
      return items, len
    end
    
    function World:querySegmentWithCoords(x1, y1, x2, y2, filter)
      local itemInfo, len = getInfoAboutItemsTouchedBySegment(self, x1, y1, x2, y2, filter)
      local dx, dy        = x2-x1, y2-y1
      local info, ti1, ti2
      for i=1, len do
        info  = itemInfo[i]
        ti1   = info.ti1
        ti2   = info.ti2
    
        info.weight  = nil
        info.x1      = x1 + dx * ti1
        info.y1      = y1 + dy * ti1
        info.x2      = x1 + dx * ti2
        info.y2      = y1 + dy * ti2
      end
      return itemInfo, len
    end
    
    -- Public library functions
    
    bump.newWorld = function(cellSize)
      cellSize = cellSize or 64
      assertIsPositiveNumber(cellSize, 'cellSize')
      local world = setmetatable({
        cellSize       = cellSize,
        rects          = {},
        rows           = {},
        nonEmptyCells  = {},
        responses = {}
      }, World_mt)
    
      world:addResponse('touch', touch)
      world:addResponse('cross', cross)
      world:addResponse('slide', slide)
      world:addResponse('bounce', bounce)
    
      return world
    end
    
    bump.rect = {
      getNearestCorner              = rect_getNearestCorner,
      getSegmentIntersectionIndices = rect_getSegmentIntersectionIndices,
      getDiff                       = rect_getDiff,
      containsPoint                 = rect_containsPoint,
      isIntersecting                = rect_isIntersecting,
      getSquareDistance             = rect_getSquareDistance,
      detectCollision               = rect_detectCollision
    }
    
    bump.responses = {
      touch  = touch,
      cross  = cross,
      slide  = slide,
      bounce = bounce
    }
    
    return bump
*/