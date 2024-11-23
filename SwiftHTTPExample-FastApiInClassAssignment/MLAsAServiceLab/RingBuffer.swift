//
//  RingBuffer.swift
//  HTTPSwiftExample
//
//  Created by Eric Larson on 10/27/17.
//  Copyright © 2017 Eric Larson. All rights reserved.
//

import UIKit

let BUFFER_SIZE = 50  //the size of the circular buffer for storing data.

//implement a ring (or circular) buffer structure that stores data in arrays.
class RingBuffer: NSObject {

    private var images = [UIImage?](repeating: nil, count: BUFFER_SIZE)  // Array to hold image references (can hold either UIImage objects or strings representing image paths)
    
    // used to keep track of the current position where the next data will be inserted into the buffer.
    private var head:Int = 0 {
        
        // monitor changes to head
        didSet{
            
            //if head exceeds the buffer size, reset it to 0 to overwrite the old data once it reaches its capacity
            if(head >= BUFFER_SIZE){
                head = 0
            }
        }
    }
    
    // Serial queue to ensure thread safety
    private let queue = DispatchQueue(label: "com.example.ringbuffer.queue")
    
    
    // Add new image to the buffer. Also ensuring thread safety
    func addNewImage(image: UIImage) {
        queue.sync {
            images[head] = image
            head += 1  // Move the head pointer to the next position
        }
    }
    
    // Return all images in the buffer as an array
    func getImages() -> [UIImage?] {
        var allImages = [UIImage?](repeating: nil, count: BUFFER_SIZE)  // Hold all images
        
        // Iterate over each buffer position
        for i in 0..<BUFFER_SIZE {
            let idx = (head + i) % BUFFER_SIZE  // Ensure that buffer behaves circularly
            allImages[i] = images[idx]  // Store image references in the array
        }
        return allImages  // Return the combined array of images
    }
}

