-- Copyright 2015-2016 Mirantis, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local string = require 'string'

local message = require 'stacklight.message'
local afd = require 'stacklight.afd'
local afd_annotation = require 'stacklight.afd_annotation'

-- node or service
local afd_type = read_config('afd_type') or error('afd_type must be specified!')
local afd_msg_type
local afd_metric_name

if afd_type == 'node' then
    afd_msg_type = 'afd_node_metric'
    afd_metric_name = 'node_status'
elseif afd_type == 'service' then
    afd_msg_type = 'afd_service_metric'
    afd_metric_name = 'service_status'
else
    error('invalid afd_type value')
end

-- ie: controller for node AFD / rabbitmq for service AFD
local afd_cluster_name = read_config('afd_cluster_name') or
    error('afd_cluster_name must be specified!')

-- ie: cpu for node AFD / queue for service AFD
local afd_logical_name = read_config('afd_logical_name') or
    error('afd_logical_name must be specified!')

local hostname = read_config('hostname') or error('hostname must be specified')

local afd_file = read_config('afd_file') or error('afd_file must be specified')
local all_alarms = require('stacklight_alarms.' .. afd_file)
local A = require 'stacklight.afd_alarms'
A.load_alarms(all_alarms)

function process_message()

    local metric_name = read_message('Fields[name]')
    local ts = read_message('Timestamp')

    local value, err_msg = message.read_values()
    if not value then
        return -1, err_msg
    end
    -- retrieve field values
    local fields = {}
    for _, field in ipairs(A.get_metric_fields(metric_name)) do
        local field_value = read_message(string.format('Fields[%s]', field))
        if not field_value then
            return -1, "Cannot find Fields[" .. field .. "] for the metric " .. metric_name
        end
        fields[field] = field_value
    end
    A.add_value(ts, metric_name, value, fields)
    return 0
end

function timer_event(ns)
    if A.is_started() then
        local state, alarms = A.evaluate(ns)
        if state then -- it was time to evaluate at least one alarm
            for _, alarm in ipairs(alarms) do
                afd.add_to_alarms(
                    alarm.state,
                    alarm.alert['function'],
                    alarm.alert.metric,
                    alarm.alert.fields,
                    {}, -- tags
                    alarm.alert.operator,
                    alarm.alert.value,
                    alarm.alert.threshold,
                    alarm.alert.window,
                    alarm.alert.periods,
                    alarm.alert.message)
            end

            -- Message example:
            -- msg = {
            --     Type = 'afd_node_metric',
            --     Payload = '{"alarms":[...]}',
            --     Fields = {
            --         name = 'node_status',
            --         value = 0,
            --         hostname = 'node1',
            --         source = 'cpu',
            --         cluster = 'system',
            --         dimensions = {'cluster', 'source', 'hostname'},
            --     }
            -- }
            local msg = afd.inject_afd_metric(
                afd_msg_type, afd_metric_name, afd_cluster_name, afd_logical_name,
                state, hostname)

            if msg then
                afd_annotation.inject_afd_annotation(msg)
            end

        end
    else
        A.set_start_time(ns)
    end
end
