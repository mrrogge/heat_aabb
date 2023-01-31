package heat.aabb;

using tink.CoreApi;
using heat.AllCore;

typedef EntityId = Int;

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

private class Cell {
    public final index:VectorInt2;
    public final items = new Map<EntityId, Bool>();
    public var itemCount(default, null) = 0;

    public function new(index:IVector2<Int>) {
        this.index = new VectorInt2(index.x, index.y);
    }

    public function addItem(item:EntityId):Void {
        if (!items.exists(item)) {
            items[item] = true;
            itemCount += 1;
        }
    }

    public function removeItem(item:EntityId):Outcome<Noise, Error> {
        return if (items.remove(item)) {
            itemCount -= 1;
            Success(Noise);
        }
        else {
            Failure(new Error("Item not found in cell"));
        }
    }
}

/**
    Defines an intersection between a rectangle and a line segment.
**/
private class RectSegmentIntersection {
    public var ti1 = 0.;
    public var ti2 = 0.;
    public final normal1 = new MVectorInt2();
    public final normal2 = new MVectorInt2();

    public function new() {}

    public function init():RectSegmentIntersection {
        ti1 = 0.;
        ti2 = 0.;
        normal1.init();
        normal2.init();
        return this;
    }
}

/**
    Holds the results of a collision between two rects.
**/
private class Collision {
    public final movingRect = new MRect();
    public final otherRect = new MRect();

    // This is set to true if the two rects were already overlapping before the move.
    public var wasOverlapping = false;

    // This specifies how far in to the move the collision occurred - 0=immediately, 1=at the very end of the move.
    public var ti = 0.;

    public final move = new MVectorFloat2();
    public final normal = new MVectorInt2();
    public final touch = new MVectorFloat2();
    public final slide = new MVectorFloat2();
    public final bounce = new MVectorFloat2();

    public var kind:CollisionKind = NONE;

    public function new() {}

    public function init():Collision {
        movingRect.init();
        otherRect.init();
        wasOverlapping = false;
        ti = 0;
        move.init();
        normal.init();
        touch.init();
        slide.init();
        bounce.init();
        kind = NONE;
        return this;
    }
}

/**
    Data for a single collision instance.
**/
// typedef Collision = {
//     overlaps:Bool,
//     ti:Float,
//     moveX:Float,
//     moveY:Float,
//     normalX:Int,
//     normalY:Int,
//     touchX:Float,
//     touchY:Float,
//     item:EntityId,
//     itemRect:Rect,
//     other:EntityId,
//     otherRect:Rect,
//     kind:CollisionKind,
//     slideX:Option<Float>,
//     slideY:Option<Float>,
//     bounceX:Option<Float>,
//     bounceY:Option<Float>
// }

// grid_traverse* functions are based on "A Fast Voxel Traversal Algorithm for Ray Tracing",
// by John Amanides and Andrew Woo - http://www.cse.yorku.ca/~amana/research/grid.pdf
// It has been modified to include both cells when the ray "touches a grid corner",
// and with a different exit condition

private typedef GridTraversalData = {
    step:Int,
    td:Float,
    tmax:Float
}

typedef ResponseData = {
    goalX:Float,
    goalY:Float,
    cols:Array<Collision>
}

/**
    Function signature for a collision response.
**/
typedef ResponseFunc = (world:World, col:Collision, 
    rect:IRect, goalX:Float, goalY:Float, filter:ColFilterFunc)->ResponseData;

/**
    Function signature for a collision filter.
**/
typedef ColFilterFunc = (item:EntityId, other:EntityId)->CollisionKind;

typedef ItemQueryInfo = {item:EntityId, ti1:Float, ti2:Float, weight:Float};

/**
    Result of an attempted move.
**/
typedef MoveResult = {actualX:Float, actualY:Float, cols:Array<Collision>}

class World {
    public final cellSize:Int;

