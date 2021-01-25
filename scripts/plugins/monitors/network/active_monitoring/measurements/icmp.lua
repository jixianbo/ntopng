--
-- (C) 2020 - ntop.org
--

--
-- This module implements the ICMP probe.
--

local do_trace = false

-- #################################################################

-- This is the script state, which must be manually cleared in the check
-- function. Can be then used in the collect_results function to match the
-- probe requests with probe replies.
local am_hosts = {}
local resolved_hosts = {}

-- #################################################################

-- The function called periodically to send the host probes.
-- measurement is `icmp`
-- hosts contains the list of hosts to probe, The table keys are
-- the hosts identifiers, whereas the table values contain host information
-- see (am_utils.key2host for the details on such format).
local function check_oneshot(measurement, hosts, granularity)
  local plugins_utils = require("plugins_utils")
  local am_utils = plugins_utils.loadModule("active_monitoring", "am_utils")
  local ifname = nil

  am_hosts[measurement] = {}
  resolved_hosts[measurement] = {}

  for key, host in pairs(hosts) do
    local domain_name = host.host
    local ip_address = am_utils.resolveHost(domain_name)

    if do_trace then
      print("["..measurement.."] Pinging address "..tostring(ip_address).."/"..domain_name.."\n")
    end

    if not ip_address then
      goto continue
    end

    -- ICMP results are retrieved in batch (see below ntop.collectPingResults)
    ntop.pingHost(ip_address, isIPv6(ip_address), false --[[ one shot ICMP]], ifname)

    am_hosts[measurement][ip_address] = key
    resolved_hosts[measurement][key] = {
       resolved_addr = ip_address,
    }

    ::continue::
  end
end

-- #################################################################

-- @brief Async ping
local function check_icmp_oneshot(hosts, granularity)
   check_oneshot("icmp", hosts, granularity)
end

-- #################################################################

-- The function responsible for collecting the results.
-- measurement is `icmp`
-- It must return a table containing a list of hosts along with their retrieved
-- measurement. The keys of the table are the host key. The values have the following format:
--  table
--	resolved_addr: (optional) the resolved IP address of the host
--	value: (optional) the measurement numeric value. If unspecified, the host is still considered unreachable.
local function collect_oneshot(measurement, granularity)
   -- Collect possible ICMP results
   for _, ipv6_results in ipairs({false --[[ collect IPv4 results --]], true --[[ collect IPv6 results --]]}) do
      local res = ntop.collectPingResults(ipv6_results, false --[[ one shot ICMP]])

      for host, value in pairs(res or {}) do
	 local key = am_hosts[measurement][host]

	 if(do_trace) then
	    print("["..measurement.."] Reading ICMP response for host ".. host .."\n")
	    print("["..measurement.."] value: ".. value .." key: "..(key or "nil").."\n")
	 end

	 if resolved_hosts[measurement][key] then
	    -- Report the host as reachable with its value
	    resolved_hosts[measurement][key].value = tonumber(value)
	 end
      end
   end

  -- NOTE: unreachable hosts can still be reported in order to properly
  -- display their resolved address
  return resolved_hosts[measurement]
end

-- #################################################################

-- @brief Collect async ping results (ipv4 icmp)
local function collect_icmp_oneshot(granularity)
   return collect_oneshot("icmp", granularity)
end

-- #################################################################

local function check_icmp_available()
  return(ntop.isPingAvailable())
end

-- #################################################################

return {
  -- Defines a list of measurements implemented by this script.
  -- The probing logic is implemented into the check() and collect_results().
  --
  -- Here is how the probing occurs:
  --	1. The check function is called with the list of hosts to probe. Ideally this
  --	   call should not block (e.g. should not wait for the results)
  --	2. The active_monitoring.lua code sleeps for some seconds
  --	3. The collect_results function is called. This should retrieve the results
  --       for the hosts checked in the check() function and return the results.
  --
  -- The alerts for non-responding hosts and the Active Monitoring timeseries are automatically
  -- generated by active_monitoring.lua . The timeseries are saved in the following schemas:
  -- "am_host:val_min", "am_host:val_5mins", "am_host:val_hour".
  measurements = {
    {
      -- The unique key for the measurement
      key = "icmp",
      -- The localization string for this measurement
      i18n_label = "icmp",
      -- The function called periodically to send the host probes
      check = check_icmp_oneshot,
      -- The function responsible for collecting the results
      collect_results = collect_icmp_oneshot,
      -- The granularities allowed for the probe. See supported_granularities in active_monitoring.lua
      granularities = {"min", "5mins", "hour"},
      -- The localization string for the measurement unit (e.g. "ms", "Mbits")
      i18n_unit = "active_monitoring_stats.msec",
      -- The localization string for the Jitter unit (e.g. "ms", "Mbits")
      i18n_jitter_unit = nil,
      -- The localization string for the Active Monitoring timeseries menu entry
      i18n_am_ts_label = "graphs.num_ms_rtt",
      -- The operator to use when comparing the measurement with the threshold, "gt" for ">" or "lt" for "<".
      operator = "gt",
      -- If set, indicates a maximum threshold value
      max_threshold = 10000,
      -- If set, indicates the default threshold value
      default_threshold = nil,
      -- A list of additional timeseries (the am_host:val_* is always shown) to show in the charts.
      -- See https://www.ntop.org/guides/ntopng/api/timeseries/adding_new_timeseries.html#charting-new-metrics .
      additional_timeseries = {},
      -- Js function to call to format the measurement value. See ntopng_utils.js .
      value_js_formatter = "NtopUtils.fmillis",
      -- The raw measurement value is multiplied by this factor before being written into the chart
      chart_scaling_value = 1,
      -- The localization string for the Active Monitoring metric in the chart
      i18n_am_ts_metric = "flow_details.round_trip_time",
      -- A list of additional notes (localization strings) to show into the timeseries charts
      i18n_chart_notes = {},
      -- If set, the user cannot change the host
      force_host = nil,
      -- An alternative localization string for the unrachable alert message
      unreachable_alert_i18n = nil,
    },
  },

  -- A setup function to possibly disable the plugin
  setup = check_icmp_available,
}
