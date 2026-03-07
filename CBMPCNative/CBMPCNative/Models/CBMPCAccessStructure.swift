import Foundation

/// Node types matching CBMPC_AC_NODE_* constants
enum CBMPCACNodeType: Int32 {
    case and_ = 0
    case or_ = 1
    case threshold = 2
    case leaf = 3
}

/// Wrapper for access structure node
class CBMPCACNode {
    let nodePtr: UnsafeMutablePointer<cbmpc_ac_node_t>

    init(type: CBMPCACNodeType, name: String, threshold: Int = 0) {
        nodePtr = cbmpc_ac_node_new(type.rawValue, name, Int32(threshold))
    }

    func addChild(_ child: CBMPCACNode) {
        cbmpc_ac_node_add_child(nodePtr, child.nodePtr)
    }

    // Note: nodes are owned by the access structure tree after creation
    // Do NOT free them individually - they are freed when the AC is freed
}

/// Wrapper for access structure
class CBMPCAccessStructure {
    private var acPtr: UnsafeMutablePointer<cbmpc_ac_t>?

    init(root: CBMPCACNode, curveCode: Int) {
        let curve = cbmpc_curve_new(Int32(curveCode))
        acPtr = cbmpc_ac_new(root.nodePtr, curve)
        // curve is consumed by the AC, but we should still free it
        // Actually, the AC copies what it needs, so free the curve ref
        if let c = curve { cbmpc_curve_free(c) }
    }

    var cAC: UnsafeMutablePointer<cbmpc_ac_t>? { acPtr }

    deinit {
        if let ptr = acPtr {
            cbmpc_ac_free(ptr)
        }
    }
}

/// Wrapper for party set
class CBMPCPartySet {
    private var setPtr: UnsafeMutablePointer<cbmpc_party_set_t>?

    init() {
        setPtr = cbmpc_party_set_new()
    }

    func add(partyIndex: Int) {
        guard let ptr = setPtr else { return }
        cbmpc_party_set_add(ptr, Int32(partyIndex))
    }

    var cSet: UnsafeMutablePointer<cbmpc_party_set_t>? { setPtr }

    deinit {
        if let ptr = setPtr {
            cbmpc_party_set_free(ptr)
        }
    }
}

/// Wrapper for curve
class CBMPCCurve {
    private var curvePtr: UnsafeMutablePointer<cbmpc_curve_t>?

    init(curveCode: Int) {
        curvePtr = cbmpc_curve_new(Int32(curveCode))
    }

    var cCurve: UnsafeMutablePointer<cbmpc_curve_t>? { curvePtr }

    deinit {
        if let ptr = curvePtr {
            cbmpc_curve_free(ptr)
        }
    }
}
