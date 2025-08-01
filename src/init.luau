local Workspace = game:GetService("Workspace")

export type SurfaceType = "BottomSurface" | "TopSurface" | "LeftSurface" | "RightSurface" | "FrontSurface" | "BackSurface"

export type Shape = | "Cylinder" | "Sphere" | "Mesh"

type InternalShape = | "CornerWedge" | "Cylinder" | "Terrain" | "Sphere" | "Brick" | "Wedge"

type Identifier<T> = {
	type: T,
	__index: Identifier<T>,
}

type BaseGeometryInfo<T, I, ID = number?> = typeof(setmetatable(
	{} :: I & {
		id: ID,
	},
	{} :: Identifier<T>
))

-- not called UnitVector3 anymore because this will be changed to be vector once the type for vector is fixed
export type UnitVector = Vector3

export type Vertex<ID = nil> = BaseGeometryInfo<"Vertex", {
	position: Vector3,
}, ID>

export type Edge<ID = nil> = BaseGeometryInfo<"Edge", {
	direction: UnitVector,
	vertexMargin: number,
	edgeMargin: number,
	inferred: true?,
	length: number,
	part: BasePart,
	a: Vector3,
	b: Vector3,
}, ID>

export type Face<ID = nil> = BaseGeometryInfo<"Face", {
	direction: UnitVector,
	vertices: { Vector3 },
	surface: SurfaceType,
	normal: UnitVector,
	point: Vector3,
	part: BasePart,
}, ID>

export type GeometryResult = {
	vertices: { Vertex<number> },
	edges: { Edge<number> },
	faces: { Face<number> },
	vertexMargin: number,
	part: BasePart,
	shape: Shape,
}

local function CREATE_IDENTIFIER<T>(type: T): Identifier<T>
	local identifier = { type = type }
	identifier.__index = identifier
	return table.freeze(identifier)
end

local VERTEX_IDENTIFIER: Identifier<"Vertex"> = CREATE_IDENTIFIER("Vertex") :: any
local FACE_IDENTIFIER: Identifier<"Face"> = CREATE_IDENTIFIER("Face") :: any
local EDGE_IDENTIFIER: Identifier<"Edge"> = CREATE_IDENTIFIER("Edge") :: any

local function CREATE_VERTEX<ID>(id: ID, position: Vector3): Vertex<ID>
	return setmetatable({
		position = position,
		id = id,
	}, VERTEX_IDENTIFIER)
end

local function CREATE_FACE<ID>(
	id: ID,
	point: Vector3,
	normal: UnitVector,
	surface: SurfaceType,
	direction: UnitVector,
	vertices: { Vector3 },
	part: BasePart
): Face<ID>
	return setmetatable({
		direction = direction,
		vertices = vertices,
		surface = surface,
		normal = normal,
		point = point,
		part = part,
		id = id,
	}, FACE_IDENTIFIER)
end

