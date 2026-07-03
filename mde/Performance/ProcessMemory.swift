//
//  ProcessMemory.swift
//  MDE
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum ProcessMemory {
    /// Resident memory size of the current process in bytes.
    static func residentBytes() -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
        #else
        return 0
        #endif
    }

    static func residentMegabytes() -> Double {
        Double(residentBytes()) / (1_024 * 1_024)
    }
}
