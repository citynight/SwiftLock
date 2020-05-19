//
//  SwiftLockTests.swift
//  SwiftLockTests
//
//  Created by 李小争 on 2020/5/19.
//  Copyright © 2020 Logan. All rights reserved.
//

import XCTest
@testable import SwiftLock

class SwiftLockTests: XCTestCase {
    
    // Unsafe in iOS, may cause priority inversion
    // But fastest
    func testSpinLock() {
        // Time: 0.238 sec
        var spinLock = OS_SPINLOCK_INIT
        executeLockTest { (block) in
            OSSpinLockLock(&spinLock)
            block()
            OSSpinLockUnlock(&spinLock)
        }
    }
    
    // iOS 10 only, fixed variant of spinlock. Not actually spins, but waits in the kernel
    // Maybe be reacquired before woken up waiter gets an opportunity to attempt to acquire the lock
    func testUnfairLock() {
        // Time: 0.401 sec
        var unfairLock = os_unfair_lock_s()
        executeLockTest { (block) in
            os_unfair_lock_lock(&unfairLock)
            block()
            os_unfair_lock_unlock(&unfairLock)
        }
    }
    
    // Fastest after spinlock and unfair_lock
    // May cause priority inversion on iOS 9, probably safe in iOS 10
    func testDispatchSemaphore() {
        // Time: 0.775 sec
        let sem = DispatchSemaphore(value: 1)
        executeLockTest { (block) in
            _ = sem.wait(timeout: DispatchTime.distantFuture)
            block()
            sem.signal()
        }
    }
    
    func testNSLock() {
        // Time: 0.498 sec
        let lock = NSLock()
        executeLockTest { (block) in
            lock.lock()
            block()
            lock.unlock()
        }
    }
    
    func testPthreadMutex() {
        // Time: 0.493 sec
        var mutex = pthread_mutex_t()
        pthread_mutex_init(&mutex, nil)
        executeLockTest{ (block) in
            pthread_mutex_lock(&mutex)
            block()
            pthread_mutex_unlock(&mutex)
        }
        pthread_mutex_destroy(&mutex);
    }
    
    // Obj-c analogue is @synchronized
    // Almost the same as pthread_mutex, but slower.
    // Best for inline usage in non performant places (because you don't need to initialize it before)
    func testSynchronized() {
        // Time: 0.441 sec
        let obj = NSObject()
        executeLockTest{ (block) in
            objc_sync_enter(obj)
            block()
            objc_sync_exit(obj)
        }
    }
    
    func testQueue() {
        // Time: 0.868 sec
        let lockQueue = DispatchQueue.init(label: "com.test.LockQueue")
        executeLockTest{ (block) in
            lockQueue.sync() {
                block()
            }
        }
    }
    
    // Enable this test to ensure work will fail
    func disable_testNoLock() {
        executeLockTest { (block) in
            block()
        }
    }
    private func executeLockTest(performBlock:@escaping (_ block:() -> Void) -> Void) {
        let dispatchBlockCount = 16
        let iterationCountPerBlock = 10_000
        // This is an example of a performance test case.
        let queues = [
            DispatchQueue.global(qos: DispatchQoS.QoSClass.userInteractive),
            DispatchQueue.global(qos: DispatchQoS.QoSClass.default),
            DispatchQueue.global(qos: DispatchQoS.QoSClass.utility),
            ]
        let array = NSMutableArray.init()
        self.measure {
            let group = DispatchGroup.init()
            for block in 0..<dispatchBlockCount {
                group.enter()
                let queue = queues[block % queues.count]
                queue.async(execute: {
                    for _ in 0..<iterationCountPerBlock {
                        performBlock({
                            array.addObjects(from: [1,2]);
                            array.removeObject(at: 1)
                        })
                    }
                    group.leave()
                })
            }
            _ = group.wait(timeout: DispatchTime.distantFuture)
        }
    }
}
