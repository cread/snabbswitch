module(...,package.seeall)

local buffer    = require("core.buffer")
local packet    = require("core.packet")
local lib       = require("core.lib")
local link_ring = require("core.link_ring")
local config = require("core.config")
require("core.packet_h")

configuration = config.new()

active_apps  = {}
active_links = {}

-- Change to a new configuration.
function configure (c)
   local old = configuration
   for name, info in pairs(c.apps) do
      if old.apps[name] == nil then
         -- create this app
      elseif old.apps[name].class ~= c.apps[name].class then
         -- replace this app
      elseif old.apps[name].arg ~= c.apps[name].arg then
         -- reconfigure this app
      end
   end
   for name in pairs(old) do
      if c.apps[name] == nil then
         -- delete this app
      end
   end
   -- Delete removed links
   for link in pairs(active_links) do
      if not c.links[link] then
         -- delete this link
      end
   end
   -- Add new links
   for link in pairs(c.links) do
      if not active_links[link] then
         -- create this link
      end
   end
end

function selftest ()
   local c = config.new()
   c.app.vhost_user = {VhostUser, [[{path = "/home/luke/qemu.sock"}]]}
   config.app(c, "vhost_user", VhostUser, [[{path = "/home/luke/qemu.sock"}]])
   config.app(c, "intel",      Intel82599, [[{pciaddr = "0000:01:00.0"}]])
   config.app(c, "vhost_tee",  Tee)
   config.app(c, "intel_tee",  Tee)
   config.app(c, "vhost_dump", PcapWriter, [[{filename = "/tmp/vhost.cap"}]])
   config.app(c, "intel_dump", PcapWriter, [[{filename = "/tmp/intel.cap"}]])
   -- VM->Network path
   config.link(c, "vhost_user.tx -> vhost_tee.input")
   config.link(c, " vhost_tee.dump -> vhost_dump.input")
   config.link(c, " vhost_tee.xmit -> intel.rx")
   -- Network->VM path
   config.link(c, "intel.tx -> intel_tee.input")
   config.link(c, " intel_tee.dump -> intel_dump.input")
   config.link(c, " intel_tee.xmit -> vhost_user.rx")
end

--- # App runtime system

-- Dictionary of all instantiated apps (Name -> App).
apps = {}
appsi = {}
links = {}

function new (class)
   app = { runnable = true,
	   input = {}, output = {},
	   inputi = {}, outputi = {}
	}
   return setmetatable(app, {__index=class})
end

function connect (from_app, from_port, to_app, to_port)
   local name = from_app.."."..from_port.."->"..to_app.."."..to_port
   l = new_link(from_app, from_port, to_app, to_port, apps[to_app])
   links[name] = l
   apps[from_app].output[from_port] = l
   table.insert(apps[from_app].outputi, l)
   apps[to_app].input[to_port] = l
   table.insert(apps[to_app].inputi, l)
end

-- Recompute link state. Needed after adding apps and links.
function relink ()
   appsi = {}
   for _,a in pairs(apps) do
      table.insert(appsi, a)
   end
end

function new_link (iapp, iport, oapp, oport, to_app)
   return { iapp = iapp, iport = iport, oapp = oapp, oport = oport,
            ring = link_ring.new(), to_app = to_app }
end

-- Take a breath. First "inhale" by pulling in packets from all
-- available sources. Then "exhale" by pushing the packets through
-- links until the stop.
function breathe ()
   -- Inhale
   for _, app in ipairs(appsi) do
      if app.pull then app:pull() end
      app.runnable = true
   end
   -- Exhale
   repeat
      local progress = false
      for _, app in ipairs(appsi) do
	 if app.runnable and app.push then
	    app.runnable = false
	    app:push()
	    progress = true
	    -- Free packets
	    --[[
	    for an,app in pairs(apps) do
	       for inn,i in pairs(app.input) do
		  link_ring.cleanup_after_receive(i.ring)
	       end
	    end
	    --]]
	 end
      end
   until not progress
   -- (TODO) Timer-driven callbacks
   -- (TODO) Status reporting / counter collection
   -- (TODO) Restart crashed apps after delay
end

function report ()
   print("link report")
   for name, l in pairs(links) do
      print(name, lib.comma_value(tostring(tonumber(l.ring.stats.tx))) .. " packet(s) transmitted")
   end
   for name, app in pairs(apps) do
      if app.report then app:report() end
   end
end

function transmit (l, p)
   l.to_app.runnable = true
   link_ring.transmit(l.ring, p)
end

function receive (l)
   return link_ring.receive(l.ring)
end

function full (l)
   return link_ring.full(l.ring)
end

function empty (l)
   return link_ring.empty(l.ring)
end

function nreadable (l)
   return link_ring.nreadable(l.ring)
end

function nwritable (l)
   return link_ring.nwritable(l.ring)
end

--- # Diagnostics

function graphviz ()
   local viz = 'digraph app {\n'
   for appname,app in pairs(apps) do
      viz = viz..'  '..appname..'\n'
   end
   for _,link in pairs(links) do
      local traffic = lib.comma_value(tonumber(link.ring.stats.tx))
      viz = viz..'  '..link.iapp.." -> "..link.oapp..' [label="'..traffic..'"]\n'
   end
   viz = viz..'}\n'
   return viz
end

function module_init ()
   -- XXX Find a better place for this.
   require("lib.hardware.bus").scan_devices()
end

module_init()
