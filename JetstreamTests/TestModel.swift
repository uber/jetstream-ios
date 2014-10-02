//
//  TestModel.swift
//  Jetstream
//
//  Created by Tuomas Artman on 9/18/14.
//  Copyright (c) 2014 Uber Technologies, Inc. All rights reserved.
//

import Foundation

@objc public class TestModel: ModelObject {
    dynamic var string: String?
    dynamic var integer = 0
    dynamic var float = 0
    dynamic var array: [TestModel] = []
    dynamic var anotherArray: [AnotherTestModel] = []
    dynamic var nsArray = NSMutableArray()
    dynamic var childModel: TestModel?
    dynamic var childModel2: TestModel?
    
    dynamic var compositeProperty: String {
        get {
            return "\(float) \(anotherArray.count)"
        }
    }
    
    override public class func getCompositeDependencies() -> [String: [String]] {
        return ["compositeProperty": ["float", "anotherArray"]]
    }
}

@objc public class AnotherTestModel: ModelObject {
    dynamic var anotherString: String? = ""
    dynamic var anotherInteger: Int = 0
    
    dynamic var anotherCompositeProperty: String {
        get {
            return "\(anotherString) \(anotherInteger)"
        }
    }
    
    override public class func getCompositeDependencies() -> [String: [String]] {
        return ["anotherCompositeProperty": ["anotherString", "anotherInteger"]]
    }
}