local function CREATE_EDGE<ID>(
	id: ID,
	a: Vector3,
	b: Vector3,
	vertexMargin: number,
	edgeMargin: number,
	part: BasePart
): Edge<ID>
	return setmetatable({
		vertexMargin = vertexMargin,
		-- temp any casts because vector type broken :(
		direction = vector.normalize(b - a) :: any,
		length = vector.magnitude(b - a) :: any,
		edgeMargin = edgeMargin,
		part = part,
		id = id,
		a = a,
		b = b,
	}, EDGE_IDENTIFIER) :: any -- new solver throwing a fit
end

local Geometry = {}

do -- getGeometry
	local CURRENT_VERTEX_MARGIN: number
	local CURRENT_PART: BasePart
	local CURRENT_ID = 0

	local function getShape(part: BasePart): InternalShape
		if part:IsA("WedgePart") then
			return "Wedge"
		elseif part:IsA("CornerWedgePart") then
			return "CornerWedge"
		elseif part:IsA("Terrain") then
			return "Terrain"
		elseif part:IsA("UnionOperation") then
			return "Brick"
		elseif part:IsA("MeshPart") then
			return "Brick"
		elseif part:IsA("Part") then
			-- BasePart
			if part.Shape == Enum.PartType.Ball then
				return "Sphere"
			elseif part.Shape == Enum.PartType.Cylinder then
				return "Cylinder"
			elseif part.Shape == Enum.PartType.Block then
				return "Brick"
			elseif part.Shape == Enum.PartType.CornerWedge then
				return "CornerWedge"
			elseif part.Shape == Enum.PartType.Wedge then
				return "Wedge"
			else
				error("Unreachable")
			end
		else
			return "Brick"
		end
	end

	local function createVertex(position: Vector3): Vertex<number>
		CURRENT_ID += 1
		return CREATE_VERTEX(CURRENT_ID, position)
	end

	local function createFace(
		point: Vector3,
		normal: UnitVector,
		surface: SurfaceType,
		direction: UnitVector,
		vertices: { Vector3 }
	): Face<number>
		CURRENT_ID += 1
		return CREATE_FACE(CURRENT_ID, point, normal, surface, direction, vertices, CURRENT_PART)
	end

	local function createEdge(a: Vector3, b: Vector3, edgeMargin: number): Edge<number>
		CURRENT_ID += 1
		return CREATE_EDGE(CURRENT_ID, a, b, CURRENT_VERTEX_MARGIN, edgeMargin, CURRENT_PART)
	end

	function Geometry.getGeometry(part: BasePart, hit: Vector3, assumedCFrame: CFrame?): GeometryResult
		CURRENT_PART = part
		CURRENT_ID = 0

		local cf = assumedCFrame or part.CFrame
		local pos = cf.Position

		local halvedPartSize = part.Size / 2
		local sx = halvedPartSize.x
		local sy = halvedPartSize.y
		local sz = halvedPartSize.z

		local xvec = cf.RightVector
		local yvec = cf.UpVector
		local zvec = -cf.LookVector

		local verts, edges, faces
		local shape = getShape(part)

		--[[
		local scale = vector.one
		sx = sx * scale.x
		sy = sy * scale.y
		sz = sz * scale.z
		]]

		CURRENT_VERTEX_MARGIN = math.min(sx, sy, sz) * 2

		if shape == "Brick" or shape == "Sphere" or shape == "Cylinder" then
			-- 8 vertices
			-- theres a ton parens so luau does math optimizations
			-- top 4
			local vert1 = (((pos + xvec) * sx) + yvec * sy) + zvec * sz
			local vert2 = (((pos + xvec) * sx) + yvec * sy) - zvec * sz
			local vert3 = (((pos - xvec) * sx) + yvec * sy) + zvec * sz
			local vert4 = (((pos - xvec) * sx) + yvec * sy) - zvec * sz
			-- bottom 4
			local vert5 = (((pos + xvec) * sx) - yvec * sy) + zvec * sz
			local vert6 = (((pos + xvec) * sx) - yvec * sy) - zvec * sz
			local vert7 = (((pos - xvec) * sx) - yvec * sy) + zvec * sz
			local vert8 = (((pos - xvec) * sx) - yvec * sy) - zvec * sz

			--6 faces
			faces = {
				createFace(vert1, xvec, "RightSurface", zvec, { vert5, vert6, vert2, vert1 }), -- right
				createFace(vert3, -xvec, "LeftSurface", zvec, { vert3, vert4, vert8, vert7 }), -- left
				createFace(vert1, yvec, "TopSurface", xvec, { vert1, vert2, vert4, vert3 }), -- top
				createFace(vert5, -yvec, "BottomSurface", xvec, { vert7, vert8, vert6, vert5 }), -- bottom
				createFace(vert1, zvec, "BackSurface", xvec, { vert1, vert3, vert7, vert5 }), -- back
				createFace(vert2, -zvec, "FrontSurface", xvec, { vert6, vert8, vert4, vert2 }), -- front
			}

			local min_sy_sz = math.min((2 * sy), (2 * sz))
			local min_sx_sy = math.min(2 * sx, (2 * sy))
			local min_sx_sz = math.min((2 * sx), (2 * sz))

			--12 edges
			edges = {
				-- top 4
				createEdge(vert1, vert2, min_sx_sy),
				createEdge(vert3, vert4, min_sx_sy),
				createEdge(vert1, vert3, min_sy_sz),
				createEdge(vert2, vert4, min_sy_sz),
				-- bottom 4
				createEdge(vert5, vert6, min_sx_sy),
				createEdge(vert7, vert8, min_sx_sy),
				createEdge(vert5, vert7, min_sy_sz),
				createEdge(vert6, vert8, min_sy_sz),
				-- verticals
				createEdge(vert1, vert5, min_sx_sz),
				createEdge(vert2, vert6, min_sx_sz),
				createEdge(vert3, vert7, min_sx_sz),
				createEdge(vert4, vert8, min_sx_sz),
			}

			-- making the verts table
			verts = { vert1, vert2, vert3, vert4, vert5, vert6, vert7, vert8 }
		elseif shape == "Sphere" or shape == "Cylinder" then
			local norm = vector.normalize(hit - pos)
			local norm2 = vector.normalize(vector.cross(norm, vector.create(0, 1, 0)))
			local absNorm = vector.abs(norm)

			-- stylua: ignore
			local surfaceName = if absNorm.x > absNorm.y and absNorm.x > absNorm.z then
					(if norm.x > 0 then "RightSurface" else "LeftSurface")
				elseif absNorm.y > absNorm.z then
					(if norm.y > 0 then "TopSurface" else "BottomSurface")
				else
					(if norm.z > 0 then "BackSurface" else "FrontSurface")

			faces = { createFace(hit, norm, surfaceName, norm2, {}) }
			-- edge can be selected as the normal of the face if the user needs it
			edges = {}
			-- Just have one face and vertex, at the hit pos
			verts = { createVertex(hit) }
		elseif shape == "CornerWedge" then
			local slantVec1 = vector.normalize(zvec * sy + yvec * sz)
			local slantVec2 = vector.normalize(-xvec * sy + yvec * sx)

			-- top 1
			local vert1 = (pos + xvec * sx) + yvec * sy - zvec * sz
			-- bottom 4
			local vert2 = ((pos + xvec * sx) - yvec) * sy + zvec * sz
			local vert3 = ((pos + xvec * sx) - yvec) * sy - zvec * sz
			local vert4 = ((pos - xvec * sx) - yvec) * sy + zvec * sz
			local vert5 = ((pos - xvec * sx) - yvec) * sy - zvec * sz

			-- 5 faces
			faces = {
				-- bottom
				createFace(vert2, -yvec, "BottomSurface", xvec, { vert2, vert3, vert5, vert4 }),
				-- sides
				createFace(vert1, xvec, "RightSurface", -yvec, { vert1, vert3, vert2 }),
				createFace(vert1, -zvec, "FrontSurface", -yvec, { vert1, vert3, vert5 }),
				-- tops
				createFace(vert1, slantVec1, "BackSurface", xvec, { vert1, vert2, vert4 }),
				createFace(vert1, slantVec2, "LeftSurface", zvec, { vert1, vert5, vert4 }),
			}

			-- 8 edges
			edges = {
				-- bottom 4
				createEdge(vert2, vert3, 0),
				createEdge(vert3, vert5, 0),
				createEdge(vert5, vert4, 0),
				createEdge(vert4, vert2, 0),
				-- vertical
				createEdge(vert1, vert3, 0),
				-- side diagonals
				createEdge(vert1, vert2, 0),
				createEdge(vert1, vert5, 0),
				-- middle diagonal
				createEdge(vert1, vert4, 0),
			}

			verts = {
				createVertex(vert1),
				createVertex(vert2),
				createVertex(vert3),
				createVertex(vert4),
				createVertex(vert5),
			}
		elseif shape == "Wedge" then
			local slantVec = vector.normalize(-zvec * sy + yvec * sz)

			-- 6 vertices
			-- top 2
			local vert1 = ((pos + xvec) * sx) + yvec * sy + zvec * sz
			local vert2 = ((pos - xvec) * sx) + yvec * sy + zvec * sz
			-- bottom 4
			local vert3 = (((pos + xvec) * sx) - yvec * sy) + zvec * sz
			local vert4 = (((pos + xvec) * sx) - yvec * sy) - zvec * sz
			local vert5 = (((pos - xvec) * sx) - yvec * sy) + zvec * sz
			local vert6 = (((pos - xvec) * sx) - yvec * sy) - zvec * sz

			--5 faces
			faces = {
				-- right
				createFace(vert1, xvec, "RightSurface", zvec, { vert4, vert1, vert3 }),
				-- left
				createFace(vert2, -xvec, "LeftSurface", zvec, { vert2, vert6, vert5 }),
				-- bottom
				createFace(vert3, -yvec, "BottomSurface", xvec, { vert5, vert6, vert4, vert3 }),
				-- back
				createFace(vert1, zvec, "BackSurface", xvec, { vert1, vert2, vert5, vert3 }),
				-- slanted
				createFace(
					vert2,
					slantVec,
					"FrontSurface",
					vector.cross(slantVec, xvec),
					{ vert2, vert1, vert4, vert6 }
				),
			}

			-- 9 edges
			local min_sx_sy = math.min((2 * sx), (2 * sy))
			local min_sy_sz = math.min((2 * sy), (2 * sz))
			local min_sx_sz = math.min((2 * sx), (2 * sz))

			edges = {
				-- top 1
				createEdge(vert1, vert2, min_sy_sz),
				-- slanted 2
				createEdge(vert1, vert4, min_sy_sz),
				createEdge(vert2, vert6, min_sy_sz),
				-- bottom 4
				createEdge(vert3, vert4, min_sx_sy),
				createEdge(vert5, vert6, min_sx_sy),
				createEdge(vert3, vert5, min_sy_sz),
				createEdge(vert4, vert6, min_sy_sz),
				-- vertical 2
				createEdge(vert1, vert3, min_sx_sz),
				createEdge(vert2, vert5, min_sx_sz),
			}

			verts = {
				createVertex(vert1),
				createVertex(vert2),
				createVertex(vert3),
				createVertex(vert4),
				createVertex(vert5),
				createVertex(vert6),
			}
		elseif shape == "Terrain" then
			error("Called GetGeometry on Terrain")
		else
			error("Bad shape: " .. shape)
		end

		return {
			shape = if shape == "Sphere" or shape == "Cylinder" then shape else "Mesh",
			vertexMargin = CURRENT_VERTEX_MARGIN,
			vertices = verts,
			edges = edges,
			faces = faces,
			part = part,
		}
	end
end

-- Get any perpendicular vector
local function perpendicularVector(v: Vector3): UnitVector
	local differentVec = if math.abs(vector.dot(v, vector.create(1, 0, 0))) > 0.7
		then vector.create(0, 1, 0)
		else vector.create(1, 0, 0)

	return vector.normalize(vector.cross(differentVec, v))
end

local function findNearestInterestingPoint(
	mainBasis: CFrame,
	part: BasePart,
	worldRoot: WorldRoot
): (Vector3?, UnitVector?)
	local main_basis_y_vector = mainBasis.YVector
	local OFF_SURFACE = 1.0
	local DOWN_VECTOR = -main_basis_y_vector * (vector.magnitude(part.Size) + OFF_SURFACE)

	--[[
		Explore outwards in a cross pattern, doubling the distance every time
		      ^ +zBasis
		      |
		  <---O---> +xBasis
		      |
		      V
	]]

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }
	local distanceStep = 0.01

	for i = 1, 12 do
		for dx = -1, 1, 2 do
			for dz = -1, 1, 2 do
				local localPosition = vector.create(dx * distanceStep, OFF_SURFACE, dz * distanceStep)
				local castFrom = mainBasis:PointToWorldSpace(localPosition)
				local hit = worldRoot:Raycast(castFrom, DOWN_VECTOR, params)

				if hit then
					if math.abs(hit.Distance - OFF_SURFACE) > 0.001 then
						return hit.Position, hit.Normal
					end
				else
					-- We missed the mesh, move down a bit, and then cast back towards the
					-- origin to find the edge / backface we missed
					castFrom -= main_basis_y_vector * (OFF_SURFACE + 0.1)
					local backToOrigin = (mainBasis.Position - castFrom)
					local sideHit = worldRoot:Raycast(castFrom, backToOrigin, params)

					if sideHit then
						return sideHit.Position, sideHit.Normal
					else
						-- The side hit should always hit, because it should at least intersect
						-- with the plane we initially started on.
						error("Unreachable")
					end
				end
			end
		end
		distanceStep *= 2
	end
	-- Should always eventually end up missing
	error("Unreachable")
