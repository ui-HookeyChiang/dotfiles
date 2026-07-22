---
name: marvell-cpss
description: >-
  Configure and control Marvell DxCh switches via CPSS Lua CLI. Use for port/VLAN/ACL/QoS configuration, CPSS API testing, or tc956xmac driver development on cpss-app and UDM-Beast. NOT for network-layer diagnosis (use ubiquiti-gw-network).
argument-hint: "<device> [port|vlan|trunk|acl|qos|lag]"
test-devices: "UDM-Beast"
landing-group: debug
---

# Marvell CPSS Control

Configure and control Marvell DxCh switches via CPSS APIs / Lua CLI.

## Quick Start

### Access Device
```bash
# Serial console (via ser2net)
telnet localhost 4501

# Lua CLI (on device)
busybox telnet localhost 12345
```

### Common Tasks

**Configure Port-Channel (LAG)**
```
configure
interface range ethernet 0/1-2
channel-group 20
exit
port-channel load-balance src-dst-mac-ip-port
end
```

**Create VLAN**
```
configure
interface vlan device 0 vid 100
interface range ethernet 0/1-10
switchport allowed vlan add 100 untagged
switchport pvid 100
end
```

**Setup ACL Redirect**
```
configure
access-list device 0 pcl-ID 11
rule-id 18 action permit mac-destination 01:80:C2:00:00:02 FF:FF:FF:FF:FF:FF redirect-ethernet 0/8
exit
interface ethernet 0/10
service-acl pcl-ID 11 lookup 0
end
```

**Validate Configuration**
```
show interfaces status all
show interfaces port-channel 20
show vlan id 100
show access-list device 0 pcl-ID 11
```

**Check Port AN Status and Speed (diagnostic)**
```
# Inside Lua CLI (busybox telnet localhost 12345):
show interfaces status all
# Shows all ports: link state, speed, duplex, AN status

# For detailed per-port info via cpss-app-client (JSON API, from shell):
cpss-app-client -p "ports/status/8" '{}'
# Returns: portState, speed, duplex, failure reason for port 8 (WAN1 SFP)

cpss-app-client -p "ports/status/0" '{}'
# Port 0 = first edge port (eth2 on UDM-Beast)
```

## Configuration Examples

Comprehensive examples (ACL/PCL, port-channel, VLAN, port config, QoS): [examples.md](references/examples.md)

## Testing CPSS APIs

**Search for APIs**
```
Console# cpss-api search Port
Console# cpss-api search Vlan
Console# cpss-api search Trunk
```

**Get API Documentation**
```
Console# cpss-api man cpssDxChPortLinkStatusGet
```

**Call API Directly**
```
Console# cpss-api call cpssDxChPortLinkStatusGet devNum 0 portNum 6
result=GT_OK = Operation succeeded
values={
  isLinkUp=true
}
```

## Validation

**Use Lua validation script:**
```lua
-- Load on device: /tmp/validate_config.lua
-- Then run specific validations:

validatePortChannel(20)  -- Validate trunk 20
validateVlan(100)        -- Validate VLAN 100
validatePortStatus(0, 6) -- Check port 0/6 status
```

Script available at: [scripts/validate_config.lua](scripts/validate_config.lua)

## Learning New Examples

1. **Explore**: `?` for help, `cpss-api search <keyword>`, `show` for state
2. **Test**: apply in test env → validate with show → verify with `cpss-api call`
3. **Document**: `scripts/learn_example.sh "name"` → edit template → add to examples.md
4. **Share**: CLI commands + underlying APIs + validation steps → [examples.md](references/examples.md)

## Architecture

System layers, Lua↔C interface, `myGenWrapper`, source reading, tracing: [technical-guide.md](references/technical-guide.md)

## Quick Reference

Commands, API patterns, lookups: [cpss-api.md](references/cpss-api.md)

## Common Patterns

### Lua API Call Pattern
```lua
result, values = myGenWrapper("cpssDxChFunctionName", {
    {"IN",  "GT_U8",  "devNum",  0},
    {"IN",  "GT_U32", "portNum", 6},
    {"OUT", "GT_BOOL", "link"}
})

if result == 0 then  -- GT_OK = success
    print("Link status:", values["link"])
end
```

### Configuration Pattern
```
Console# configure          # Enter config mode
Console(config)# [commands] # Configure
Console(config)# end        # Exit config mode
Console# show [...]         # Verify
```

### Validation Pattern
1. Configure with CLI commands
2. Show commands to verify CLI state
3. `cpss-api call` to verify underlying hardware state
4. Lua script for automated validation

## Source Code Locations

```
~/sourcecode/marvell-cpss-extension/
├── lua_cli/scripts/dxCh/
│   ├── exec/               # Show commands
│   ├── configuration/      # Config commands
│   ├── interface/          # Interface commands
│   └── examples/           # Example configs
└── mainLuaWrapper/data/    # API definitions
```

## Troubleshooting

**GT_NOT_INITIALIZED:** run `cpssInitSystem`

**GT_NOT_FOUND:** entry doesn't exist — check with show commands

**Command not found:** check mode (config vs exec), device family (DxCh vs PX), use `?`

**API documentation missing:** check Lua script implementation; `cpss-api search` for related APIs
