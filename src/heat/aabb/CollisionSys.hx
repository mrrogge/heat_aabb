package heat.aabb;

import heat.ecs.*;
import core.*;
import heat.core.*;

using tink.core.Option.OptionTools;

//https://blog.hamaluik.ca/posts/swept-aabb-collision-using-minkowski-difference/

private class Cell {
    public var row(default, null):Int;
    public var col(default, null):Int;
    public var size(default, null):Int;
    public var ids(default, null) = new Map<EntityId, Bool>();
    public var rect:MRect;

    public function new(row=0, col=0, size=64) {
        this.row = row;
        this.col = col;
        this.size = size;
        this.rect = new MRect(col*size, row*size, size, size);
    }
}

private typedef RectLineIntersection = {
    final ti1:Float;
    final ti2:Float;
    final nx1:Float;
    final ny1:Float;
    final nx2:Float;
    final ny2:Float;
}

class CollisionSys {
    //tolerance for collisions
    public static inline final EPSILON = 1e-7;
    // public static inline final EPSILON = 0;

    //signal for when collisions are detected
    public var collisionSignal(default, null):heat.event.ISignal<ECollision>;

    //private emitter for collision signal
    var collisionEmitter = new heat.event.SignalEmitter<ECollision>();

    //query for all collidables
    var query = new heat.ecs.ComQuery();

    //collidable map
    var collidables:heat.ecs.ComMap<Collidable>;

    //x/y dimension of each cell in spatial hash
    var cellSize:Int;

    //container for all cell instances
    var cells = new Map<Int, Map<Int, Cell>>();

    //holds collidable data for each entity from the previous frame
    public var prevRects = new Map<EntityId, MRect>();

    //pre-allocated map of IDs for performance purposes
    var checkedIds = new Map<EntityId, Bool>();
    //pre-allocated array of cells for performance purposes
    var cellsArray = new Array<Cell>();

    //pool used for managing internal rect instances
    var rectPool:Pool<MRect>;

    //pool used for managing internal vector instances
    var vectorPool:Pool<MFloatVector2>;

    var intersectionPool:Pool<RectLineIntersection>;

    public var colCount(default, null) = 0;

    public function new(collidables:heat.ecs.ComMap<Collidable>, cellSize=64) {
        this.collidables = collidables;
        this.cellSize = cellSize;
        query.with(collidables);
        collisionSignal = collisionEmitter.signal;
        rectPool = new Pool<MRect>(()->{
            return new MRect();
        });
        vectorPool = new Pool<MFloatVector2>(()->{
            return new MFloatVector2();
        });

    }

    //A filter for detecting valid collisions; return true if the ids can collide, otherwise false.
    public dynamic function filter(id1:EntityId, id2:EntityId):Bool {
        return true;
    }

    /**
        Returns the minimum area Rect containing r1 and r2.
    **/
    function getContainingRect(r1:MRect, r2:MRect, ?dest:MRect):MRect {
        if (dest == null) dest = rectPool.get();
        dest.init(Math.min(r1.x, r2.x), Math.min(r1.y, r2.y), 
            Math.max(r1.x+r1.w, r2.x+r2.w) - Math.min(r1.x, r2.x),
            Math.max(r1.y+r1.h, r2.y+r2.h) - Math.min(r1.y, r2.y));
        return dest;
    }

    /**
        Returns the cell instance from cells, initializing it if necessary.
    **/
    function getCell(row:Int, col:Int):Cell {
        if (cells[row] == null) cells[row] = new Map<Int, Cell>();
        if (cells[row][col] == null) {
            cells[row][col] = new Cell(row, col, cellSize);
        }
        return cells[row][col];
    }

    /**
        Returns the Cell containing the point defined by x and y. If that cell doesn't exist yet, this method automatically initializes it.

        Cells are lower-bound-inclusive and upper-bound-exclusive.

        NOTE: this may need to be adjusted to include all cells touching the point, investigation needed
    **/
    function pointToCells(x:Float, y:Float, dest:Array<Cell>):Array<Cell> {
        while (dest.length > 0) dest.pop();
        dest.push(getCell(Math.floor(x/cellSize), Math.floor(y/cellSize)));
        var cell:Cell;
        if (x/cellSize - Math.floor(x/cellSize) == 0) {
            cell = getCell(Math.ceil(x/cellSize), Math.floor(y/cellSize));
            if (!dest.contains(cell)) dest.push(cell);
        }
        if (y/cellSize - Math.floor(y/cellSize) == 0) {
            cell = getCell(Math.floor(x/cellSize), Math.ceil(y/cellSize));
            if (!dest.contains(cell)) dest.push(cell);
        }       
        return dest;
    }