    final rects = new Map<EntityId, MRect>();
    final rows = new Map<Int, Map<Int, Cell>>();
    final nonEmptyCells = new Map<Cell, Bool>();
    final responses = new Map<CollisionKind, ResponseFunc>();

    final collisionArrayPool:Pool<Array<Collision>>;
    final collisionPool:Pool<Collision>;
    final rectSegmentIntersectionPool:Pool<RectSegmentIntersection>;
    final rectPool:Pool<MRect>;
    final pointPool:Pool<MVectorFloat2>;
    final pointIntPool:Pool<MVectorInt2>;
    final segmentPool:Pool<MLineSegment>;
    final mapIdToBoolPool:Pool<Map<EntityId, Bool>>;

    public function new(cellSize=64) {
        this.cellSize = cellSize <= 0 ? 64 : cellSize;

        // responses[SLIDE] = slide;
        // responses[TOUCH] = touch;
        // responses[CROSS] = cross;
        // responses[BOUNCE] = bounce;

        collisionArrayPool = new Pool(collisionArrayConstructor, collisionArrayInit);
        collisionPool = new Pool(collisionConstructor, collisionInit);
        rectSegmentIntersectionPool = new Pool(
            rectSegmentIntersectionConstructor,
            rectSegmentIntersectionInit
        );
        rectPool = new Pool(rectConstructor, rectInit);
        pointPool = new Pool(pointConstructor, pointInit);
        pointIntPool = new Pool(pointIntConstructor, pointIntInit);
        segmentPool = new Pool(segmentConstructor, segmentInit);
        mapIdToBoolPool = new Pool(mapIdToBoolConstructor, mapIdToBoolInit);
    }

    public function add(item:EntityId, rect:IRect):Outcome<Noise, Error> {
        if (rects.exists(item)) {
            return Failure(itemNotAddedError(item));
        }
        rects[item] = rectPool.get().init(rect.pos, rect.dim, rect.offset);
        var cellRect = convertWorldRectToCellCoords(rects[item]);
        var cellIndex = pointIntPool.get();
        for (cellRow in Std.int(cellRect.topY)...Std.int(cellRect.bottomY)+1) {
            for (cellCol in Std.int(cellRect.leftX)...Std.int(cellRect.rightX)+1) {
                addItemToCell(item, cellIndex.init(cellCol, cellRow));
            }
        }
        rectPool.put(cellRect);
        pointIntPool.put(cellIndex);
        return Success(Noise);
    }

    public function getRect(item:EntityId):Outcome<Rect, Error> {
        if (rects.exists(item)) {
            return Success(rects[item].toImmutable());
        }
        else {
            return Failure(itemNotAddedError(item));
        }
    }

    function itemNotAddedError(item:EntityId):Error {
        return new Error(NotFound, 'Item ${item} not added');
    }

    public function update(item:EntityId, pos:IVector2<Float>, ?dim:IVector2<Float>, ?offset:IVector2<Float>)
    :Outcome<Noise, Error>
    {
        var rect1 = if (rects.exists(item)) {
            rects[item];
        }
        else {
            return Failure(itemNotAddedError(item));
        }
        var rect2 = rectPool.get().initPos(pos)
            .initDim(dim == null ? rect1.dim : dim)
            .initOffset(offset == null ? rect1.offset : offset);

        // If item hasn't moved, return early
        if (Rect.areSame(rect1, rect2)) {
            rectPool.put(rect2);
            return Success(Noise);
        }

        var cellRect1 = convertWorldRectToCellCoords(rect1);
        var cellRect2 = convertWorldRectToCellCoords(rect2);
        
        // If item has not moved into any different cells, return early
        if (Rect.areSame(cellRect1, cellRect2)) {
            rect1.initFrom(rect2);
            rectPool.put(rect2).put(cellRect1).put(cellRect2);
            return Success(Noise);
        }

        var cellIndex = pointIntPool.get();
        for (cellRow in Std.int(cellRect1.topY)...Std.int(cellRect1.bottomY)+1) {
            for (cellCol in Std.int(cellRect1.leftX)...Std.int(cellRect1.rightX)+1) {
                removeItemFromCell(item, cellIndex.init(cellCol, cellRow));
            }
        }
        for (cellRow in Std.int(cellRect2.topY)...Std.int(cellRect2.bottomY)+1) {
            for (cellCol in Std.int(cellRect2.leftX)...Std.int(cellRect2.rightX)+1) {
                addItemToCell(item, cellIndex.init(cellCol, cellRow));
            }
        }

        rect1.initFrom(rect2);
        rectPool.put(rect2).put(cellRect1).put(cellRect2);
        pointIntPool.put(cellIndex);

        return Success(Noise);
    }