end

local function intersectPlanePlane(p1: Vector3, n1: Vector3, p2: Vector3, n2: Vector3): (Vector3, Vector3)
	local dir = vector.normalize(vector.cross(n1, n2))
	local a1 = vector.normalize(vector.cross(n1, dir))
	local a2 = vector.normalize(vector.cross(n2, dir))

	-- p1 + a1 * i = p2 + a2 * j
	-- (p1 - p2) = a1 * i + a2 * j
	-- ((p1 - p2) . a1) = i + (a1 . a2) * j
	-- ((p1 - p2) . a2) = (a1 . a2) * i + j
	--
	-- ((p1 - p2) . a1) - (a1 . a2) * j = i
	local a1a2 = vector.dot(a1, a2)
	local delta = p1 - p2
	local j = (vector.dot(delta, a2) - a1a2 * vector.dot(delta, a1)) / (1 - a1a2 * a1a2)
	local origin = p2 + a2 * j
	return origin, dir
end

-- Insersect Ray(a + t*b) with plane (origin: o, normal: n), return t of the interesection
local function intersectRayPlane(a: Vector3, b: Vector3, o: Vector3, n: Vector3): number
	return vector.dot((o - a), n) / vector.dot(b, n)
end

-- Intersect Ray(a + t*b) with plane (origin: o, normal :n), and return the intersection as Vector3
local function intersectRayPlanePoint(a: Vector3, b: Vector3, o: Vector3, n: Vector3): Vector3
	local t = intersectRayPlane(a, b, o, n)
	return a + t * b