    /**
        Finds all cells overlapping rect and returns them in an array.
    **/
    var workingCellArray = new Array<Cell>();
    function getCellsInRect(rect:MRect, ?dest:Array<Cell>):Array<Cell> {
        if (dest == null) dest = new Array<Cell>();
        else {
            for (i in 0...dest.length) dest.pop();
        }
        pointToCells(rect.x, rect.y, dest);
        var topLeftCell = dest[0];
        pointToCells(rect.x + rect.w, rect.y + rect.h, workingCellArray);
        var bottomRightCell = workingCellArray[workingCellArray.length-1];
        for (cell in workingCellArray) {
            if (!dest.contains(cell)) dest.push(cell);
        }
        if (topLeftCell != bottomRightCell) {
            for (row in topLeftCell.row...bottomRightCell.row+1) {
                for (col in topLeftCell.col...bottomRightCell.col+1) {
                    var cell = getCell(row, col);
                    if (!dest.contains(cell)) dest.push(cell);
                }
            }
        }
        return dest;
    }

    function rotateRect180AroundOrigin(rect:MRect, ?dest:MRect):MRect {
        if (dest == null) dest = new MRect();
        dest.init(-(rect.x + rect.w), -(rect.y + rect.h), rect.w, rect.h);
        return dest;
    }

    function sumRects(r1:MRect, r2:MRect, ?dest:MRect):MRect {
        if (dest == null) dest = new MRect();
        dest.init(r1.x+r2.x, r1.y+r2.y, r1.w+r2.w, r1.h+r2.h);
        return dest;
    }

    function diffRects(r1:MRect, r2:MRect, ?dest:MRect):MRect {
        if (dest == null) dest = new MRect();
        dest.init(r1.x - r2.x - r2.w, r1.y - r2.y - r2.h, r1.w+r2.w, r1.h+r2.h);
        return dest;
    }

