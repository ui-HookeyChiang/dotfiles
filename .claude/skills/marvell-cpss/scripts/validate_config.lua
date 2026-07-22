-- Marvell CPSS Configuration Validation Script
-- This script validates various CPSS configurations

function validatePortChannel(trunkId)
    print("=== Validating Port-Channel", trunkId, "===")

    local ret, val = myGenWrapper("cpssDxChTrunkTableEntryGet", {
        {"IN",  "GT_U8", "devNum", 0},
        {"IN",  "GT_TRUNK_ID", "trunkId", trunkId},
        {"OUT", "GT_U32", "numOfEnabledMembersPtr"},
        {"OUT", "CPSS_TRUNK_MEMBER_STC", "enabledMembersArray", 12}
    })

    if ret == 0 then
        print(string.format("✓ PASS - Trunk %d has %d members",
            trunkId, val.numOfEnabledMembersPtr))
        for i = 0, val.numOfEnabledMembersPtr - 1 do
            print(string.format("  Member: Port %d/%d",
                val.enabledMembersArray[i].hwDevice,
                val.enabledMembersArray[i].port))
        end
        return true
    else
        print("✗ FAIL - Trunk not configured")
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
        print("✓ PASS - VLAN exists")
        return true
    else
        print("✗ FAIL - VLAN not found")
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
        print("✓ PASS - Rule configured")
        print("  Action:", val.action.pktCmd)
        return true
    else
        print("✗ FAIL - Rule not found")
        return false
    end
end

function validatePortStatus(devNum, portNum)
    print(string.format("=== Validating Port %d/%d ===", devNum, portNum))

    -- Check link status
    local ret, val = myGenWrapper("cpssDxChPortLinkStatusGet", {
        {"IN", "GT_U8", "devNum", devNum},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
        {"OUT", "GT_BOOL", "isLinkUp"}
    })

    if ret == 0 then
        print(string.format("  Link: %s", val.isLinkUp and "UP" or "DOWN"))
    end

    -- Check speed
    ret, val = myGenWrapper("cpssDxChPortSpeedGet", {
        {"IN", "GT_U8", "devNum", devNum},
        {"IN", "GT_PHYSICAL_PORT_NUM", "portNum", portNum},
        {"OUT", "CPSS_PORT_SPEED_ENT", "speed"}
    })

    if ret == 0 then
        print("  Speed:", val.speed)
    end

    return ret == 0
end

-- Main validation function
function runAllValidations()
    print("\n" .. string.rep("=", 60))
    print("MARVELL CPSS CONFIGURATION VALIDATION")
    print(string.rep("=", 60))

    local results = {}

    -- Add your validations here
    -- Example: table.insert(results, validatePortChannel(20))
    -- Example: table.insert(results, validateVlan(100))

    print("\n" .. string.rep("=", 60))
    print("VALIDATION SUMMARY")
    print(string.rep("=", 60))

    local pass_count = 0
    for _, result in ipairs(results) do
        if result then pass_count = pass_count + 1 end
    end

    print(string.format("Total: %d  Passed: %d  Failed: %d",
        #results, pass_count, #results - pass_count))
end

-- Export functions for use
return {
    validatePortChannel = validatePortChannel,
    validateVlan = validateVlan,
    validateACL = validateACL,
    validatePortStatus = validatePortStatus,
    runAll = runAllValidations
}