end

local function exploreEdge(
	part: BasePart,
	origin: Vector3,
	dir: Vector3,
	normal: Vector3,
	normal2: Vector3,
	worldRoot: WorldRoot
): Edge?
	local PART_SIZE = part.Size
	local MAX_LENGTH = vector.magnitude(PART_SIZE)
	local HOVER_POINT_1 = origin + normal * 0.01 - normal2 * 0.01
	local HOVER_POINT_2 = origin + normal2 * 0.01 - normal * 0.01
	local SINK_POINT = origin - normal * 0.01 - normal2 * 0.01

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }

	local span = dir * MAX_LENGTH

	-- Find a positive clip plane for edge (origin, dir)
	local positiveHit = worldRoot:Raycast(HOVER_POINT_1, span, params)
	if not positiveHit then
		positiveHit = worldRoot:Raycast(HOVER_POINT_2, span, params)
	end
	if not positiveHit then
		positiveHit = worldRoot:Raycast(SINK_POINT + span, -span, params)
	end
	if not positiveHit then
		return nil
	end

	-- Find a negative clip plane for edge (origin, dir)
	local negativeHit = worldRoot:Raycast(HOVER_POINT_1, -span, params)
	if not negativeHit then
		negativeHit = worldRoot:Raycast(HOVER_POINT_2, -span, params)
	end
	if not negativeHit then
		negativeHit = worldRoot:Raycast(SINK_POINT - span, span, params)
	end
	if not negativeHit then
		return nil
	end

	-- Clip (origin, dir) by planes
	local positivePoint = intersectRayPlanePoint(origin, dir, positiveHit.Position, positiveHit.Normal)
	local negativePoint = intersectRayPlanePoint(origin, dir, negativeHit.Position, negativeHit.Normal)

	-- Figure out the vertex margin
	local testPart = part:Clone()
	testPart.Material = Enum.Material.Plastic
	testPart.CustomPhysicalProperties = nil
	local referencePart = Instance.new("Part")
	referencePart.Size = PART_SIZE
	referencePart.CustomPhysicalProperties = nil
	local massFraction = testPart:GetMass() / referencePart:GetMass()

	local edge = CREATE_EDGE(
		nil,
		positivePoint,
		negativePoint,
		math.min(PART_SIZE.X, PART_SIZE.Y, PART_SIZE.Z) * massFraction * massFraction,
		0.5,
		part
	)
	edge.inferred = true

	return edge
end

function Geometry.blackboxFindClosestMeshEdge(hit: RaycastResult, viewDirection: Vector3, worldRoot: WorldRoot?): Edge?
	worldRoot = worldRoot or Workspace
	local part = hit.Instance :: BasePart

	-- We have a current plane defined by p,n
	local p = hit.Position
	local n = hit.Normal

	-- Basis within which we're about to do stuff
	local mainBasis = CFrame.fromMatrix(p, perpendicularVector(n), n)
	local xBasis = mainBasis.XVector
	local zBasis = mainBasis.ZVector

	-- We want to explore outwards over this plane until we find where it ends
	-- (that is, where parallel raycasts diverge from the plane)
	local p2, n2 = findNearestInterestingPoint(mainBasis, part, worldRoot)

	-- Find the axis which goes through both (p, n) and (p2, n2)
	local origin, dir = intersectPlanePlane(p, n, p2, n2)

	-- (origin, dir) is now a ray along the edge of interest. From here we have
	-- to figure out how LONG the edge is along that ray. We know that origin is
	-- ONE of the points on the ray, so we can raycast out from there.
	return exploreEdge(part, origin, dir, n, n2, worldRoot)
end

return table.freeze(Geometry)
