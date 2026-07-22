# Marvell CPSS Quick Reference

## Device Connection

```bash
# Connect to UDM-Beast serial console
telnet localhost 4501

# Enter Lua CLI
busybox telnet localhost 12345
```

## Common CPSS API Patterns

### Calling CPSS APIs from Lua

```lua
result, values = myGenWrapper("cpssDxChFunctionName", {
    {"IN",  "GT_U8",   "devNum",  0},
    {"IN",  "GT_U32",  "portNum", 6},
    {"OUT", "GT_BOOL", "outputParam"}
})

if result == 0 then  -- GT_OK
    print("Success:", values["outputParam"])
end
```

### Parameter Directions
- `"IN"` - Input parameter (provide value)
- `"OUT"` - Output parameter (omit value)
- `"INOUT"` - Both input and output

## Quick Commands

### Port Operations
```
show interfaces status all
show interfaces ethernet 0/6 configuration
cpss-api call cpssDxChPortLinkStatusGet devNum 0 portNum 6
cpss-api call cpssDxChPortSpeedGet devNum 0 portNum 6
```

### Trunk/Port-Channel
```
show interfaces port-channel
show interfaces port-channel 20
```

### VLAN
```
show vlan id 100
show vlan
```

### ACL/PCL
```
show access-list device 0
show access-list device 0 pcl-ID 11
```

## API Discovery

```
Console# cpss-api search <keyword>     # Find APIs
Console# cpss-api man <function>       # Get documentation
Console# cpss-api call <function> ...  # Test API directly
```

## Common Return Codes

| Code | Name | Meaning |
|------|------|---------|
| 0 | GT_OK | Success |
| 1 | GT_FAIL | General failure |
| 4 | GT_NOT_FOUND | Entry not found |
| 0x10 | GT_NOT_ALLOWED | Operation not allowed |
| 0x11 | GT_NOT_INITIALIZED | Not initialized |

## Configuration Template

```
Console# configure
Console(config)# [configuration commands]
Console(config)# end
Console# show [verify configuration]
```

## Validation Pattern

```lua
-- 1. Configure
local ret = myGenWrapper("cpssDxChConfigSet", {...})

-- 2. Verify by reading back
local ret, val = myGenWrapper("cpssDxChConfigGet", {...})

-- 3. Check result
if ret == 0 and val.param == expected then
    print("✓ Configuration successful")
else
    print("✗ Configuration failed")
end
```
