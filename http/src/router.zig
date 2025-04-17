//! Very much not working.

// const std = @import("std");
// const request = @import("request.zig");

// const Route = struct {
//     request.Method,
//     []const u8,
//     RouteHandler,
// };
// const RouteHandler = *const fn (*request.Request) anyerror!void;
// const PathSegments = []const []const u8;
// const Params = std.StringHashMap([]const u8);

// const RouteGroup = struct {
//     path_segment: []const u8,
//     child_routes: []const Route,
// };

// const RouterResponse = struct {
//     handler: RouteHandler,
//     params: Params,
// };

// pub fn Router(comptime routes: []const Route) type {
//     return static_route_finder(routes);
// }

// fn static_route_finder(comptime routes: []const Route) type {
//     // std.debug.print(comptime fmt: []const u8, args: anytype)

//     comptime var route_groups = [_]RouteGroup{RouteGroup{ .child_routes = &[_]Route{}, .path_segment = "" }} ** 100;
//     comptime var route_groups_index = 0;
//     comptime var leaf_routes = [_]Route{undefined} ** 100;
//     comptime var leaf_routes_index = 0;

//     inline for (routes) |route| {
//         // If the route has no path segment add it to leaf_routes instead
//         if (route.@"1".len == 0) {
//             leaf_routes[leaf_routes_index] = route;
//             leaf_routes_index += 1;

//             continue;
//         }

//         // Find the first path segment
//         comptime var segment_end_index = 0;
//         inline while (segment_end_index < route.@"1".len) : (segment_end_index += 1) {
//             switch (route.@"1"[segment_end_index]) {
//                 '/' => break,
//                 else => {},
//             }
//         }

//         const segment = route.@"1"[0..segment_end_index];

//         // Update or create a route group for this segment
//         comptime var existing_route_group_index = 0;
//         inline while (existing_route_group_index < route_groups_index) : (existing_route_group_index += 1) {
//             if (!std.mem.eql(u8, route_groups[existing_route_group_index].path_segment, segment)) continue;

//             break;
//         }

//         const rest_path = route.@"1"[(segment_end_index + 1)..];

//         if (existing_route_group_index < route_groups_index + 1) {
//             // Group already exists: just "append" the route

//             route_groups[existing_route_group_index].child_routes = route_groups[existing_route_group_index].child_routes ++ [_]Route{Route{
//                 route.@"0",
//                 rest_path,
//                 route.@"2",
//             }};
//         } else {
//             // No group found: create one

//             const new_child_route = Route{ route.@"0", rest_path, route.@"2" };
//             const new_group = RouteGroup{
//                 .path_segment = segment,
//                 .child_routes = &[_]Route{new_child_route},
//             };
//             route_groups[route_groups_index] = new_group;
//             route_groups_index += 1;
//         }
//     }

//     return struct {
//         _leaf_routes: []Route = &leaf_routes,
//         _route_groups: []RouteGroup = &route_groups,

//         pub fn find_route(this: @This(), allocator: std.mem.Allocator, method: request.Method, path_segments: PathSegments, index: usize) !?RouterResponse {
//             if (path_segments[index].len == 0) {
//                 const found_handler: ?RouteHandler = inline for (this._leaf_routes[0..leaf_routes_index]) |leaf_route| {
//                     if (leaf_route.@"0" == method) break leaf_route.@"2";
//                 } else null;

//                 if (found_handler) |h| {
//                     const params = std.StringHashMap([]const u8).init(allocator);
//                     errdefer params.deinit();

//                     return RouterResponse{ .handler = h, .params = params };
//                 }

//                 return null;
//             }

//             inline for (this._route_groups) |route_group| {
//                 if (std.mem.eql(u8, route_group.path_segment, path_segments[index])) {
//                     return static_route_finder(route_group.child_routes).find_route(allocator, method, path_segments, index + 1);
//                 }
//             }

//             return null;
//         }
//     };
// }

// fn handler(_: *request.Request) !void {}

// test "should find correct handler" {
//     const router = Router(&[_]Route{
//         Route{
//             request.Method.get, "/hello", &handler,
//         },
//     });

//     const path = "/hello";
//     const segments = try request.get_path_segments(path);
//     std.debug.print("{any}", .{segments});

//     try router.find_route(std.testing.allocator, request.Method.get, segments, 0);
// }
