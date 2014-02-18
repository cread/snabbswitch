-- 'config' data structure to describe an app network.

module(..., package.seeall)

-- Create a new configuration. Initially there are no apps or links.
function new ()
   return {
      apps = {},         -- list of {name, class, args}
      links = {}         -- table with keys like "a.out -> b.in"
   }
end

-- Add an app to the configuration.
--
-- Example: config.app(c, "nic", Intel82599, [[{pciaddr = "0000:00:01.00"}]])
function app (config, name, class, arg)
   assert(type(name) == "string", "name must be a string")
   assert(type(class) == "table", "class must be a table")
   assert(type(arg)   == "string", "arg must be a string")
   config.apps[names] = { class = class, arg = arg}
end

-- Add a link to the configuration.
--
-- Example: link(myconfig, "nic.tx -> vm.rx")
function link (config, spec)
   assert(parse_link(spec), "syntax error: " .. spec)
   config.links[spec] = true

   local name = ("%s.%s -> %s.%s"):format(fromapp, fromlink, toapp, tolink)
   table.insert(config.links, name)

   config.links[name] = {fromapp, fromlink, toapp, tolink}
   table.insert(config.links, {fromapp, fromlink, toapp, tolink})
end

-- Given "a.out -> b.in" return "a", "out", "b", "in".
function parse_link (spec)
   local fa, fl, ta, tl = spec:gmatch(link_syntax)
   if fa and fl and ta and tl then
      return fa, fl, ta, tl
   end
end

link_syntax = [[ *(%S)+.(%S)+ *-> *(%S)+.(%S)+ *]]