    function getRectLineIntersection(rect:MRect, line:Line, ti1=0., ti2=1.)
    :haxe.ds.Option<RectLineIntersection> 
    {
        var dx = line.x2-line.x1;
        var dy = line.y2-line.y1;
        var nx:Null<Float> = null;
        var ny:Null<Float> = null;
        var nx1 = 0.;
        var ny1 = 0.;
        var nx2 = 0.;
        var ny2 = 0.;
        var p:Null<Float> = null;
        var q:Null<Float> = null;
        var r:Null<Float> = null;

        for (side in 1...5) {
            if (side == 1) {
                nx = -1;
                ny = 0;
                p = -dx;
                q = line.x1 - rect.x;
            }
            else if (side == 2) {
                nx = 1;
                ny = 0;
                p = dx;
                q = rect.x + rect.w - line.x1;
            }
            else if (side == 3) {
                nx = 0;
                ny = -1;
                p = -dy;
                q = line.y1 - rect.y;
            }
            else if (side == 4) {
                nx = 0;
                ny = 1;
                p = dy;
                q = rect.y + rect.h - line.y1;
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
        return Some({
            ti1: ti1,
            ti2: ti2,
            nx1: nx1,
            ny1: ny1,
            nx2: nx2,
            ny2: ny2
        });
    }

    function normalizeRectFromCollidable(collidable:Collidable, ?destRect:MRect)
    :MRect {
        if (destRect == null) destRect = rectPool.get();
        destRect.x = collidable.rect.x - collidable.offset.x;
        destRect.y = collidable.rect.y - collidable.offset.y;
        destRect.w = collidable.rect.w;
        destRect.h = collidable.rect.h;
        return destRect;
    }

    public function getNearestCorner(rect:MRect, x:Float, y:Float, ?dest:MFloatVector2):MFloatVector2 {
        if (dest == null) dest = vectorPool.get();
        dest.x = Math.abs(rect.x - x) < Math.abs(rect.x + rect.w - x) ? rect.x : rect.x + rect.w;
        dest.y = Math.abs(rect.y - y) < Math.abs(rect.y + rect.h - y) ? rect.y : rect.y + rect.h;
        return dest;
    }

    /**
     * Sets the previous rect to the current collidable.
     * @param id 
     */
    var syncPrev_workingRect2 = new MRect();
    function syncPrev(id:EntityId, workingRect:MRect) {
        //remove from cells
        var collidable = collidables[id];
        normalizeRectFromCollidable(collidable, workingRect);
        if (!prevRects.exists(id)) {
            prevRects[id] = workingRect.clone();
        }
        getContainingRect(prevRects[id], workingRect, syncPrev_workingRect2);
        getCellsInRect(syncPrev_workingRect2, cellsArray);
        for (cell in cellsArray) {
            cell.ids.remove(id);
        }
        prevRects[id].pullFrom(workingRect);
        //add to cells
        getCellsInRect(prevRects[id], cellsArray);
        for (cell in cellsArray) {
            cell.ids[id] = true;
        }
    }

    /**
     * Updates the internal rects for each entity to the current collidable positions. 
     * 
     * This is useful for when entities move in the world but their displacement should not be handled by the collision system, e.g. teleporting. Without calling this method, the system will assume any change in position since the last frame should have collisions processed.
     */
    public function syncAll() {
        query.run();
        var rect = rectPool.get();
        for (id in query.result) {
            syncPrev(id, rect);
        }
        rectPool.put(rect);
    }

    var update_currentRect = new MRect();
    var update_movedRect = new MRect();
    var update_dv1 = new MFloatVector2();
    var update_dv2 = new MFloatVector2();
    var update_dv = new MFloatVector2();
    var update_line = new Line();
    var update_rectDiff = new MRect();
    var checkedPairs = new Map<heat.ecs.EntityId, Map<heat.ecs.EntityId, Bool>>();
    public function update(dt:Float) {
        colCount = 0;
        query.run();
        for (id in query.result) {
            var collidable = collidables[id];
            normalizeRectFromCollidable(collidable, update_currentRect);
            if (!prevRects.exists(id)) {
                prevRects[id] = update_currentRect.clone();
            }
            getContainingRect(update_currentRect, prevRects[id], update_movedRect);
            getCellsInRect(update_movedRect, cellsArray);
            for (cell in cellsArray) {
                cell.ids[id] = true;
            }
        }

        for (id1 => m in checkedPairs) {
            m.clear();
        }

        for (id1 in query.result) {
            var collidable1 = collidables[id1];
            var currentRect1 = normalizeRectFromCollidable(collidable1);
            getContainingRect(prevRects[id1], currentRect1, update_movedRect);
            getCellsInRect(update_movedRect, cellsArray);
            if (!checkedPairs.exists(id1)) checkedPairs[id1] = new Map<heat.ecs.EntityId, Bool>();
            for (cell in cellsArray) {
                for (id2 => _ in cell.ids) {
                    if (id1 == id2) continue;
                    if (checkedPairs[id1].exists(id2)) {
                        continue;
                    }
                    else {
                        checkedPairs[id1][id2] = true;
                        if (!checkedPairs.exists(id2)) checkedPairs[id2] = new Map<heat.ecs.EntityId, Bool>();
                        checkedPairs[id2][id1] = true;
                    }
                    var collidable2 = collidables[id2];
                    if (collidable2 == null) {
                        cell.ids.remove(id2);
                        prevRects.remove(id2);
                        continue;
                    }
                    if (!filter(id1, id2)) continue;
                    colCount++;
                    var currentRect2 = normalizeRectFromCollidable(collidable2);
                    update_dv1.init(
                        currentRect1.x - prevRects[id1].x,
                        currentRect1.y - prevRects[id1].y);
                    update_dv2.init(
                        currentRect2.x - prevRects[id2].x,
                        currentRect2.y - prevRects[id2].y);
                    //dv is how far id2 has moved from id1's frame of reference
                    update_dv.init(update_dv1.x-update_dv2.x, update_dv1.y-update_dv2.y);
                    //line is from the origin out in dv direction
                    update_line.init(0, 0, -update_dv.x, -update_dv.y);
                    //rectDiff is Minkowski diff of prev collidables. This tells us if they were overlapping already or not
                    diffRects(prevRects[id1], prevRects[id2], update_rectDiff);
                    var prevRect1 = prevRects[id1];
                    var prevRect2 = prevRects[id2];
                    if (update_rectDiff.containsPoint(0, 0, -1e-7)) {
                        //was already overlapping
                        var nearestCornerToOrigin = getNearestCorner(update_rectDiff, 0, 0);
                        var intersectionWidth = Math.min(collidable1.rect.w, 
                            Math.abs(nearestCornerToOrigin.x));
                        var intersectionHeight = Math.min(collidable1.rect.h,
                            Math.abs(nearestCornerToOrigin.y));
                        //Check if they are moving relative to each other or not
                        if (update_dv.x == 0 && update_dv.y == 0) {
                            //not moving relative to each other. Separate by finding the shortest displacement vector
                            var n1 = new MFloatVector2();
                            var n2 = new MFloatVector2();
                            var separateX1 = 0.;
                            var separateY1 = 0.;
                            var separateX2 = 0.;
                            var separateY2 = 0.;
                            if (Math.abs(nearestCornerToOrigin.x) < Math.abs(nearestCornerToOrigin.y)) {
                                n1.x =  nearestCornerToOrigin.x/Math.abs(nearestCornerToOrigin.x == 0 ? 1 : nearestCornerToOrigin.x);
                                n1.y = 0;
                                n2.x = -n1.x;
                                n2.y = 0;
                                separateX1 = -nearestCornerToOrigin.x;
                                separateX2 = nearestCornerToOrigin.x;
                            }
                            else {
                                n1.x = 0;
                                n1.y = nearestCornerToOrigin.y/Math.abs(nearestCornerToOrigin.y == 0 ? 1 : nearestCornerToOrigin.y);
                                n2.x = 0;
                                n2.y = -n1.y;
                                separateY1 = -nearestCornerToOrigin.y;
                                separateY2 = nearestCornerToOrigin.y; 
                            }
                            if (n1.x/Math.abs(n1.x) == update_dv1.x/Math.abs(update_dv1.x)) {
                                separateX1 -= update_dv1.x;
                            }
                            if (n2.x/Math.abs(n2.x) == update_dv2.x/Math.abs(update_dv2.x)) {
                                separateX2 -= update_dv2.x;
                            }
                            if (n1.y/Math.abs(n1.y) == update_dv1.y/Math.abs(update_dv1.y)) {
                                separateY1 -= update_dv1.y;
                            }
                            if (n2.y/Math.abs(n2.y) == update_dv2.y/Math.abs(update_dv2.y)) {
                                separateY2 -= update_dv2.y;
                            }
                            if (Math.abs(separateX1) < EPSILON) separateX1 = 0;
                            if (Math.abs(separateX2) < EPSILON) separateX2 = 0;
                            if (Math.abs(separateY1) < EPSILON) separateY1 = 0;
                            if (Math.abs(separateY2) < EPSILON) separateY2 = 0;
                            var event:ECollision = {
                                id1: id1,
                                id2: id2,
                                normal1: n1,
                                normal2: n2,
                                dx1: update_dv1.x,
                                dy1: update_dv1.y,
                                dx2: update_dv2.x,
                                dy2: update_dv2.y,
                                separateX1: separateX1,
                                separateY1: separateY1,
                                separateX2: separateX2,
                                separateY2: separateY2,
                                dt: dt
                            };
                            collisionEmitter.emit(event);
                        }
                        else {
                            //moving relative to each other. Separate along dv line, away from each other.
                            var intersection = getRectLineIntersection(update_rectDiff, update_line, Math.NEGATIVE_INFINITY, 1);
                            switch intersection {
                                case Some(intersection): {
                                    final ti1 = intersection.ti1;
                                    final ti2 = intersection.ti2;
                                    var separateX1 = 0.;
                                    var separateX2 = 0.;
                                    var separateY1 = 0.;
                                    var separateY2 = 0.;
                                    var normal1 = new MFloatVector2();
                                    var normal2 = new MFloatVector2();
                                    var edgeDist1 = 0.;
                                    var edgeDist2 = 0.;
                                    if (intersection.nx1 != 0) {
                                        edgeDist1 = ti1 * update_line.x2;
                                    }
                                    else if (intersection.ny1 != 0) {
                                        edgeDist1 = ti1 * update_line.y2;
                                    }
                                    else {
                                        edgeDist1 = Math.POSITIVE_INFINITY;
                                    }
                                    if (intersection.nx2 != 0) {
                                        edgeDist2 = ti2 * update_line.x2;
                                    }
                                    else if (intersection.ny2 != 0) {
                                        edgeDist2 = ti2 * update_line.y2;
                                    }
                                    else {
                                        edgeDist2 = Math.POSITIVE_INFINITY;
                                    }
                                    if (Math.abs(edgeDist1) < Math.abs(edgeDist2)) {
                                        normal1.x = intersection.nx1;
                                        normal1.y = intersection.ny1;
                                        normal2.x = -normal1.x;
                                        normal2.y = -normal1.y;
                                        if (normal1.x != 0) {
                                            separateX1 = -update_line.x2 * intersection.ti1;
                                        }
                                        if (normal2.x != 0) {
                                            separateX2 = update_line.x2 * intersection.ti1;
                                        }
                                        if (normal1.y != 0) {
                                            separateY1 = -update_line.y2 * intersection.ti1;
                                        }
                                        if (normal2.y != 0) {
                                            separateY2 = update_line.y2 * intersection.ti1;
                                        }
                                    }
                                    else {
                                        normal1.x = intersection.nx2;
                                        normal1.y = intersection.ny2;
                                        normal2.x = -normal1.x;
                                        normal2.y = -normal1.y;
                                        if (normal1.x != 0) {
                                            separateX1 = -update_line.x2 * intersection.ti2;
                                        }
                                        if (normal2.x != 0) {
                                            separateX2 = update_line.x2 * intersection.ti2;
                                        }
                                        if (normal1.y != 0) {
                                            separateY1 = -update_line.y2 * intersection.ti2;
                                        }
                                        if (normal2.y != 0) {
                                            separateY2 = update_line.y2 * intersection.ti2;
                                        }
                                    }
                                    if (normal1.x/Math.abs(normal1.x) == update_dv1.x/Math.abs(update_dv1.x)) {
                                        separateX1 -= update_dv1.x;
                                    }
                                    if (normal2.x/Math.abs(normal2.x) == update_dv2.x/Math.abs(update_dv2.x)) {
                                        separateX2 -= update_dv2.x;
                                    }
                                    if (normal1.y/Math.abs(normal1.y) == update_dv1.y/Math.abs(update_dv1.y)) {
                                        separateY1 -= update_dv1.y;
                                    }
                                    if (normal2.y/Math.abs(normal2.y) == update_dv2.y/Math.abs(update_dv2.y)) {
                                        separateY2 -= update_dv2.y;
                                    }
                                    if (Math.abs(separateX1) < EPSILON) separateX1 = 0;
                                    if (Math.abs(separateX2) < EPSILON) separateX2 = 0;
                                    if (Math.abs(separateY1) < EPSILON) separateY1 = 0;
                                    if (Math.abs(separateY2) < EPSILON) separateY2 = 0;
                                    var event:ECollision = {
                                        id1: id1,
                                        id2: id2,
                                        normal1: normal1,
                                        normal2: normal2,
                                        dx1: update_dv1.x,
                                        dy1: update_dv1.y,
                                        dx2: update_dv2.x,
                                        dy2: update_dv2.y,
                                        separateX1: separateX1,
                                        separateX2: separateX2,
                                        separateY1: separateY1,
                                        separateY2: separateY2,
                                        dt: dt
                                    }
                                    collisionEmitter.emit(event);
                                }
                                case None: {}
                            }
                        }
                    }
                    else {  
                        //was not overlapping, check if tunneled into each other 
                        var intersection = getRectLineIntersection(update_rectDiff, update_line,
                            0, 1);
                        switch intersection {
                            case Some(intersection): {
                                final ti1 = intersection.ti1;
                                final ti2 = intersection.ti2;
                                var normal1 = new MFloatVector2();
                                normal1.x = intersection.nx1;
                                normal1.y = intersection.ny1;
                                var normal2 = new MFloatVector2();
                                normal2.x = -normal1.x;
                                normal2.y = -normal1.y;
                                var separateX1 = 0.;
                                var separateX2 = 0.;
                                var separateY1 = 0.;
                                var separateY2 = 0.;
                                if (normal1.x != 0) {
                                    separateX1 = -update_dv1.x * (1-intersection.ti1);
                                    separateX2 = -update_dv2.x * (1-intersection.ti1);
                                }
                                else if (normal1.y != 0) {
                                    separateY1 = -update_dv1.y * (1-intersection.ti1);
                                    separateY2 = -update_dv2.y * (1-intersection.ti1);
                                }
                                if (Math.abs(separateX1) < EPSILON) separateX1 = 0;
                                if (Math.abs(separateX2) < EPSILON) separateX2 = 0;
                                if (Math.abs(separateY1) < EPSILON) separateY1 = 0;
                                if (Math.abs(separateY2) < EPSILON) separateY2 = 0;
                                var event:ECollision = {
                                    id1: id1,
                                    id2: id2,
                                    normal1: normal1,
                                    normal2: normal2,
                                    dx1: update_dv1.x,
                                    dy1: update_dv1.y,
                                    dx2: update_dv2.x,
                                    dy2: update_dv2.y,
                                    separateX1: separateX1,
                                    separateX2: separateX2,
                                    separateY1: separateY1,
                                    separateY2: separateY2,
                                    dt: dt
                                }
                                collisionEmitter.emit(event);

                            } 
                            case None: {}
                        }
                    }
                }
            }
        }

        for (id in query.result) {
            syncPrev(id, update_currentRect);
        }
    }
}