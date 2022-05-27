package heat.aabb;

import heat.ecs.*;
import heat.core.*;

typedef ECollision = {
    final id1:heat.ecs.EntityId;
    final id2:heat.ecs.EntityId;
    final normal1:MFloatVector2;
    final normal2:MFloatVector2;
    final dx1:Float;
    final dx2:Float;
    final dy1:Float;
    final dy2:Float;
    //The amounts needed to add to id1's position to separate the two objects
    final separateX1:Float;
    final separateY1:Float;
    final separateX2:Float;
    final separateY2:Float;
    final dt:Float;
}