# Marvell CPSS Practical Configuration Examples

## Table of Contents
1. [ACL/PCL Examples](#aclpcl-examples)
2. [Port-Channel/Trunk Examples](#port-channeltrunk-examples)
3. [VLAN Examples](#vlan-examples)
4. [QoS Examples](#qos-examples)
5. [Port Configuration Examples](#port-configuration-examples)
6. [Validation Methods](#validation-methods)

---

## ACL/PCL Examples

### Example 1: Redirect LACP Packets (IEEE 802.3ad)

**Use Case:** Redirect all LACP control frames to a specific port for monitoring

#### Configuration Commands
```
Console# configure
Console(config)# access-list device 0 pcl-ID 11
Console(config-access-list)# rule-id 18 action permit \
    mac-destination 01:80:C2:00:00:02 FF:FF:FF:FF:FF:FF \
    redirect-ethernet 0/8
Console(config-access-list)# exit

Console(config)# interface ethernet 0/10
Console(config-if)# service-acl pcl-ID 11 lookup 0
Console(config-if)# exit
Console(config)# end
```

#### What This Does
- **PCL-ID 11**: Creates a Policy Control List with ID 11
- **Rule-ID 18**: Creates a rule with priority/index 18
- **MAC Destination 01:80:C2:00:00:02**: LACP multicast address
- **Redirect to 0/8**: All matching packets go to port 8
- **Applied on 0/10**: Rule is active on ingress port 10

#### Underlying Lua Code
**File:** `lua_cli/scripts/dxCh/configuration/access_list.lua`

```lua
-- When you type: rule-id 18 action permit mac-destination ...
function pcl_rule_add(params)
    -- Build PCL rule structure
    local rule = {
        ruleIndex = params.ruleId,
        ruleFormat = "CPSS_DXCH_PCL_RULE_FORMAT_INGRESS_STD_NOT_IP_E"
    }

    -- Set pattern (match criteria)
    local pattern = {
        macDa = params.macDest,  -- 01:80:C2:00:00:02
    }

    -- Set action (what to do when matched)
    local action = {
        pktCmd = "CPSS_PACKET_CMD_FORWARD_E",
        redirect = {
            redirectCmd = "CPSS_DXCH_PCL_ACTION_REDIRECT_CMD_OUT_IF_E",
            outIf = {
                outInterface = {
                    type = "CPSS_INTERFACE_PORT_E",
                    devPort = {
                        devNum = params.devNum,    -- 0
                        portNum = params.portNum   -- 8
                    }
                }
            }
        }
    }

    -- Call CPSS API
    result = myGenWrapper("cpssDxChPclRuleSet", {
        {"IN", "GT_U8", "devNum", params.devNum},
        {"IN", "GT_U32", "ruleIndex", params.ruleId},
        {"IN", "CPSS_DXCH_PCL_RULE_FORMAT_TYPE_ENT", "ruleFormat", rule.ruleFormat},
        {"IN", "CPSS_DXCH_PCL_RULE_OPTION_ENT", "ruleOptionsBmp", 0},
        {"IN", "CPSS_DXCH_PCL_RULE_FORMAT_UNT", "maskPtr", mask},
        {"IN", "CPSS_DXCH_PCL_RULE_FORMAT_UNT", "patternPtr", pattern},
        {"IN", "CPSS_DXCH_PCL_ACTION_STC", "actionPtr", action}
    })
end
```

#### Validation

**Method 1: Show ACL Configuration**
```
Console# show access-list device 0 pcl-ID 11
```

**Method 2: Show Interface ACL Binding**
```
Console# show interfaces ethernet 0/10 configuration
```

**Method 3: Lua Test Script**
```lua
-- Test if rule is configured correctly
function validateLACPRedirect()
    local ret, val = myGenWrapper("cpssDxChPclRuleGet", {
        {"IN",  "GT_U8",  "devNum", 0},
        {"IN",  "GT_U32", "ruleIndex", 18},
        {"IN",  "CPSS_DXCH_PCL_RULE_FORMAT_TYPE_ENT", "ruleFormat",
         "CPSS_DXCH_PCL_RULE_FORMAT_INGRESS_STD_NOT_IP_E"},
        {"OUT", "CPSS_DXCH_PCL_RULE_FORMAT_UNT", "mask"},
        {"OUT", "CPSS_DXCH_PCL_RULE_FORMAT_UNT", "pattern"},
        {"OUT", "CPSS_DXCH_PCL_ACTION_STC", "action"}
    })

    if ret == 0 then
        print("Rule 18 is configured:")
        print("  Redirect to port:", val.action.redirect.outIf.outInterface.devPort.portNum)
        print("  MAC DA:", string.format("%02X:%02X:%02X:%02X:%02X:%02X",
            val.pattern.macDa[0], val.pattern.macDa[1], val.pattern.macDa[2],
            val.pattern.macDa[3], val.pattern.macDa[4], val.pattern.macDa[5]))
    else
        print("Rule not found or error:", ret)
    end
end
```

### Example 2: Block Telnet Traffic

**Use Case:** Prevent telnet access on all ports for security

#### Configuration
```
Console# configure
Console(config)# access-list device 0 pcl-ID 20
Console(config-access-list)# rule-id 100 action deny l4-dst-port 23
Console(config-access-list)# exit

Console(config)# interface range ethernet 0/1-48
Console(config-if-range)# service-acl pcl-ID 20 lookup 0
Console(config-if-range)# exit
Console(config)# end
```

#### What This Does
- Matches TCP/UDP destination port 23 (Telnet)
- Action: DENY (drop packets)
- Applied to ports 0/1 through 0/48

#### Lua Implementation
```lua
-- rule-id 100 action deny l4-dst-port 23
local action = {
    pktCmd = "CPSS_PACKET_CMD_DROP_HARD_E"  -- Hard drop, no learning
}

local pattern = {
    isIp = true,
    l4Byte2 = 0,     -- L4 destination port high byte
    l4Byte3 = 23     -- L4 destination port low byte (23 = Telnet)
}

local mask = {
    isIp = true,
    l4Byte2 = 0xFF,
    l4Byte3 = 0xFF
}
```

#### Validation
```
Console# show access-list device 0 pcl-ID 20

# Or test with cpss-api
Console# cpss-api call cpssDxChPclRuleGet devNum 0 ruleIndex 100 ...
```

### Example 3: QoS Marking - Set VPT (VLAN Priority Tag)

**Use Case:** Mark specific traffic with high priority (VPT=7)

#### Configuration
```
Console# configure
Console(config)# access-list device 0 pcl-ID 30
Console(config-access-list)# rule-id 200 action permit set-vpt 7 vlan 100
Console(config-access-list)# exit

Console(config)# interface range ethernet 0/1-10
Console(config-if-range)# service-acl pcl-ID 30 lookup 0
Console(config-if-range)# exit
Console(config)# end
```

#### What This Does
- Matches packets in VLAN 100
- Sets 802.1p priority (VPT) to 7 (highest priority)
- Applied to ports 1-10

#### Lua Implementation
```lua
local action = {
    pktCmd = "CPSS_PACKET_CMD_FORWARD_E",
    qos = {
        profileAssignIndex = true,
        profileIndex = 7,
        modifyUp = "CPSS_DXCH_PCL_ACTION_QOS_MODIFY_UP_ENABLE_E",
        up = 7  -- VPT value
    }
}

local pattern = {
    vid = 100  -- VLAN ID
}
```

### Example 4: Mirror to CPU

**Use Case:** Send copies of specific traffic to CPU for analysis

#### Configuration
```
Console# configure
Console(config)# access-list device 0 pcl-ID 40
Console(config-access-list)# rule-id 50 action trap \
    mac-source 00:11:22:33:44:55 FF:FF:FF:FF:FF:FF
Console(config-access-list)# exit

Console(config)# interface ethernet 0/5
Console(config-if)# service-acl pcl-ID 40 lookup 0
Console(config-if)# exit
Console(config)# end
```

#### Lua Implementation
```lua
local action = {
    pktCmd = "CPSS_PACKET_CMD_TRAP_TO_CPU_E",
    mirror = {
        mirrorToRxAnalyzerPort = true
    }
}

local pattern = {
    macSa = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55}
}
```

### Example 5: Rate Limiting with ACL

**Use Case:** Limit broadcast traffic to 1000 pps

#### Configuration
```
Console# configure
Console(config)# access-list device 0 pcl-ID 50
Console(config-access-list)# rule-id 60 action permit \
    mac-destination FF:FF:FF:FF:FF:FF FF:FF:FF:FF:FF:FF \
    policer-id 10
Console(config-access-list)# exit

# Configure policer
Console(config)# policer device 0 policer-id 10 \
    rate 1000 burst 100 meter-mode srTCM
Console(config)# end
```

---

## Port-Channel/Trunk Examples

### Example 6: Create LAG/Trunk (LACP)

**Use Case:** Aggregate ports for redundancy and bandwidth

#### Configuration
```
Console# configure
Console(config)# interface range ethernet 0/1-2
Console(config-if-range)# channel-group 20
Console(config-if-range)# exit

Console(config)# port-channel load-balance src-dst-mac-ip-port
Console(config)# exit

Console# show interfaces port-channel 20

Channel          Ports
-------   ---------------------
  20       0/1, 0/2
```

#### Lua Implementation
**File:** `lua_cli/scripts/dxCh/configuration/channel_group.lua`

```lua
function channel_group_func(params)
    local trunkId = params["trunkID"]  -- 20
    local devNum, portNum

    -- For each port in range
    for iterator, devNum, portNum in command_data:getPortIterator() do
        -- Convert port to hardware format
        result, hwDevNum, hwPortNum =
            device_port_to_hardware_format_convert(devNum, portNum)

        -- Create trunk member structure
        local trunk_member = {
            hwDevice = hwDevNum,
            port = hwPortNum
        }

        -- Add member to trunk
        result = myGenWrapper("cpssDxChTrunkMemberAdd", {
            {"IN", "GT_U8", "devNum", devNum},
            {"IN", "GT_TRUNK_ID", "trunkId", trunkId},
            {"IN", "CPSS_TRUNK_MEMBER_STC", "memberPtr", trunk_member}
        })

        if result ~= 0 then
            print("Error adding port to trunk:", result)
        end
    end
end
```

#### Load Balancing Configuration
```lua
-- port-channel load-balance src-dst-mac-ip-port
result = myGenWrapper("cpssDxChTrunkHashGlobalModeSet", {
    {"IN", "GT_U8", "devNum", 0},
    {"IN", "CPSS_DXCH_TRUNK_LBH_GLOBAL_MODE_ENT", "hashMode",
     "CPSS_DXCH_TRUNK_LBH_PACKETS_INFO_E"}
})

-- Enable L2+L3+L4 hashing
result = myGenWrapper("cpssDxChTrunkHashL4ModeSet", {
    {"IN", "GT_U8", "devNum", 0},
    {"IN", "CPSS_DXCH_TRUNK_L4_LBH_MODE_ENT", "hashMode",
     "CPSS_DXCH_TRUNK_L4_LBH_LONG_E"}  -- Use src+dst port
})
```

#### Validation
```lua
function validateTrunk(trunkId)
    -- Get trunk members
    local ret, val = myGenWrapper("cpssDxChTrunkTableEntryGet", {
        {"IN",  "GT_U8", "devNum", 0},
        {"IN",  "GT_TRUNK_ID", "trunkId", trunkId},
        {"OUT", "GT_U32", "numOfEnabledMembersPtr"},
        {"OUT", "CPSS_TRUNK_MEMBER_STC", "enabledMembersArray", 12}
    })

    if ret == 0 then
        print(string.format("Trunk %d has %d members:",
            trunkId, val.numOfEnabledMembersPtr))

        for i = 0, val.numOfEnabledMembersPtr - 1 do
            print(string.format("  Port %d/%d",
                val.enabledMembersArray[i].hwDevice,
                val.enabledMembersArray[i].port))
        end
    end
end

validateTrunk(20)
```

### Example 7: Delete Trunk

```
Console# configure
Console(config)# interface range ethernet 0/1-2
Console(config-if-range)# no channel-group 20
Console(config-if-range)# exit
Console(config)# end
```

#### Lua Implementation
```lua
-- no channel-group 20
result = myGenWrapper("cpssDxChTrunkMemberRemove", {
    {"IN", "GT_U8", "devNum", devNum},
    {"IN", "GT_TRUNK_ID", "trunkId", trunkId},
    {"IN", "CPSS_TRUNK_MEMBER_STC", "memberPtr", trunk_member}
})
```

---

## VLAN Examples

### Example 8: Create VLAN and Assign Ports

**Use Case:** Create VLAN 100 for guest network

#### Configuration
```
Console# configure
Console(config)# interface vlan device 0 vid 100
Console(config-if)# exit

Console(config)# interface range ethernet 0/1-10
Console(config-if-range)# switchport allowed vlan add 100 untagged
Console(config-if-range)# switchport pvid 100
Console(config-if-range)# exit
Console(config)# end
```

#### Lua Implementation
```lua
-- interface vlan device 0 vid 100
result = myGenWrapper("cpssDxChBrgVlanEntryWrite", {
    {"IN", "GT_U8", "devNum", 0},
    {"IN", "GT_U16", "vlanId", 100},
    {"IN", "CPSS_PORTS_BMP_STC", "portsMembers", portsBmp},
    {"IN", "CPSS_PORTS_BMP_STC", "portsTagging", portsTagBmp},
    {"IN", "CPSS_DXCH_BRG_VLAN_INFO_STC", "vlanInfoPtr", vlanInfo},
    {"IN", "CPSS_DXCH_BRG_VLAN_PORTS_TAG_CMD_STC", "portsTaggingCmd", tagCmd}
})

-- Set PVID for each port
result = myGenWrapper("cpssDxChBrgVlanPortVidSet", {
    {"IN", "GT_U8", "devNum", devNum},
    {"IN", "GT_PORT_NUM", "portNum", portNum},
    {"IN", "GT_U16", "vlanId", 100}
})
```

#### Validation
```lua
function validateVlan(vlanId)
    local ret, val = myGenWrapper("cpssDxChBrgVlanEntryRead", {
        {"IN",  "GT_U8", "devNum", 0},
        {"IN",  "GT_U16", "vlanId", vlanId},
        {"OUT", "CPSS_PORTS_BMP_STC", "portsMembers"},
        {"OUT", "CPSS_PORTS_BMP_STC", "portsTagging"},
        {"OUT", "CPSS_DXCH_BRG_VLAN_INFO_STC", "vlanInfo"}
    })

    if ret == 0 then
        print("VLAN", vlanId, "exists")
        print("Member ports:", val.portsMembers)
        print("Tagged ports:", val.portsTagging)
    else
        print("VLAN not configured")
    end
end
```

### Example 9: VLAN Trunking

**Use Case:** Allow multiple VLANs on uplink port

```
Console# configure
Console(config)# interface ethernet 0/48
Console(config-if)# switchport mode trunk
Console(config-if)# switchport allowed vlan add 10,20,30,40 tagged
Console(config-if)# exit
Console(config)# end
```

---

## QoS Examples

### Example 10: Port-Based QoS

**Use Case:** Set default priority for a port

```
Console# configure
Console(config)# interface ethernet 0/5
Console(config-if)# qos default-up 5
Console(config-if)# exit
Console(config)# end
```

#### Lua Implementation
**File:** `lua_cli/scripts/dxCh/interface/qos_default_up.lua`

```lua
result = myGenWrapper("cpssDxChCosPortDefaultUpSet", {
    {"IN", "GT_U8", "devNum", devNum},
    {"IN", "GT_PORT_NUM", "portNum", portNum},
    {"IN", "GT_U8", "defaultUserPrio", 5}
})
```

### Example 11: DSCP to Queue Mapping

```
Console# configure
Console(config)# qos map dscp-to-queue 46 queue 7
Console(config)# qos map dscp-to-queue 0 queue 0
Console(config)# end
```

---

## Port Configuration Examples

### Example 12: Configure Port Speed and Duplex

```
Console# configure
Console(config)# interface ethernet 0/10
Console(config-if)# speed 10000
Console(config-if)# duplex full
Console(config-if)# no shutdown
Console(config-if)# exit
Console(config)# end
```

#### Lua Implementation
```lua
-- speed 10000 (10G)
result = myGenWrapper("cpssDxChPortSpeedSet", {
    {"IN", "GT_U8", "devNum", devNum},
    {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
    {"IN", "CPSS_PORT_SPEED_ENT", "speed", "CPSS_PORT_SPEED_10000_E"}
})

-- duplex full
result = myGenWrapper("cpssDxChPortDuplexModeSet", {
    {"IN", "GT_U8", "devNum", devNum},
    {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
    {"IN", "CPSS_PORT_DUPLEX_ENT", "dMode", "CPSS_PORT_FULL_DUPLEX_E"}
})

-- no shutdown
result = myGenWrapper("cpssDxChPortEnableSet", {
    {"IN", "GT_U8", "devNum", devNum},
    {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
    {"IN", "GT_BOOL", "enable", true}
})
```

### Example 13: Configure Port Loopback

**Use Case:** Test port without external cable

```
Console# configure
Console(config)# interface ethernet 0/6
Console(config-if)# loopback internal
Console(config-if)# exit
Console(config)# end
```

#### Lua Implementation
```lua
result = myGenWrapper("cpssDxChPortInternalLoopbackEnableSet", {
    {"IN", "GT_U8", "devNum", devNum},
    {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
    {"IN", "GT_BOOL", "enable", true}
})
```

### Example 14: Storm Control

**Use Case:** Limit broadcast/multicast traffic

```
Console# configure
Console(config)# interface ethernet 0/10
Console(config-if)# storm-control broadcast rate 1000
Console(config-if)# storm-control multicast rate 2000
Console(config-if)# exit
Console(config)# end
```

---

## Validation Methods

### Method 1: Show Commands

```bash
# Show all configured ACLs
show access-list device 0

# Show specific PCL
show access-list device 0 pcl-ID 11

# Show port channel
show interfaces port-channel 20

# Show VLAN
show vlan id 100

# Show port status
show interfaces status all

# Show port configuration
show interfaces ethernet 0/10 configuration
```

### Method 2: Direct CPSS API Calls

```
# Get port link status
Console# cpss-api call cpssDxChPortLinkStatusGet devNum 0 portNum 6

# Get trunk members
Console# cpss-api call cpssDxChTrunkTableEntryGet devNum 0 trunkId 20

# Get VLAN entry
Console# cpss-api call cpssDxChBrgVlanEntryRead devNum 0 vlanId 100

# Get PCL rule
Console# cpss-api call cpssDxChPclRuleGet devNum 0 ruleIndex 18 ...
```

### Method 3: Lua Validation Scripts

Create `/tmp/validate_config.lua`:

```lua
-- Comprehensive validation script

function validatePortChannel(trunkId)
    print("=== Validating Port-Channel", trunkId, "===")

    local ret, val = myGenWrapper("cpssDxChTrunkTableEntryGet", {
        {"IN",  "GT_U8", "devNum", 0},
        {"IN",  "GT_TRUNK_ID", "trunkId", trunkId},
        {"OUT", "GT_U32", "numOfEnabledMembersPtr"},
        {"OUT", "CPSS_TRUNK_MEMBER_STC", "enabledMembersArray", 12}
    })

    if ret == 0 then
        print(string.format("Status: PASS - %d members configured",
            val.numOfEnabledMembersPtr))
        return true
    else
        print("Status: FAIL - Trunk not configured")
        return false
    end
end

function validateVlan(vlanId)
    print("=== Validating VLAN", vlanId, "===")

    local ret, val = myGenWrapper("cpssDxChBrgVlanEntryRead", {
        {"IN",  "GT_U8", "devNum", 0},
        {"IN",  "GT_U16", "vlanId", vlanId},
        {"OUT", "CPSS_PORTS_BMP_STC", "portsMembers"},
        {"OUT", "CPSS_PORTS_BMP_STC", "portsTagging"},
        {"OUT", "CPSS_DXCH_BRG_VLAN_INFO_STC", "vlanInfo"}
    })

    if ret == 0 then
        print("Status: PASS - VLAN exists")
        return true
    else
        print("Status: FAIL - VLAN not found")
        return false
    end
end

function validateACL(pclId, ruleId)
    print("=== Validating ACL PCL-ID", pclId, "Rule", ruleId, "===")

    local ret, val = myGenWrapper("cpssDxChPclRuleGet", {
        {"IN",  "GT_U8", "devNum", 0},
        {"IN",  "GT_U32", "ruleIndex", ruleId},
        {"IN",  "CPSS_DXCH_PCL_RULE_FORMAT_TYPE_ENT", "ruleFormat",
         "CPSS_DXCH_PCL_RULE_FORMAT_INGRESS_STD_NOT_IP_E"},
        {"OUT", "CPSS_DXCH_PCL_RULE_FORMAT_UNT", "mask"},
        {"OUT", "CPSS_DXCH_PCL_RULE_FORMAT_UNT", "pattern"},
        {"OUT", "CPSS_DXCH_PCL_ACTION_STC", "action"}
    })

    if ret == 0 then
        print("Status: PASS - Rule configured")
        print("  Action:", val.action.pktCmd)
        return true
    else
        print("Status: FAIL - Rule not found")
        return false
    end
end

-- Run validations
validatePortChannel(20)
validateVlan(100)
validateACL(11, 18)
```

Load and run:
```
Console# load /tmp/validate_config.lua
```

### Method 4: Automated Testing

Create test suite in `/tmp/test_suite.lua`:

```lua
local test_results = {}

function test(name, func)
    print("\n>>> Running test:", name)
    local success, result = pcall(func)

    if success and result then
        print("✓ PASS:", name)
        table.insert(test_results, {name = name, status = "PASS"})
    else
        print("✗ FAIL:", name)
        table.insert(test_results, {name = name, status = "FAIL"})
    end
end

-- Test suite
test("Port-Channel 20 exists", function()
    return validatePortChannel(20)
end)

test("VLAN 100 configured", function()
    return validateVlan(100)
end)

test("ACL rule 18 active", function()
    return validateACL(11, 18)
end)

test("Port 0/6 link is UP", function()
    local ret, val = myGenWrapper("cpssDxChPortLinkStatusGet", {
        {"IN", "GT_U8", "devNum", 0},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", 6},
        {"OUT", "GT_BOOL", "isLinkUp"}
    })
    return ret == 0 and val.isLinkUp == true
end)

-- Print summary
print("\n" .. string.rep("=", 50))
print("TEST SUMMARY")
print(string.rep("=", 50))

local pass_count = 0
for _, test in ipairs(test_results) do
    print(string.format("%-40s %s", test.name, test.status))
    if test.status == "PASS" then
        pass_count = pass_count + 1
    end
end

print(string.rep("=", 50))
print(string.format("Total: %d  Passed: %d  Failed: %d",
    #test_results, pass_count, #test_results - pass_count))
```

---

## Quick Reference

### Common ACL Actions
```
action permit                    # Allow packet
action deny                      # Drop packet
action trap                      # Send to CPU
action mirror                    # Mirror to analyzer port
action redirect-ethernet X/Y     # Redirect to port
action policer-id N              # Apply rate limiting
action set-vpt N                 # Set VLAN priority
action set-dscp N                # Set DSCP value
```

### Common Match Criteria
```
mac-source <MAC> <mask>          # Match source MAC
mac-destination <MAC> <mask>     # Match destination MAC
vlan <vid>                       # Match VLAN ID
l4-src-port <port>               # Match TCP/UDP source port
l4-dst-port <port>               # Match TCP/UDP dest port
dscp <value>                     # Match DSCP
```

### Port-Channel Commands
```
channel-group <ID>               # Add port to trunk
no channel-group <ID>            # Remove port from trunk
port-channel load-balance <mode> # Set hash algorithm
show interfaces port-channel <ID> # Show trunk status
```

### VLAN Commands
```
interface vlan device <dev> vid <vid>  # Create VLAN
switchport allowed vlan add <vid>      # Add VLAN to port
switchport pvid <vid>                  # Set native VLAN
switchport mode {access|trunk}         # Set port mode
```

---

*Document created from practical Marvell CPSS CLI examples*
*Last updated: 2026-01-30*
