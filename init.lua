dynamic_liquid = {} -- global table to expose liquid_abm for other mods' usage

dynamic_liquid.registered_liquids = {} -- used by the flow-through node abm
dynamic_liquid.registered_liquid_neighbors = {}

-- internationalization boilerplate
local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

-- By making this giant table of all possible permutations of horizontal direction we can avoid
-- lots of redundant calculations.

local all_direction_permutations = {
	{{x=0,z=1},{x=0,z=-1},{x=1,z=0},{x=-1,z=0}},
	{{x=0,z=1},{x=0,z=-1},{x=-1,z=0},{x=1,z=0}},
	{{x=0,z=1},{x=1,z=0},{x=0,z=-1},{x=-1,z=0}},
	{{x=0,z=1},{x=1,z=0},{x=-1,z=0},{x=0,z=-1}},
	{{x=0,z=1},{x=-1,z=0},{x=0,z=-1},{x=1,z=0}},
	{{x=0,z=1},{x=-1,z=0},{x=1,z=0},{x=0,z=-1}},
	{{x=0,z=-1},{x=0,z=1},{x=-1,z=0},{x=1,z=0}},
	{{x=0,z=-1},{x=0,z=1},{x=1,z=0},{x=-1,z=0}},
	{{x=0,z=-1},{x=1,z=0},{x=-1,z=0},{x=0,z=1}},
	{{x=0,z=-1},{x=1,z=0},{x=0,z=1},{x=-1,z=0}},
	{{x=0,z=-1},{x=-1,z=0},{x=1,z=0},{x=0,z=1}},
	{{x=0,z=-1},{x=-1,z=0},{x=0,z=1},{x=1,z=0}},
	{{x=1,z=0},{x=0,z=1},{x=0,z=-1},{x=-1,z=0}},
	{{x=1,z=0},{x=0,z=1},{x=-1,z=0},{x=0,z=-1}},
	{{x=1,z=0},{x=0,z=-1},{x=0,z=1},{x=-1,z=0}},
	{{x=1,z=0},{x=0,z=-1},{x=-1,z=0},{x=0,z=1}},
	{{x=1,z=0},{x=-1,z=0},{x=0,z=1},{x=0,z=-1}},
	{{x=1,z=0},{x=-1,z=0},{x=0,z=-1},{x=0,z=1}},
	{{x=-1,z=0},{x=0,z=1},{x=1,z=0},{x=0,z=-1}},
	{{x=-1,z=0},{x=0,z=1},{x=0,z=-1},{x=1,z=0}},
	{{x=-1,z=0},{x=0,z=-1},{x=1,z=0},{x=0,z=1}},
	{{x=-1,z=0},{x=0,z=-1},{x=0,z=1},{x=1,z=0}},
	{{x=-1,z=0},{x=1,z=0},{x=0,z=-1},{x=0,z=1}},
	{{x=-1,z=0},{x=1,z=0},{x=0,z=1},{x=0,z=-1}},
}

local get_node = minetest.get_node
local set_node = minetest.set_node

-- Dynamic liquids
-----------------------------------------------------------------------------------------------------------------------

dynamic_liquid.liquid_abm = function(liquid, flowing_liquid, chance)
	minetest.register_abm({
		label = "dynamic_liquid " .. liquid,
		nodenames = {liquid},
		neighbors = {flowing_liquid},
		interval = 1,
		chance = chance or 1,
		catch_up = false,
		action = function(pos,node) -- Do everything possible to optimize this method
			local check_pos = {x=pos.x, y=pos.y-1, z=pos.z}
			local check_node = get_node(check_pos)
			local check_node_name = check_node.name
			if check_node_name == flowing_liquid or check_node_name == "air" then
				set_node(pos, check_node)
				set_node(check_pos, node)
				return
			end
			local perm = all_direction_permutations[math.random(24)]
			local dirs -- declare outside of loop so it won't keep entering/exiting scope
			for i=1,4 do
				dirs = perm[i]
				-- reuse check_pos to avoid allocating a new table
				check_pos.x = pos.x + dirs.x 
				check_pos.y = pos.y
				check_pos.z = pos.z + dirs.z
				check_node = get_node(check_pos)
				check_node_name = check_node.name
				if check_node_name == flowing_liquid or check_node_name == "air" then
					set_node(pos, check_node)
					set_node(check_pos, node)
					return
				end
			end
		end
	})	
	dynamic_liquid.registered_liquids[liquid] = flowing_liquid
	table.insert(dynamic_liquid.registered_liquid_neighbors, liquid)
