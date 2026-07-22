# Marvell CPSS Control with Lua - Deep Learning Guide

## Table of Contents
1. [System Architecture](#system-architecture)
2. [Source Code Structure](#source-code-structure)
3. [How Lua Interfaces with CPSS C Code](#how-lua-interfaces-with-cpss-c-code)
4. [Reading marvell-cpss-extension Code](#reading-marvell-cpss-extension-code)
5. [Validating Code with Lua CLI](#validating-code-with-lua-cli)
6. [Practical Examples](#practical-examples)

---

## System Architecture

### Hardware Layer
```
┌──────────────────────────────────────────────┐
│  UDM-Beast (Marvell Switch Device)           │
│  - Marvell DxCh Switch Chip                  │
│  - ARM64 CPU running Debian                  │
└──────────────────────────────────────────────┘
         │ (Serial Console)
         │ /dev/ttyUSB1 @ 115200 N81
         ▼
┌──────────────────────────────────────────────┐
│  ser2net (Serial-to-Network Bridge)          │
│  Port: 4501 → /dev/ttyUSB1                   │
└──────────────────────────────────────────────┘
         │ (telnet localhost 4501)
         ▼
┌──────────────────────────────────────────────┐
│  Linux Shell (root@UDM-Beast)                │
└──────────────────────────────────────────────┘
         │ (busybox telnet localhost 12345)
         ▼
┌──────────────────────────────────────────────┐
│  CPSS Application Layer                      │
│  - cpss-app (Main application)               │
│  - Lua CLI Server (Port 12345)               │
└──────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Lua CLI Interface                           │
│  - Lua 5.1 Interpreter                       │
│  - Mini-XML Engine                           │
│  - Command Parser                            │
└──────────────────────────────────────────────┘
         │ (myGenWrapper)
         ▼
┌──────────────────────────────────────────────┐
│  CPSS C Library (marvell-cpss)               │
│  - CPSS 4.3.17.015                          │
│  - DxCh version 4.3.17.25.03                │
└──────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Hardware Abstraction Layer                  │
│  - Register Access                           │
│  - DMA, Interrupts                           │
└──────────────────────────────────────────────┘
```

---

## Source Code Structure

### marvell-cpss-extension Directory Layout

```
~/sourcecode/marvell-cpss-extension/
├── main.c                          # Entry point, calls cpssLibConstructor
├── Makefile                        # Build system
├── config.mk                       # Build configuration
│
├── lua_cli/                        # ★ Lua CLI Implementation
│   ├── scripts/                    # ★ All Lua scripts for CLI
│   │   ├── CLI.lua                 # Main CLI loop
│   │   ├── initCLI.lua             # CLI initialization
│   │   ├── cmdLuaCLIDefs.lua       # Command definitions
│   │   ├── common/                 # Common scripts for all devices
│   │   │   ├── misc/
│   │   │   │   └── myGenWrapper.lua  # ★★ Lua-to-C wrapper function
│   │   │   ├── cli_types/          # Type definitions
│   │   │   └── exec/               # Exec mode commands
│   │   ├── dxCh/                   # ★ DxCh-specific scripts
│   │   │   ├── exec/               # Show commands, etc.
│   │   │   │   ├── show_interfaces_status.lua
│   │   │   │   ├── show_interfaces_mac_counters.lua
│   │   │   │   └── ...
│   │   │   ├── configuration/      # Config mode commands
│   │   │   ├── interface/          # Interface configuration
│   │   │   ├── debug/              # Debug commands
│   │   │   └── cli_types/          # DxCh-specific types
│   │   └── px/                     # PX-specific scripts
│   │
│   ├── inc/                        # C headers for Lua CLI
│   ├── tools/                      # CLI tools
│   └── docs/                       # Documentation
│
├── mainLuaWrapper/                 # ★★ Lua-C binding layer
│   ├── src/                        # C implementation of Lua bindings
│   └── data/                       # XML API definitions
│       ├── dxCh_xml/
│       │   └── cpssAPI.xml         # ★ CPSS API declarations for Lua
│       └── dxpx_xml/
│
├── cpssEnabler/                    # CPSS Enabler code
│   ├── mainSysConfig/              # System configuration
│   ├── mainCmd/                    # Command engine
│   └── mainPpDrv/                  # Packet Processor driver
│
├── extension/                      # ★ CPSS Extensions
│   ├── firmware/                   # Firmware extensions
│   ├── serdes/                     # SERDES extensions
│   ├── macSecApp/                  # MACSec application
│   └── srvCpu/                     # Service CPU extensions
│
├── mainExtUtils/                   # External utilities
├── mainGaltisWrapper/              # Galtis wrapper (legacy CLI)
├── mainPpDrv/                      # PP driver extensions
├── mainUT/                         # Unit tests
├── platform/                       # Platform-specific code
└── simulation/                     # Simulation support
```

---

## How Lua Interfaces with CPSS C Code

### The Call Chain

```
User Command → CLI Parser → Lua Script → myGenWrapper → C Wrapper → CPSS API → Hardware
```

### Example: Getting Port Link Status

#### 1. User Types Command
```
Console# show interfaces status all
```

#### 2. CLI Parser Matches Command
Located in: `lua_cli/scripts/dxCh/exec/show_interfaces_status.lua`

```lua
-- Command registration (at end of file)
CLI_addCommand("exec", "show interfaces status", {
    func = show_interfaces_status,
    help = "Interface status",
    params = {
        { type = "named",
          { format = "all", name = "all", help = "All interfaces" },
          ...
        }
    }
})
```

#### 3. Lua Function Calls CPSS API via myGenWrapper
From `show_interfaces_status.lua` (line 143):

```lua
result, values = cpssPerPortParamGet("cpssDxChPortLinkStatusGet",
                                     devNum, portNum, "link",
                                     "GT_BOOL")
```

#### 4. cpssPerPortParamGet calls myGenWrapper
Located in: `lua_cli/scripts/common/misc/myGenWrapper.lua`

```lua
function myGenWrapper(funcName, params)
    -- funcName: "cpssDxChPortLinkStatusGet"
    -- params: table of {direction, type, name, value}

    -- Call the C wrapper function
    local ret, values = cpssGenWrapper(funcName, params, isReadOnly)

    return ret, values
end
```

#### 5. cpssGenWrapper (C Function)
This is a C function registered to Lua that:
1. Parses the Lua parameters
2. Converts Lua types to C types
3. Calls the actual CPSS C function
4. Converts C return values back to Lua
5. Returns results to Lua

#### 6. CPSS C Function Executes
```c
GT_STATUS cpssDxChPortLinkStatusGet(
    IN  GT_U8     devNum,
    IN  GT_PHYSICAL_PORT_NUM portNum,
    OUT GT_BOOL   *isLinkUpPtr
)
{
    // Accesses hardware registers
    // Returns GT_OK on success
}
```

---

## Reading marvell-cpss-extension Code

### Methodology: Top-Down Approach

#### Step 1: Start with User-Visible Commands

**Find a command you're interested in:**
```bash
cd ~/sourcecode/marvell-cpss-extension
find lua_cli/scripts -name "*.lua" | xargs grep -l "show interfaces"
```

**Read the command implementation:**
```bash
vim lua_cli/scripts/dxCh/exec/show_interfaces_status.lua
```

**Look for:**
1. Command registration at bottom: `CLI_addCommand(...)`
2. Main function: `local function show_interfaces_status(params)`
3. CPSS API calls: Look for `myGenWrapper`, `cpssPerPortParamGet`, etc.

#### Step 2: Trace CPSS API Calls

**Pattern Recognition:**

```lua
-- Direct myGenWrapper call:
result, values = myGenWrapper("cpssDxChPortFecModeGet", {
    {"IN",  "GT_U8",        "devNum",  devNum},
    {"IN",  "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
    {"OUT", "CPSS_DXCH_PORT_FEC_MODE_ENT", "mode"}
})

-- Helper function call:
result, values = cpssPerPortParamGet("cpssDxChPortLinkStatusGet",
                                     devNum, portNum, "link",
                                     "GT_BOOL")
```

**Key components:**
- `"IN"` / `"OUT"` / `"INOUT"` : Parameter direction
- `"GT_U8"`, `"GT_BOOL"`, etc. : C type names
- `"devNum"`, `"portNum"`, etc. : Parameter names
- `devNum`, `portNum` : Lua variable values

#### Step 3: Find C Function Declaration

**Search in XML API definitions:**
```bash
grep -r "cpssDxChPortLinkStatusGet" mainLuaWrapper/data/
```

**Output shows:**
```xml
<Function>
    <Declaration>GT_STATUS cpssDxChPortLinkStatusGet</Declaration>
    <Params>
        <Param>
            <Name>devNum</Name>
            <Type>GT_U8</Type>
            <Direction>IN</Direction>
        </Param>
        <Param>
            <Name>portNum</Name>
            <Type>GT_PHYSICAL_PORT_NUM</Type>
            <Direction>IN</Direction>
        </Param>
        <Param>
            <Name>isLinkUpPtr</Name>
            <Type>GT_BOOL</Type>
            <Direction>OUT</Direction>
        </Param>
    </Params>
</Function>
```

#### Step 4: Understand Data Flow

**Reading show_interfaces_status.lua:**

1. **Initialization:**
```lua
local command_data = Command_Data()  -- Helper object
command_data:initAllInterfacesPortIterator(params)
```

2. **Main Loop:**
```lua
for iterator, devNum, portNum in command_data:getPortIterator() do
    -- For each port on each device
end
```

3. **Get Port Info:**
```lua
-- Get interface mode
result, values = cpssPerPortParamGet("cpssDxChPortInterfaceModeGet", ...)
port_interface_mode = interfaceStrGet(values["mode"])

-- Get link status
result, values = cpssPerPortParamGet("cpssDxChPortLinkStatusGet", ...)
port_link = values["link"]

-- Get speed
result, values = cpssPerPortParamGet("cpssDxChPortSpeedGet", ...)
port_speed = portSpeedStrGet(values["speed"])
```

4. **Format and Print:**
```lua
command_data["result"] = string.format("%-10s %-8s %-6s %-6s %-7s ...",
    devNum .. "/" .. portNum,
    port_interface_mode_string,
    port_link_string,
    port_speed_string,
    ...
)
```

### Methodology: Bottom-Up Approach (For Understanding Extensions)

#### Step 1: Look at Extension Code

```bash
cd ~/sourcecode/marvell-cpss-extension/extension
ls -la
```

**Example: SERDES Extension**
```bash
find extension/serdes -name "*.c" -o -name "*.h"
```

#### Step 2: Find How Extension is Called

**Search for function names in Lua scripts:**
```bash
grep -r "serdes" lua_cli/scripts/dxCh/interface/
```

#### Step 3: Trace Back to User Command

**Find which command uses this:**
```bash
grep -r "serdes" lua_cli/scripts/dxCh/exec/
```

---

## Validating Code with Lua CLI

### Method 1: Using cpss-api Commands

#### Get Function Documentation
```
Console# cpss-api man cpssDxChPortLinkStatusGet
```

**Output shows:**
- Function purpose
- Parameters (IN/OUT)
- Return values
- Applicable devices

#### Search for Functions
```
Console# cpss-api search port
```

**Returns list of all port-related functions**

#### Call Functions Directly
```
Console# cpss-api call cpssDxChPortLinkStatusGet devNum 0 portNum 6
```

**Example output:**
```
Command: cpssDxChPortLinkStatusGet
Parameters:
  devNum: 0
  portNum: 6
Returns:
  rc: 0 (GT_OK)
  isLinkUpPtr: true
```

### Method 2: Interactive Lua Code Execution

#### Using shell-execute for Custom Lua Functions

**First, add a custom Lua function via JSON:**
```
Console# execJsonAddCustomFunc
```

**Input (compressed JSON):**
```json
{
  "name": "testPortLink",
  "src": "function(dev, port) local ret, val = myGenWrapper('cpssDxChPortLinkStatusGet', {{'IN','GT_U8','devNum',dev},{'IN','GT_PHYSICAL_PORT_NUM','portNum',port},{'OUT','GT_BOOL','link'}}) return val.link end"
}
```

**Then call it:**
```
Console# execJsonCallCustomFunc
```

**Input:**
```json
{
  "name": "testPortLink",
  "params": [0, 6]
}
```

### Method 3: Loading and Running Test Scripts

#### Create Test Script on Device

**On UDM-Beast Linux shell:**
```bash
cat > /tmp/test_ports.lua << 'EOF'
-- Test script to validate port functions

function testAllPorts()
    local devNum = 0

    for portNum = 0, 11 do
        -- Get link status
        local ret, val = myGenWrapper("cpssDxChPortLinkStatusGet", {
            {"IN", "GT_U8", "devNum", devNum},
            {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
            {"OUT", "GT_BOOL", "link"}
        })

        if ret == 0 then
            print(string.format("Port %d/%d: Link %s",
                devNum, portNum,
                val.link and "UP" or "DOWN"))
        else
            print(string.format("Port %d/%d: Error %d",
                devNum, portNum, ret))
        end
    end
end

-- Run the test
testAllPorts()
EOF
```

#### Load Script in Lua CLI
```
Console# load /tmp/test_ports.lua
```

### Method 4: Step-by-Step Validation

#### Example: Validating a New Port Configuration Function

**Scenario:** You added a new function to configure port LED

#### 1. Check Function Exists in CPSS
```
Console# cpss-api search PortLed
```

**Look for your function:**
```
cpssDxChLedStreamPortPositionSet
cpssDxChPortLedInterfaceGet
... (your new function should appear here)
```

#### 2. Get Function Documentation
```
Console# cpss-api man cpssDxChPortLedInterfaceGet
```

**Verify:**
- Parameters match your understanding
- Return type is correct
- Applicable devices include yours

#### 3. Test Function Directly
```
Console# cpss-api call cpssDxChPortLedInterfaceGet devNum 0 portNum 6
```

**Check:**
- Return code (0 = GT_OK)
- Output values make sense

#### 4. Create Lua Test Function

```lua
-- In Lua CLI or via execJsonAddCustomFunc

function testLedConfig(dev, port, ledInterface)
    -- Set LED interface
    local ret1 = myGenWrapper("cpssDxChPortLedInterfaceSet", {
        {"IN", "GT_U8", "devNum", dev},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", port},
        {"IN", "GT_U32", "ledInterfaceNum", ledInterface}
    })

    if ret1 ~= 0 then
        print("Set failed:", ret1)
        return false
    end

    -- Verify by reading back
    local ret2, val = myGenWrapper("cpssDxChPortLedInterfaceGet", {
        {"IN", "GT_U8", "devNum", dev},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", port},
        {"OUT", "GT_U32", "ledInterfaceNum"}
    })

    if ret2 ~= 0 then
        print("Get failed:", ret2)
        return false
    end

    if val.ledInterfaceNum == ledInterface then
        print("SUCCESS: LED interface set to", ledInterface)
        return true
    else
        print("FAIL: Expected", ledInterface, "got", val.ledInterfaceNum)
        return false
    end
end

-- Run test
testLedConfig(0, 6, 1)
```

#### 5. Add to CLI Command (Optional)

**Create file:** `lua_cli/scripts/dxCh/configuration/led_interface.lua`

```lua
local function port_led_interface(params)
    local devNum = params.devID
    local portNum = params.portNum
    local ledIf = params.ledInterface

    local ret = myGenWrapper("cpssDxChPortLedInterfaceSet", {
        {"IN", "GT_U8", "devNum", devNum},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
        {"IN", "GT_U32", "ledInterfaceNum", ledIf}
    })

    if ret ~= 0 then
        print("Error setting LED interface:", returnCodes[ret])
        return false
    end

    return true
end

-- Register command
CLI_addCommand("interface", "led interface", {
    func = port_led_interface,
    help = "Set LED interface number",
    params = {
        { type = "values",
          "%ledInterface"  -- Type defined in cli_types
        }
    }
})
```

---

## Practical Examples

### Example 1: Reading and Validating Port Speed Configuration

#### A. Read the Source Code

**File:** `lua_cli/scripts/dxCh/interface/speed.lua`

**Key function:**
```lua
local function port_speed_func(params)
    ...
    -- Set port speed
    result = myGenWrapper("cpssDxChPortSpeedAutoDetectAndConfig", {
        {"IN", "GT_U8", "devNum", devNum},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
        {"IN", "CPSS_PORT_SPEED_ENT", "speed", params.speedType}
    })
    ...
end
```

#### B. Validate with Lua CLI

```
Console# configure
Console(config)# interface ethernet 0/6
Console(config-if)# speed 10000
```

**Or test directly:**
```
Console# cpss-api call cpssDxChPortSpeedGet devNum 0 portNum 6
```

#### C. Write Validation Script

```lua
function validatePortSpeed(dev, port, expectedSpeed)
    local ret, val = myGenWrapper("cpssDxChPortSpeedGet", {
        {"IN", "GT_U8", "devNum", dev},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", port},
        {"OUT", "CPSS_PORT_SPEED_ENT", "speed"}
    })

    if ret == 0 and val.speed == expectedSpeed then
        print("PASS: Port speed is", expectedSpeed)
        return true
    else
        print("FAIL: Expected", expectedSpeed, "got", val.speed)
        return false
    end
end

-- Test port 6 should be 10G
validatePortSpeed(0, 6, "CPSS_PORT_SPEED_10000_E")
```

### Example 2: Understanding myGenWrapper Parameters

#### Anatomy of a myGenWrapper Call

```lua
result, values = myGenWrapper("cpssDxChPortFecModeGet", {
    {"IN",  "GT_U8",                     "devNum",  devNum},
    {"IN",  "GT_PHYSICAL_PORT_NUM",      "portNum", portNum},
    {"OUT", "CPSS_DXCH_PORT_FEC_MODE_ENT", "mode"}
})
```

**Parameter Table Structure:**
```lua
{
    {direction, type, name, value},  -- First parameter
    {direction, type, name, value},  -- Second parameter
    ...
}
```

**Components:**
- **direction**: `"IN"`, `"OUT"`, or `"INOUT"`
- **type**: C type string (e.g., `"GT_U8"`, `"GT_BOOL"`, enum name)
- **name**: Parameter name (matches C function declaration)
- **value**: Lua value (for IN parameters only, omit for OUT)

**Return Values:**
- **result**: Return code (0 = GT_OK, see `returnCodes` table)
- **values**: Table containing OUT parameter values, indexed by name

**Example:**
```lua
if result == 0 then  -- GT_OK
    local fecMode = values["mode"]
    print("FEC Mode:", fecMode)
end
```

### Example 3: Debugging with Print Statements

#### Add Debug Prints to Lua Scripts

```lua
function debugPortInfo(dev, port)
    print("=== Port Debug Info ===")
    print("Device:", dev, "Port:", port)

    -- Get link status
    local ret, val = myGenWrapper("cpssDxChPortLinkStatusGet", {
        {"IN", "GT_U8", "devNum", dev},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", port},
        {"OUT", "GT_BOOL", "link"}
    })
    print("Link Status: ret=", ret, "link=", val and val.link or "N/A")

    -- Get interface mode
    ret, val = myGenWrapper("cpssDxChPortInterfaceModeGet", {
        {"IN", "GT_U8", "devNum", dev},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", port},
        {"OUT", "CPSS_PORT_INTERFACE_MODE_ENT", "mode"}
    })
    print("Interface Mode: ret=", ret, "mode=", val and val.mode or "N/A")

    -- Get speed
    ret, val = myGenWrapper("cpssDxChPortSpeedGet", {
        {"IN", "GT_U8", "devNum", dev},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", port},
        {"OUT", "CPSS_PORT_SPEED_ENT", "speed"}
    })
    print("Speed: ret=", ret, "speed=", val and val.speed or "N/A")

    print("======================")
end

-- Run debug
debugPortInfo(0, 6)
```

---

## Complete Validation Workflow

### Scenario: Adding a New VLAN Feature

#### 1. Identify CPSS APIs Needed
```bash
# On development machine
cd ~/sourcecode/marvell-cpss-extension
grep -r "vlan" mainLuaWrapper/data/dxCh_xml/cpssAPI.xml | grep -i "function_you_need"
```

#### 2. Check if Lua Wrapper Exists
```bash
grep -r "cpssDxChBrgVlanYourFunction" lua_cli/scripts/
```

#### 3. Test API Directly
```
Console# cpss-api man cpssDxChBrgVlanYourFunction
Console# cpss-api call cpssDxChBrgVlanYourFunction devNum 0 ...
```

#### 4. Create Lua Test Script
```lua
function testVlanFeature()
    -- Your test code
    -- Call CPSS API via myGenWrapper
    -- Verify results
end
```

#### 5. Add to CLI (if needed)
```lua
-- Create configuration script
-- Register command with CLI_addCommand
```

#### 6. Build and Deploy
```bash
# Build cpss-app with your changes
make

# Deploy to device
scp cpss-app root@device:/root/
```

#### 7. Test on Device
```
Console# [your new command]
```

---

## Debugging Tips

### Common Issues and Solutions

#### Issue: Function Not Found
```
Error: function doesn't exists
```

**Solution:**
1. Check function name spelling
2. Verify function is in XML API definition
3. Check if device family matches (DxCh vs PX)

#### Issue: Wrong Parameter Type
```
Error: parameter type mismatch
```

**Solution:**
1. Check C function signature in XML
2. Verify parameter directions (IN/OUT)
3. Ensure type strings match exactly

#### Issue: Return Code Not GT_OK
```
ret = 4  # GT_NOT_INITIALIZED
```

**Solution:**
1. Check `returnCodes` table for meaning
2. Verify system is initialized (`cpssInitSystem`)
3. Check if port/device exists

### Enable Trace Logging

```
Console# cpss-api mode
```

**Set verbose output mode to see:**
- Function calls
- Parameter values
- Return codes
- Execution time

---

## Summary

### Reading marvell-cpss-extension Code:
1. **Start with Lua scripts** in `lua_cli/scripts/dxCh/`
2. **Find myGenWrapper calls** to see which CPSS APIs are used
3. **Check XML definitions** in `mainLuaWrapper/data/dxCh_xml/cpssAPI.xml`
4. **Trace to C code** if you need to understand implementation

### Validating with Lua CLI:
1. **Use cpss-api** commands for quick API testing
2. **Write Lua test functions** for complex validation
3. **Create test scripts** for regression testing
4. **Add CLI commands** for permanent features

### Key Files to Remember:
- `lua_cli/scripts/common/misc/myGenWrapper.lua` - Lua-to-C bridge
- `lua_cli/scripts/dxCh/exec/show_interfaces_status.lua` - Example command
- `mainLuaWrapper/data/dxCh_xml/cpssAPI.xml` - API definitions

---

*Document created through deep exploration of UDM-Beast and marvell-cpss-extension source code*
*Last updated: 2026-01-30*
