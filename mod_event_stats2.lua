if module:get_host_type() ~= "component" then
    error("Event logger should be loaded as a component, please see http://prosody.im/doc/components", 0);
end

local jid = require "util.jid";
local json = require "util.json";

local xmlns_log = "urn:xmpp:eventlog";
local log_levels = {
    Debug = "debug",
    Informational = "info",
    Warning = "warn",
    Error = "error"
};


module:depends("disco");
module:add_identity("component", "log", module:get_option_string("name", "Event Logger"));
module:add_feature("urn:xmpp:eventlog");


local function has_prefix(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix;
end

local function get_suffix(str, prefix)
    if has_prefix(str, prefix) then
        return string.sub(str, string.len(prefix) + 1)
    else
        return str;
    end
end

local function process_metric(category, metric_name, log, info)
   local main = {
       metric = metric_name;
       value = 1;
   };
   local meta = {};

   for tag in log:childtags("tag", xmlns_log) do
       local metric = tag.attr.name;
       local value = tag.attr.value;

       if metric == metric_name then
           main.metric = metric;
           main.value = value;
       else
           meta[metric] = value;
       end
   end

   module:log("debug", "METRIC: (%s) Event stat: %s = %s; %s", category, main.metric, main.value, json.encode(meta));
   module:fire_event("eventlog-stat", {
       category = category;
       from = info.user_service;
       service = info.service;
       room = info.room;
       metric = main.metric;
       value = main.value;
       meta = meta;
   });
end

local function process_trace(category, log, info)
    local trace = {};

    for tag in log:childtags("tag", xmlns_log) do
        local key = tag.attr.name;
        local value = tag.attr.value or "";

        if value[1] == '{' or value[1] == '[' then
            value = json.decode(value);
        end

        trace[key] = value;
    end

    local data = {
        category = category;
        from = info.user_service;
        service = info.service;
        room = info.room;
        trace = trace;
    }

    module:log('debug', 'TRACE: (%s) %s', category, json.encode(data));
    module:fire_event("eventlog-trace", data);
end


module:hook("message/host", function (event)
    local origin, stanza = event.origin, event.stanza;
    local user, host, resource = jid.prepped_split(stanza.attr.from)

    local log = stanza:get_child("log", xmlns_log);
    if not log then
        return
    end

    local user_service = host;
    local service = log.attr.facility;
    local room = log.attr.subject;
    local level = log_levels[log.attr.type] or "info";
    local log_type = log.attr.id;

    module:log("debug", "ALLSTATS: Event stat: %s = %s", log, log_type);
    if service and has_prefix(service, 'https://') then
        service = get_suffix(service, 'https://');
    end

    if log_type == 'log' then
        local message = log:get_child_text("message", xmlns_log);
        if not message then
            return;
        end
        module:log(level, "CLIENTLOG: %s", message);
    elseif log_type == 'metric' then
        -- COMPAT
        for tag in log:childtags("tag", xmlns_log) do
            local metric = tag.attr.name;
            local value = tag.attr.value;

            module:log("debug", "METRIC: Event stat: %s = %s", metric, value);
            module:fire_event("eventlog-stat", {
                 from = user_service;
                 service = service;
                 room = room;
                 metric = metric;
                 value = value;
            });
        end
    end

    return true;
end);


module:log("info", "Started event log component");