end

if not minetest.get_modpath("default") then
	return
end

local water = minetest.setting_getbool("dynamic_liquid_water")
water = water or water == nil -- default true

local river_water = minetest.setting_getbool("dynamic_liquid_river_water") -- default false

local lava = minetest.setting_getbool("dynamic_liquid_lava")
lava = lava or lava == nil -- default true

local water_probability = tonumber(minetest.setting_get("dynamic_liquid_water_flow_propability"))
if water_probability == nil then
	water_probability = 1
end

local river_water_probability = tonumber(minetest.setting_get("dynamic_liquid_river_water_flow_propability"))
if river_water_probability == nil then
	river_water_probability = 1
end

local lava_probability = tonumber(minetest.setting_get("dynamic_liquid_lava_flow_propability"))
if lava_probability == nil then
	lava_probability = 5
end

local springs = minetest.setting_getbool("dynamic_liquid_springs")
springs = springs or springs == nil -- default true

if water then
	-- override water_source and water_flowing with liquid_renewable set to false
	local override_def = {liquid_renewable = false}
	minetest.override_item("default:water_source", override_def)
	minetest.override_item("default:water_flowing", override_def)
end

if lava then
	dynamic_liquid.liquid_abm("default:lava_source", "default:lava_flowing", lava_probability)
end
if water then
	dynamic_liquid.liquid_abm("default:water_source", "default:water_flowing", water_probability)
end
if river_water then	
	dynamic_liquid.liquid_abm("default:river_water_source", "default:river_water_flowing", river_water_probability)
end

-- Flow-through nodes
-----------------------------------------------------------------------------------------------------------------------

local flow_through = minetest.setting_getbool("dynamic_liquid_flow_through")
flow_through = flow_through or flow_through == nil -- default true

if flow_through then

	local flow_through_directions = {
		{{x=1,z=0},{x=0,z=1}},
		{{x=0,z=1},{x=1,z=0}},
	}
	
	minetest.register_abm({
		label = "dynamic_liquid flow-through",
		nodenames = {"group:flow_through", "group:leaves", "group:sapling", "group:grass", "group:dry_grass", "group:flora", "groups:rail", "groups:flower"},
		neighbors = dynamic_liquid.registered_liquid_neighbors,
		interval = 1,
		chance = 2, -- since liquid is teleported two nodes by this abm, halve the chance
		catch_up = false,
		action = function(pos)
			local source_pos = {x=pos.x, y=pos.y+1, z=pos.z}
			local dest_pos = {x=pos.x, y=pos.y-1, z=pos.z}
			local source_node = get_node(source_pos)
			local dest_node
			local source_flowing_node = dynamic_liquid.registered_liquids[source_node.name]
			local dest_flowing_node
			if source_flowing_node ~= nil then
				dest_node = minetest.get_node(dest_pos)
				if dest_node.name == source_flowing_node or dest_node.name == "air" then
					set_node(dest_pos, source_node)
					set_node(source_pos, dest_node)
					return
				end
			end
			
			local perm = flow_through_directions[math.random(2)]
			local dirs -- declare outside of loop so it won't keep entering/exiting scope
			for i=1,2 do
				dirs = perm[i]
				-- reuse to avoid allocating a new table
				source_pos.x = pos.x + dirs.x 
				source_pos.y = pos.y
				source_pos.z = pos.z + dirs.z
				
				dest_pos.x = pos.x - dirs.x 
				dest_pos.y = pos.y
				dest_pos.z = pos.z - dirs.z			
				
				source_node = get_node(source_pos)
				dest_node = get_node(dest_pos)
				source_flowing_node = dynamic_liquid.registered_liquids[source_node.name]
				dest_flowing_node = dynamic_liquid.registered_liquids[dest_node.name]
				
				if (source_flowing_node ~= nil and (dest_node.name == source_flowing_node or dest_node.name == "air")) or
					(dest_flowing_node ~= nil and (source_node.name == dest_flowing_node or source_node.name == "air"))
				then
					set_node(source_pos, dest_node)
					set_node(dest_pos, source_node)
					return
				end
			end		
		end,
	})

	local add_flow_through = function(node_name)
		local node_def = minetest.registered_nodes[node_name]
		local new_groups = node_def.groups
		new_groups.flow_through = 1
		minetest.override_item(node_name,{groups = new_groups})
	end

	if minetest.get_modpath("default") then
		for _, name in pairs({
			"default:apple",
			"default:papyrus",
			"default:dry_shrub",
			"default:bush_stem",
			"default:acacia_bush_stem",
			"default:sign_wall_wood",
			"default:sign_wall_steel",
			"default:ladder_wood",
			"default:ladder_steel",
			"default:fence_wood",
			"default:fence_acacia_wood",
			"default:fence_junglewood",
			"default:fence_pine_wood",
			"default:fence_aspen_wood",
		}) do
			add_flow_through(name)
		end
	end
	
	if minetest.get_modpath("xpanes") then
		add_flow_through("xpanes:bar")
		add_flow_through("xpanes:bar_flat")
	end