    public function remove(item:EntityId):Outcome<Noise, Error> {
        if (!rects.exists(item)) return Failure(itemNotAddedError(item));
        var rect = rects[item];
        rects.remove(item);
        var cellRect = convertWorldRectToCellCoords(rect);
        var cellIndex = pointIntPool.get();
        for (cellRow in Std.int(cellRect.topY)...Std.int(cellRect.bottomY)+1) {
            for (cellCol in Std.int(cellRect.leftX)...Std.int(cellRect.rightX)+1) {
                removeItemFromCell(item, cellIndex.init(cellCol, cellRow));
            }
        }

        rectPool.put(rect).put(cellRect);
        pointIntPool.put(cellIndex);

        return Success(Noise);
    }

    public function project(item:EntityId, rect:IRect, goal:IVector2<Float>,
    ?filter:ColFilterFunc):Array<Collision>
    {
        if (filter == null) filter = defaultFilter;
        var collisions = collisionArrayPool.get();
        var visited = mapIdToBoolPool.get();
        visited[item] = true;
        // Construct a cell rectangle range that encompasses the projected item and the goal position. This determines which items to test for collisions.
        var rectLeftX = Math.min(goal.x, rect.leftX);
        var rectTopY = Math.min(goal.y, rect.topY);
        var rectRightX = Math.max(goal.x+rect.width, rect.rightX);
        var rectBottomY = Math.max(goal.y+rect.height, rect.bottomY);
        var rectWidth = rectRightX-rectLeftX;
        var rectHeight = rectBottomY-rectTopY;
        var rect = rectPool.get();
        rect.pos.init(rectLeftX, rectTopY);
        rect.dim.init(rectWidth, rectHeight);
        var cellRect = convertWorldRectToCellCoords(rect);

        // Find all items in all checked cells. Test for collisions against these and collect all the resulting collisions.
        var itemsInCellRect = getDictItemsInCellRect(cellRect);
        for (other => _ in itemsInCellRect) {
            if (visited.exists(other)) continue;
            visited[other] = true;
            var colKind = filter(item, other);
            switch colKind {
                case NONE: continue;
                case SLIDE, BOUNCE, CROSS, TOUCH, OTHER(_): {
                    #if heat_assert if (!rects.exists(other)) throw new Error(); #end
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

        mapIdToBoolPool.put(visited).put(itemsInCellRect);
        rectPool.put(tRect).put(cellRect);

        return collisions;
    }

    public function check(item:EntityId, goal:IVector2<Float>,
    ?filter:ColFilterFunc):Outcome<MoveResult, Error>
    {
        if (filter == null) filter = defaultFilter;
        var visited = mapIdToBoolPool.get();
        visited[item] = true;
        // TODO: can this function be factored out somehow?
        var visitedFilter = function(itm:T, other:T):CollisionKind {
            if (visited.exists(other)) return NONE;
            return filter(itm, other);
        }
        var result:MoveResult<T> = {
            actualX: 0,
            actualY: 0,
            cols: []
        }
        var rect = if (this.rects.exists(item)) {
            this.rects[item];
        }  
        else {
            mapIdToBoolPool.put(visited);
            return Failure(itemNotAddedError(item));
        }
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

    inline function collisionConstructor():Collision {
        return new Collision();
    }

    inline function collisionInit(col:Collision):Collision {
        return col.init();
    }

    inline function collisionArrayConstructor():Array<Collision> {
        return [];
    }

    function collisionArrayInit(x:Array<Collision>):Array<Collision> {
        while (x.length > 0) x.pop();
        return x;
    }

    inline function rectSegmentIntersectionConstructor():RectSegmentIntersection {
        return new RectSegmentIntersection();
    }

    function rectSegmentIntersectionInit(int:RectSegmentIntersection):RectSegmentIntersection {
        return int.init();
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

    inline function mapIdToBoolConstructor():Map<EntityId, Bool> {
        return [];
    }

    inline function mapIdToBoolInit(map:Map<EntityId, Bool>):Map<EntityId, Bool> {
        map.clear();
        return map;
    }

    
    function defaultFilter(item:EntityId, other:EntityId):CollisionKind {
        return SLIDE;
    }
    
    function rectGetSegmentIntersectionIndices(rect:IRect, seg:ILineSegment, ti1=0., 
    ti2=1.):haxe.ds.Option<RectSegmentIntersection>
    {
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
        result.normal1.x = nx1;
        result.normal1.y = ny1;
        result.normal2.x = nx2;
        result.normal2.y = ny2;
        return Some(result);
    }
    
    function rectGetSquareDist(rect1:IRect, rect2:IRect):Float
    {
        var dx = rect1.leftX - rect2.leftX + (rect1.width - rect2.width)/2;
        var dy = rect1.topY - rect2.topY + (rect1.height - rect2.height)/2;
        return dx*dx + dy*dy;
    }
    
    function rectDetectCollision(rect1:IRect, rect2:IRect, goal:IVector2<Float>):haxe.ds.Option<Collision>
    {
        var col = collisionPool.get();
        var displacement = pointPool.get().init(goal.x-rect1.x, goal.y-rect1.y);
        var rectDiff = rectPool.get()
            .initFrom(rect1);
        rectDiff.diffWith(rect2, rectDiff);
        col.wasOverlapping = rectDiff.containsPoint(VectorFloat2.ORIGIN);
        if (col.wasOverlapping) {
            var nearestCorner = rectDiff.nearestCornerTo(VectorFloat2.ORIGIN, 
                pointPool.get());
            var wi = Math.min(rect1.width, Math.abs(nearestCorner.x));
            var hi = Math.min(rect1.height, Math.abs(nearestCorner.y));
            col.ti = -wi * hi;

            if (displacement.lengthSquared() == 0) {
                //intersecting and not moving - use minimum displacement vector
                if (Math.abs(nearestCorner.x) < Math.abs(nearestCorner.y)) {
                    col.normal.x = Math.sign(nearestCorner.x);
                    col.normal.y = 0;
                    col.touch.x = rect1.x + nearestCorner.x;
                    col.touch.y = rect1.y;
                }
                else {
                    col.normal.x = 0;
                    col.normal.y = Math.sign(nearestCorner.y);
                    col.touch.x = rect1.x;
                    col.touch.y = rect1.y + nearestCorner.y;
                }
            }
            else {
                //intersecting and moving - move in opposite direction
                var seg = segmentPool.get().init(0, 0, displacement.x, displacement.y);
                var segInt = rectGetSegmentIntersectionIndices(rectDiff, seg, 
                    Math.NEGATIVE_INFINITY, 1);
                segmentPool.put(seg);
                switch segInt {
                    case None: {
                        pointPool.put(nearestCorner);
                        rectPool.put(rectDiff);
                        return None;
                    }
                    case Some(segInt): {
                        col.normal.initFrom(segInt.normal1);
                        col.touch.x = rect1.x + displacement.x * segInt.ti1;
                        col.touch.y = rect1.y + displacement.y * segInt.ti1;
                        rectSegmentIntersectionPool.put(segInt);
                    }
                }
            }
            pointPool.put(nearestCorner);
        }
        else {
            var seg = segmentPool.get().init(0, 0, displacement.x, displacement.y);
            var segInt = rectGetSegmentIntersectionIndices(rectDiff, 
                seg, Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY);
            segmentPool.put(seg);
            switch segInt {
                case None: {
                    rectPool.put(rectDiff);
                    return None;
                }
                case Some(segInt): {
                    if (segInt.ti1 < 1 
                    && Math.abs(segInt.ti1 - segInt.ti2) >= Math.FP_ERR() 
                    && (0 < segInt.ti1 + Math.FP_ERR() || 0 == segInt.ti1 && segInt.ti2 > 0))
                    {
                        col.ti = segInt.ti1;
                        col.normal.initFrom(segInt.normal1);
                        col.touch.x = rect1.x + displacement.x * col.ti;
                        col.touch.y = rect1.y + displacement.y * col.ti;
                    }
                    else {
                        rectSegmentIntersectionPool.put(segInt);
                        rectPool.put(rectDiff);
                        return None;
                    }
                    rectSegmentIntersectionPool.put(segInt);
                }
            }
        }

        rectPool.put(rectDiff);
    
        return Some(col);
    }
    
    function gridToWorld(cellSize:Int, point:IVector2<Int>):MVectorFloat2 {
        return pointPool.get()
            .init((point.x-1)*cellSize, (point.y-1)*cellSize);
    }
    
    /**
        Converts from a point in world coordinates to cell coordinates.

        Points that are right on the edge between two cells are considered to be within only the cell furthest to the right and down.
    **/
    function convertWorldPointToCellCoords(point:IVector2<Float>, ?dest:MVectorInt2):MVectorInt2 {
        if (dest == null) dest = pointIntPool.get();
        return dest.init(Math.floor(point.x / cellSize),
            Math.floor(point.y / cellSize));
    }

    function sortByWeight(a:ItemQueryInfo, b:ItemQueryInfo):Int {
        return a.weight < b.weight ? -1 : a.weight == b.weight ? 0 : 1;
    }

    function sortByTiAndDistance(a:Collision, b:Collision):Int {
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
        var cell1 = convertWorldPointToCellCoords(cellSize, p1);
        var cell2 = convertWorldPointToCellCoords(cellSize, p2);
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
    
    /**
        For the specified rect in world coordinates, return a rect corresponding to the cell indices that rect occupies.
    **/
    function convertWorldRectToCellCoords(rect:IRect, ?dest:MRect):MRect {
        if (dest == null) dest = rectPool.get();
        var rectTopLeft = pointPool.get().init(rect.leftX, rect.topY);
        var rectBottomRight = pointPool.get().init(rect.rightX, rect.bottomY);
        var topLeftCell = convertWorldPointToCellCoords(rectTopLeft);
        var bottomRightCell = convertWorldPointToCellCoords(rectBottomRight);
        #if heat_assert 
        if (topLeftCell.x > bottomRightCell.x) throw new Error();
        if (topLeftCell.y > bottomRightCell.y) throw new Error();
        #end
        dest.pos.init(topLeftCell.x, topLeftCell.y);
        dest.dim.init(bottomRightCell.x-topLeftCell.x, bottomRightCell.y-topLeftCell.y);
        dest.offset.init(0, 0);
        pointPool.put(rectTopLeft).put(rectBottomRight);
        pointIntPool.put(topLeftCell).put(bottomRightCell);
        return dest;
    }

    function touch(world:World, col:Collision, rect:IRect, goalX:Float, 
    goalY:Float, filter:ColFilterFunc):ResponseData
    {
        return {goalX:col.touchX, goalY:col.touchY, cols:new Array<Collision<T>>()}
    }
    
    function cross(world:World, col:Collision, rect:IRect, goalX:Float, 
    goalY:Float, filter:ColFilterFunc):ResponseData
    {
        return {
            goalX:goalX,
            goalY:goalY,
            cols:world.project(col.item, rect, goalX, goalY, filter)
        }
    }
    
    function slide(world:World, col:Collision, rect:IRect, goalX:Float,
    goalY:Float, filter:ColFilterFunc):ResponseData 
    {
        var newGoal = pointPool.get();
        if (col.moveX != 0 || col.moveY != 0) {
            if (col.normalX != 0) {
                newGoal.x = col.touchX;
            }
            else {
                newGoal.y = col.touchY;
            }
        }
        col.slideX = Some(newGoal.x);
        col.slideY = Some(newGoal.y);
        var newRect = rectPool.get().init(col.touchX, col.touchY, rect.width, rect.height);
        var result = {
            goalX: newGoal.x,
            goalY: newGoal.y,
            cols:world.project(col.item, newRect, newGoal, filter)
        };
        return result;
    }
    
    function bounce(world:World, col:Collision, rect:IRect, goal:IVector2<Float>, 
    filter:ColFilterFunc):ResponseData 
    {
        var newGoal = pointPool.get().init(goal.x, goal.y);
        var bx = col.touchX;
        var by = col.touchY;
        if (col.moveX != 0 || col.moveY != 0) {
            var bnx = newGoal.x - col.touchX;
            var bny = newGoal.y - col.touchY;
            if (col.normalX == 0) {
                bny *= -1;
            }
            else {
                bnx *= -1;
            }
            bx = col.touchX + bnx;
            by = col.touchY + bny;
        }
        col.bounceX = Some(bx);
        col.bounceY = Some(by);
        var newRect = rectPool.get()
            .init(col.touchX, col.touchY, rect.width, rect.height);
        newGoal.x = bx;
        newGoal.y = by;
        return {
            goalX:newGoal.x,
            goalY:newGoal.y,
            cols:world.project(col.item, newRect, newGoal, filter)
        }
    }

    function addItemToCell(item:EntityId, index:IVector2<Int>) {
        if (!this.rows.exists(index.y)) this.rows[index.y] = new Map<Int, Cell>();
        var row = this.rows[index.y];
        if (!row.exists(index.x)) {
            row[index.x] = new Cell(index);
        }
        var cell = row[index.x];
        nonEmptyCells[cell] = true;
        cell.addItem(item);
    }

    function removeItemFromCell(item:EntityId, index:IVector2<Int>):Outcome<Noise, Error> {
        if (!rows.exists(index.y)) return Failure(new Error(NotFound, "Row is empty"));
        var row = rows[index.y];
        if (!row.exists(index.x)) return Failure(new Error(NotFound, "Column is empty"));
        var cell = row[index.x];
        if (!cell.items.exists(item)) return Failure(new Error(NotFound, "Item not found in cell"));
        cell.removeItem(item);
        if (cell.itemCount <= 0) {
            nonEmptyCells.remove(cell);
        }
        return Success(Noise);
    }

    /**
        Returns a map where keys are all EntityIds currently found within all cells contained within cellRect.
    **/
    function getDictItemsInCellRect(cellRect:IRect):Map<EntityId, Bool> {
        var itemsDict = mapIdToBoolPool.get();
        for (cellRow in Std.int(cellRect.topY)...Std.int(cellRect.bottomY)+1) {
            if (!this.rows.exists(cellRow)) continue;
            var row = this.rows[cellRow];
            for (cellCol in Std.int(cellRect.leftX)...Std.int(cellRect.rightX)+1) {
                if (!row.exists(cellCol)) continue;
                var cell = row[cellCol];
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
    ?filter:(item:EntityId)->Bool):Array<ItemQueryInfo>
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

    public function addResponse(colKind:String, response:ResponseFunc) {
        responses[OTHER(colKind)] = response;
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

    public inline function hasItem(item:EntityId):Bool {
        return rects.exists(item);
    }

    public function getItems():Array<EntityId> {
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

    public function move(item:EntityId, goalX:Float, goalY:Float, 
    ?filter:ColFilterFunc):Outcome<MoveResult, Error> {
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