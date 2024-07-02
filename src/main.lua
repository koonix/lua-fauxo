local M = {}
local pl = require("pl.import_into")()

-----
-----

-- an implementation of a base class
M.class = {}

-- create a new immutable copy of the class
function M.class:newclass(overrides)
	local proxy = {}
	setmetatable(proxy, {
		__index = M.morph(self, overrides),
		__newindex = function()
			error("attempt to mutate a class")
		end,
	})
	return proxy
end

-- create a new object
function M.class:new(overrides)
	return M.morph(self, overrides)
end

-- morph the given subtable of the object with the given 'overrides' table
function M.class:morph(key, overrides)
	return self:new({ [key] = M.morph(self[key], overrides) })
end

-- append the given items to the specified list-like subtable
function M.class:append(key, items)
	self = self:new()
	for _, v in ipairs(items) do
		table.insert(self[key], v)
	end
	return self
end

-- prepend the given items to the specified list-like subtable
function M.class:prepend(key, items)
	self = self:new()
	for i = #items, 1, -1 do
		table.insert(self[key], 1, items[i])
	end
	return self
end

-----
-----

-- the cache class allows storing key-value pairs,
-- where the key can be a table whose significance is it's contents.
M.cache = {
	result_cache = {},
	table_cache = {},
}

-- add the given key and value to the cache
function M.cache:set(key, value)
	self.result_cache[self:tuid({ key })] = { value }
end

-- return the value of the given key
function M.cache:get(key)
	local value = self.result_cache[self:tuid({ key })]
	return value and true or false, value and value[1] or nil
end

-- return a uid (an empty table) for the given table
function M.cache:tuid(t)
	local node = self.table_cache
	for k, v in self:dspairs(t) do
		node.children = node.children or {}
		node.children[k] = node.children[k] or {}
		node.children[k][v] = node.children[k][v] or {}
		node = node.children[k][v]
	end
	node.uid = node.uid or {}
	return node.uid
end

-- digestive sorted pairs; an iterator that iterates over the digest() of
-- the keys and values of the given table in a repeatable manner (sorted
-- based on the digest of the keys)
function M.cache:dspairs(t)
	local keys, values = {}, {} -- arrays of digested keys and values
	for k, v in pairs(t) do
		table.insert(keys, self:digest(k))
		table.insert(values, self:digest(v))
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local i = 0
	return function()
		i = i + 1
		return keys[i], values[i]
	end
end

-- return a digest for the given value
function M.cache:digest(v)
	local type = type(v)
	if type == "number" then
		return v
	elseif type == "table" then
		return self:tuid(v)
	elseif type == "function" then
		return type .. M.fndigest(v)
	else
		return type .. tostring(v)
	end
end

-----
-----

-- return a memoized version of the given function
function M.memoize(fn)
	local cache = M.cache:new()
	return function(...)
		local params = { ... }
		local success, results = cache:get(params)
		if not success then
			results = { fn(...) }
			cache:set(params, pl.tablex.deepcopy(results))
		end
		return M.unpack(results)
	end
end

-- return an rmni()-ed deepcopy of the 'original' table
function M.morph(original, overrides)
	local new = M.rmni(pl.tablex.deepcopy(original))
	if type(overrides) == "table" then
		for k, v in pairs(overrides) do
			new[k] = pl.tablex.deepcopy(v)
		end
	elseif type(overrides) ~= "nil" then
		error("the second argument to morph() should be a table or nil")
	end
	return new
end

-- return a string representation of the given function.
-- the digest is the same for pure lua functions with the same bytecode.
function M.fndigest(fn)
	local success, dump = pcall(function()
		return string.dump(fn)
	end)
	dump = success and dump or ""
	local noups = (debug.getinfo(fn).nups == 0)
	local address = (dump and noups) and "" or tostring(fn)
	return address .. dump
end

-- set the metatable of the given table
-- to a copy with the __newindex metamethod removed.
-- this is useful to make the table readwrite again
-- in case it's readonly-ed using a __newindex metamethod.
function M.rmni(t)
	local mt = pl.tablex.deepcopy(getmetatable(t))
	if mt then
		mt.__newindex = nil
		setmetatable(t, mt)
	end
	return t
end

-----
-----

-- make the classes immutable
M.class = M.class:newclass(M.class)
M.cache = M.class:newclass(M.cache)

-----
-----

return M