end


-- Springs
-----------------------------------------------------------------------------------------------------------------------

local duplicate_def = function (name)
	local old_def = minetest.registered_nodes[name]
	local new_def = {}
	for param, value in pairs(old_def) do
		new_def[param] = value
	end
	return new_def
end

-- register damp clay whether we're going to set the ABM or not, if the user disables this feature we don't want existing
-- spring clay to turn into unknown nodes.
local clay_def = duplicate_def("default:clay")
clay_def.description = S("Damp Clay")
if not springs then
	clay_def.groups.not_in_creative_inventory = 1 -- take it out of creative inventory though
end
minetest.register_node("dynamic_liquid:clay", clay_def)

local data = {}

if springs then	
	local c_clay = minetest.get_content_id("default:clay")
	local c_spring_clay = minetest.get_content_id("dynamic_liquid:clay")
	local water_level = minetest.get_mapgen_params().water_level

	-- Turn mapgen clay into spring clay
	minetest.register_on_generated(function(minp, maxp, seed)
		if minp.y >= water_level or maxp.y <= -15 then
			return
		end
		local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
		vm:get_data(data)
		
		for voxelpos, voxeldata in pairs(data) do
			if voxeldata == c_clay then
				data[voxelpos] = c_spring_clay
			end
		end
		vm:set_data(data)
		vm:write_to_map()
	end)
	
	minetest.register_abm({
		label = "dynamic_liquid damp clay spring",
		nodenames = {"dynamic_liquid:clay"},
		neighbors = {"air", "default:water_source", "default:water_flowing"},
		interval = 1,
		chance = 1,
		catch_up = false,
		action = function(pos,node)
			local check_node
			local check_node_name
			while pos.y < water_level do
				pos.y = pos.y + 1
				check_node = get_node(pos)
				check_node_name = check_node.name
				if check_node_name == "air" or check_node_name == "default:water_flowing" then
					set_node(pos, {name="default:water_source"})
				elseif check_node_name ~= "default:water_source" then
					--Something's been put on top of this clay, don't send water through it
					break
				end
			end
		end
	})
	
	-- This is a creative-mode only node that produces a modest amount of water continuously no matter where it is.
	-- Allow this one to turn into "unknown node" when this feature is disabled, since players had to explicitly place it.
	minetest.register_node("dynamic_liquid:spring", {
		description = S("Spring"),
		_doc_items_longdesc = S("A natural spring that generates an endless stream of water source blocks"),
		_doc_items_usagehelp = S("Generates one source block of water directly on top of itself once per second, provided the space is clear. If this natural spring is dug out the flow stops and it is turned into ordinary cobble."),
		drops = "default:gravel",
		tiles = {"default_cobble.png^[combine:16x80:0,-48=crack_anylength.png",
			"default_cobble.png","default_cobble.png","default_cobble.png","default_cobble.png","default_cobble.png",
			},
		is_ground_content = false,
		groups = {cracky = 3, stone = 2},
		sounds = default.node_sound_gravel_defaults(),
	})
	
	minetest.register_abm({
		label = "dynamic_liquid creative spring",
		nodenames = {"dynamic_liquid:spring"},
		neighbors = {"air", "default:water_flowing"},
		interval = 1,
		chance = 1,
		catch_up = false,
		action = function(pos,node)
			pos.y = pos.y + 1
			local check_node = get_node(pos)
			local check_node_name = check_node.name
			if check_node_name == "air" or check_node_name == "default:water_flowing" then
				set_node(pos, {name="default:water_source"})
			end
		end
	})	
end