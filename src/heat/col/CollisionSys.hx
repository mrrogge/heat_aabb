package heat.col;

import heat.ecs.*;
import core.*;

using tink.core.Option.OptionTools;

private class Cell {
    public var row(default, null):Int;
    public var col(default, null):Int;
    public var size(default, null):Int;
    public var ids(default, null) = new Map<EntityId, Bool>();
    public var rect:core.Rect;

    public function new(row=0, col=0, size=64) {
        this.row = row;
        this.col = col;
        this.size = size;
        this.rect = new core.Rect(col*size, row*size, size, size);
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
    public static inline final EPSILON = 1e-7;

    public var collisionSignal(default, null):heat.event.ISignal<ECollision>;

    //emitters for the protected signals
    var collisionSignalEmitter = new heat.event.SignalEmitter<ECollision>();

    var query = new heat.ecs.ComQuery();

    var collidables:heat.ecs.ComMap<Collidable>;
    var posComs:heat.ecs.ComMap<h2d.Object>;

    var cellSize:Int;
    var cells = new Map<Int, Map<Int, Cell>>();

    var prevRects = new Map<EntityId, MutRect>();
    var currentRects = new Map<EntityId, MutRect>();
    var idCellsMap = new Map<EntityId, Array<Cell>>();
    var containingRect = new core.MutRect();
    var checkedIds = new Map<EntityId, Bool>();
    var cellsArray = new Array<Cell>();

    public function new(collidables:heat.ecs.ComMap<Collidable>, 
    posComs:heat.ecs.ComMap<h2d.Object>, cellSize=64) 
    {
        this.collidables = collidables;
        this.posComs = posComs;
        this.cellSize = cellSize;
        query.with(collidables).with(posComs);
        collisionSignal = collisionSignalEmitter.signal;
    }

    public dynamic function filter(id1:EntityId, id2:EntityId):Bool {
        return true;
    }

    /**
        Returns an absolute Rect based on the collidable and position components, where the rect's x and y are aligned with the top-left corner.
    **/
    function getAbsRectFromComs(collidable:Collidable, pos:h2d.Object, ?dest:MutRect):MutRect {
        if (dest == null) dest = new MutRect();
        dest.init(pos.x-collidable.rect.x, pos.y-collidable.rect.y,
            collidable.rect.w, collidable.rect.h);
        return dest;
    }

    /**
        Returns the minimum area Rect containing r1 and r2.
    **/
    function getContainingRect(r1:MutRect, r2:MutRect, ?dest:MutRect):MutRect {
        if (dest == null) dest = new MutRect();
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
    **/
    function pointToCell(x:Float, y:Float):Cell {
        return getCell(Math.floor(x/cellSize), Math.floor(y/cellSize));
    }


    /**
        Finds all cells overlapping rect and returns them in an array.
    **/
    function getCellsInRect(rect:MutRect, ?dest:Array<Cell>):Array<Cell> {
        if (dest == null) dest = new Array<Cell>();
        else {
            for (i in 0...dest.length) dest.pop();
        }
        var topLeftCell = pointToCell(rect.x, rect.y);
        var bottomRightCell = pointToCell(rect.x+rect.w, rect.y+rect.h);
        dest.push(topLeftCell);
        if (topLeftCell != bottomRightCell) {
            dest.push(bottomRightCell);
            for (row in topLeftCell.row...bottomRightCell.row+1) {
                for (col in topLeftCell.col...bottomRightCell.col+1) {
                    if (row == topLeftCell.row && col == topLeftCell.col) continue;
                    if (row == bottomRightCell.row && col == bottomRightCell.col) continue;
                    dest.push(getCell(row, col));
                }
            }
        }
        return dest;
    }

    function rotateRect180AroundOrigin(rect:MutRect, ?dest:MutRect):MutRect {
        if (dest == null) dest = new MutRect();
        dest.init(-(rect.x + rect.w), -(rect.y + rect.h), rect.w, rect.h);
        return dest;
    }

    function sumRects(r1:MutRect, r2:MutRect, ?dest:MutRect):MutRect {
        if (dest == null) dest = new MutRect();
        dest.init(r1.x+r2.x, r1.y+r2.y, r1.w+r2.w, r1.h+r2.h);
        return dest;
    }

    function diffRects(r1:MutRect, r2:MutRect, ?dest:MutRect):MutRect {
        if (dest == null) dest = new MutRect();
        dest.init(r2.x - r1.x - r1.w, r2.y - r1.y - r1.h, r1.w+r2.w, r1.h+r2.h);
        return dest;
    }

    function getRectLineIntersection(rect:MutRect, line:Line, ti1=0., ti2=1.)
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

    function updateRectsAfterCollision(event:ECollision) {
        var collidable1 = collidables[event.id1];
        if (collidable1 == null) return;
        var pos1 = posComs[event.id1];
        if (pos1 == null) return;
        var collidable2 = collidables[event.id2];
        if (collidable2 == null) return;
        var pos2 = posComs[event.id2];
        if (pos2 == null) return;

        var newRect = getAbsRectFromComs(collidable1, pos1);
        if (!currentRects.exists(event.id1)) {
            currentRects[event.id1] = new MutRect(); 
        }
        if(!Rect.s_isAlike(newRect, currentRects[event.id1])) {
            //id1 has changed due to a collision response
            getContainingRect(prevRects[event.id1], currentRects[event.id1],
                containingRect);
            getCellsInRect(containingRect, cellsArray);
            for (cell in cellsArray) {
                cell.ids.remove(event.id1);
            }
            currentRects[event.id1].applyFrom(newRect);
            getContainingRect(prevRects[event.id1], currentRects[event.id1],
                containingRect);
            getCellsInRect(containingRect, cellsArray);
            for (cell in cellsArray) {
                cell.ids[event.id1] = true;
            }
        }
        getAbsRectFromComs(collidable2, pos2, newRect);
        if (!currentRects.exists(event.id2)) {
            currentRects[event.id2] = new MutRect(); 
        }
        if(!Rect.s_isAlike(newRect, currentRects[event.id2])) {
            //id2 has changed due to a collision response
            getContainingRect(prevRects[event.id2], currentRects[event.id2],
                containingRect);
            getCellsInRect(containingRect, cellsArray);
            for (cell in cellsArray) {
                cell.ids.remove(event.id2);
            }
            currentRects[event.id2].applyFrom(newRect);
            getContainingRect(prevRects[event.id2], currentRects[event.id2],
                containingRect);
            getCellsInRect(containingRect, cellsArray);
            for (cell in cellsArray) {
                cell.ids[event.id2] = true;
            }
        }
    }

    public function getNearestCorner(rect:MutRect, x:Float, y:Float, ?dest:Point):Point {
        if (dest == null) dest = new Point();
        dest.x = Math.abs(rect.x - x) < Math.abs(rect.x + rect.w - x) ? rect.x : rect.x + rect.w;
        dest.y = Math.abs(rect.y - y) < Math.abs(rect.y + rect.h - y) ? rect.y : rect.y + rect.h;
        return dest;
    }

    public function update(dt:Float) {
        query.run();
        for (id in query.result) {
            var collidable = collidables[id];
            var pos = posComs[id];
            if (prevRects.exists(id) && currentRects.exists(id)) {
                //remove id from previous cells
                getContainingRect(prevRects[id], currentRects[id],
                    containingRect);
                getCellsInRect(containingRect, cellsArray);
                for (cell in cellsArray) {
                    cell.ids.remove(id);
                }
                prevRects[id].applyFrom(currentRects[id]);
                getAbsRectFromComs(collidable, pos, currentRects[id]);
                getContainingRect(prevRects[id], currentRects[id],
                    containingRect);
            }
            else {
                if (!prevRects.exists(id)) prevRects[id] = new MutRect();
                if (!currentRects.exists(id)) currentRects[id] = new MutRect();
                getAbsRectFromComs(collidable, pos, currentRects[id]);
                prevRects[id].applyFrom(currentRects[id]);
                containingRect.applyFrom(currentRects[id]);
            }
            if (Math.abs(prevRects[id].w-currentRects[id].w) > EPSILON
            || Math.abs(prevRects[id].h-currentRects[id].h) > EPSILON) 
            {
                //collider has changed this frame. Instead of trying to figure out collisions while gradually resizing (which would likely require some complex integration), we will just act as the though the size changed immediately before the move, i.e. previous size is still equal to current size.
                //NOTE: technically there's still an issue here since the previous origin point might be something other than the top-left corner, but because we aren't storing that info we don't know what it is, so we're just keeping it simple and resizing based on the top-left corner position. We would need to store more info from the previous frame in order to fix this, but it's not really that important right now.
                prevRects[id].w = currentRects[id].w;
                prevRects[id].h = currentRects[id].h;
            }
            getCellsInRect(containingRect, cellsArray);
            for (cell in cellsArray) {
                cell.ids[id] = true;
            }
        }
        checkedIds.clear();
        var rect1 = new MutRect();
        var rect2 = new MutRect();
        for (id1 in query.result) {
            checkedIds[id1] = true;
            var collidable1 = collidables[id1];
            if (collidable1 == null) continue;
            var pos1 = posComs[id1];
            if (pos1 == null) continue;
            getContainingRect(prevRects[id1], currentRects[id1], containingRect);
            getCellsInRect(containingRect, cellsArray);
            for (cell in cellsArray) {
                for (id2 => val in cell.ids) {
                    if (id1 == id2) continue;
                    var id2HasAllComs = true;
                    var collidable2 = collidables[id2];
                    if (collidable2 == null) id2HasAllComs = false;
                    var pos2 = posComs[id2];
                    if (pos2 == null) id2HasAllComs = false;
                    if (!id2HasAllComs) {
                        cell.ids.remove(id2);
                        prevRects.remove(id2);
                        currentRects.remove(id2);
                        continue;
                    }
                    if (checkedIds[id2]) continue;
                    if (!filter(id1, id2)) continue;
                    var dv1 = new Point(currentRects[id1].x - prevRects[id1].x,
                        currentRects[id1].y - prevRects[id1].y);
                    var dv2 = new Point(currentRects[id2].x - prevRects[id2].x,
                        currentRects[id2].y - prevRects[id2].y);
                    var dv = new Point(dv1.x-dv2.x, dv1.y-dv2.y);
                    var line = new Line(0, 0, dv.x, dv.y);
                    var rectDiff = diffRects(prevRects[id1], prevRects[id2]);
                    if (rectDiff.containsPoint(0, 0)) {
                        //was already overlapping
                        var nearestCornerToOrigin = getNearestCorner(rectDiff, 0, 0);
                        var intersectionWidth = Math.min(collidable1.rect.w, 
                            Math.abs(nearestCornerToOrigin.x));
                        var intersectionHeight = Math.min(collidable1.rect.h,
                            Math.abs(nearestCornerToOrigin.y));
                        if (dv.x == 0 && dv.y == 0) {
                            //not moving relative to each other. Separate by finding the shortest displacement vector
                            var n1 = new heat.vector.FloatVector2();
                            var n2 = new heat.vector.FloatVector2();
                            var separateX1 = -dv1.x;
                            var separateY1 = -dv1.y;
                            var separateX2 = -dv2.x;
                            var separateY2 = -dv2.y;
                            if (Math.abs(nearestCornerToOrigin.x) < Math.abs(nearestCornerToOrigin.y)) {
                                n1.x = nearestCornerToOrigin.x/Math.abs(nearestCornerToOrigin.x);
                                n1.y = 0;
                                n2.x = -n1.x;
                                n2.y = 0;
                                separateX1 += nearestCornerToOrigin.x;
                                separateX2 -= nearestCornerToOrigin.x;
                            }
                            else {
                                n1.x = 0;
                                n1.y = nearestCornerToOrigin.y/Math.abs(nearestCornerToOrigin.y);
                                n2.x = 0;
                                n2.y = -n1.y;
                                separateY1 += nearestCornerToOrigin.y;
                                separateY2 -= nearestCornerToOrigin.y; 
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
                                dx1: dv1.x,
                                dy1: dv1.y,
                                dx2: dv2.x,
                                dy2: dv2.y,
                                separateX1: separateX1,
                                separateY1: separateY1,
                                separateX2: separateX2,
                                separateY2: separateY2 
                            };
                            collisionSignalEmitter.emit(event);
                            updateRectsAfterCollision(event);
                        }
                        else {
                            //moving relative to each other. Separate along dv line, away from each other.
                            var intersection = getRectLineIntersection(rectDiff, line, Math.NEGATIVE_INFINITY, 1);
                            switch intersection {
                                case Some(intersection): {
                                    final ti1 = intersection.ti1;
                                    final ti2 = intersection.ti2;
                                    if (ti1 < 1 
                                    && (0 < ti1 + EPSILON || (ti1 == 0 && ti2 > 0)))
                                    {
                                        var normal1 = new heat.vector.FloatVector2();
                                        normal1.x = intersection.nx1;
                                        normal1.y = intersection.ny1;
                                        var normal2 = new heat.vector.FloatVector2();
                                        normal2.x = -normal1.x;
                                        normal2.y = -normal1.y;
                                        var separateX1 = 0.;
                                        var separateX2 = 0.;
                                        var separateY1 = 0.;
                                        var separateY2 = 0.;
                                        if ((dv1.x > 0 && normal1.x < 0) 
                                        || (dv1.x < 0 && normal1.x > 0)) 
                                        {
                                            separateX1 = -dv1.x + line.x2 * intersection.ti1;
                                        }
                                        if ((dv2.x > 0 && normal2.x < 0) 
                                        || (dv2.x < 0 && normal2.x > 0)) 
                                        {
                                            separateX2 = -dv2.x - line.x2 * intersection.ti1;
                                        }
                                        if ((dv1.y > 0 && normal1.y < 0) 
                                        || (dv1.y < 0 && normal1.y > 0)) 
                                        {
                                            separateY1 = -dv1.y + line.y2 * intersection.ti1;
                                        }
                                        if ((dv2.y > 0 && normal2.y < 0) 
                                        || (dv2.y < 0 && normal2.y > 0)) 
                                        {
                                            separateY2 = -dv2.y - line.y2 * intersection.ti1;
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
                                            dx1: dv1.x,
                                            dy1: dv1.y,
                                            dx2: dv2.x,
                                            dy2: dv2.y,
                                            separateX1: separateX1,
                                            separateX2: separateX2,
                                            separateY1: separateY1,
                                            separateY2: separateY2
                                        }
                                        collisionSignalEmitter.emit(event);
                                        updateRectsAfterCollision(event);
                                    }
                                }
                                case None: {}
                            }
                        }
                    }
                    else {  
                        //was not overlapping, tunneled into each other.  
                        var intersection = getRectLineIntersection(rectDiff, line,
                            Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY);
                        switch intersection {
                            case Some(intersection): {
                                final ti1 = intersection.ti1;
                                final ti2 = intersection.ti2;
                                if (ti1 < 1 
                                && (0 < ti1 + EPSILON || (ti1 == 0 && ti2 > 0)))
                                {
                                    var normal1 = new heat.vector.FloatVector2();
                                    normal1.x = intersection.nx1;
                                    normal1.y = intersection.ny1;
                                    var normal2 = new heat.vector.FloatVector2();
                                    normal2.x = -normal1.x;
                                    normal2.y = -normal1.y;
                                    var separateX1 = 0.;
                                    var separateX2 = 0.;
                                    var separateY1 = 0.;
                                    var separateY2 = 0.;
                                    if ((dv1.x > 0 && normal1.x < 0) 
                                    || (dv1.x < 0 && normal1.x > 0)) 
                                    {
                                        separateX1 = -dv1.x + line.x2 * intersection.ti1;
                                    }
                                    if ((dv2.x > 0 && normal2.x < 0) 
                                    || (dv2.x < 0 && normal2.x > 0)) 
                                    {
                                        separateX2 = -dv2.x - line.x2 * intersection.ti1;
                                    }
                                    if ((dv1.y > 0 && normal1.y < 0) 
                                    || (dv1.y < 0 && normal1.y > 0)) 
                                    {
                                        separateY1 = -dv1.y + line.y2 * intersection.ti1;
                                    }
                                    if ((dv2.y > 0 && normal2.y < 0) 
                                    || (dv2.y < 0 && normal2.y > 0)) 
                                    {
                                        separateY2 = -dv2.y - line.y2 * intersection.ti1;
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
                                        dx1: dv1.x,
                                        dy1: dv1.y,
                                        dx2: dv2.x,
                                        dy2: dv2.y,
                                        separateX1: separateX1,
                                        separateX2: separateX2,
                                        separateY1: separateY1,
                                        separateY2: separateY2
                                    }
                                    collisionSignalEmitter.emit(event);
                                    updateRectsAfterCollision(event);
                                }
                            } 
                            case None: {}
                        }
                    }
                }
            }
        }
    }
}