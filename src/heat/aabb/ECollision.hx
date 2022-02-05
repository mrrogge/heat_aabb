package heat.col;

import heat.ecs.*;
import heat.vector.*;

typedef ECollision = {
    final id1:heat.ecs.EntityId;
    final id2:heat.ecs.EntityId;
    final normal1:MVector2<Float>;
    final normal2:MVector2<Float>;
    final dx1:Float;
    final dx2:Float;
    final dy1:Float;
    final dy2:Float;
    //The amounts needed to add to id1's position to separate the two objects
    final separateX1:Float;
    final separateY1:Float;
    final separateX2:Float;
    final separateY2:Float;
}