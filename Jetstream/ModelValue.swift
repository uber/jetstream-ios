//
//  ModelValue.swift
//  Jetstream
//
//  Created by Tuomas Artman on 10/7/14.
//  Copyright (c) 2014 Uber Technologies, Inc. All rights reserved.
//

import Foundation

protocol ModelValue {
    func equalTo(value: ModelValue) -> Bool
    func serialize() -> AnyObject
    class func unserialize(value: AnyObject, scope: Scope) -> AnyObject?
}

enum ModelValueType: String {
    case Int8 = "c"
    case UInt8 = "C"
    case Int16 = "s"
    case UInt16 = "S"
    case Int32 = "i"
    case UInt32 = "I"
    case Int = "q"
    case UInt = "Q"
    case Float = "f"
    case Double = "d"
    case Bool = "B"
    case Str = "@"
    case Date = "@\"NSDate\""
    case Color = "@\"UIColor\""
    case Array = "@a"
    case ModelObject = "@m"
}

func convertAnyObjectToModelValue(value: AnyObject, type: ModelValueType) -> ModelValue? {
    switch type {
    case .Int8: return value as? Int
    case .UInt8: return value as? Int
    case .Int16: return value as? Int
    case .UInt16: return value as? Int
    case .Int32: return value as? Int
    case .UInt32: return value as? Int
    case .Int: return value as? Int
    case .UInt: return value as? UInt
    case .Float: return value as? Float
    case .Double: return value as? Double
    case .Bool: return value as? Bool
    case .Str: return value as? String
    case .Date: return value as? NSDate
    case .Color: return value as? UIColor
    case .Array: return value as? [AnyObject]
    case .ModelObject: return value as? ModelObject
    }
}

// XCode 6.0 crashes when accessing modelValue.dynamicType.unserialize directly. We might be able to
// removed this wrapper once migrating to 6.1
func unserializeModelValue(value: AnyObject, scope: Scope, type: ModelValueType) -> AnyObject? {
    switch type {
    case .Int8: return Int8.unserialize(value, scope: scope)
    case .UInt8: return UInt8.unserialize(value, scope: scope)
    case .Int16: return Int16.unserialize(value, scope: scope)
    case .UInt16: return UInt16.unserialize(value, scope: scope)
    case .Int32: return Int32.unserialize(value, scope: scope)
    case .UInt32: return UInt32.unserialize(value, scope: scope)
    case .Int: return Int.unserialize(value, scope: scope)
    case .UInt: return UInt.unserialize(value, scope: scope)
    case .Float: return Float.unserialize(value, scope: scope)
    case .Double: return Double.unserialize(value, scope: scope)
    case .Bool: return Bool.unserialize(value, scope: scope)
    case .Str: return String.unserialize(value, scope: scope)
    case .Date: return NSDate.unserialize(value, scope: scope)
    case .Color: return UIColor.unserialize(value, scope: scope)
    case .Array: return Array<ModelObject>.unserialize(value, scope: scope)
    case .ModelObject: return ModelObject.unserialize(value, scope: scope)
    }
}

extension String: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as String }
    func serialize() -> AnyObject { return self }
    func unserailizeFromTransport() -> ModelValue { return self}
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as String}
}

extension UInt: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as UInt }
    func serialize() -> AnyObject { return self }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as UInt }
}

extension Int: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as Int }
    func serialize() -> AnyObject { return self }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Int }
}

extension UInt8: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as UInt8 }
    func serialize() -> AnyObject { return UInt(self) }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Int }
}

extension Int8: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as Int8 }
    func serialize() -> AnyObject { return Int(self) }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Int }
}

extension UInt16: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as UInt16 }
    func serialize() -> AnyObject { return UInt(self) }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Int }
}

extension Int16: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as Int16 }
    func serialize() -> AnyObject { return Int(self) }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Int }
}

extension UInt32: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as UInt32 }
    func serialize() -> AnyObject { return UInt(self) }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Int }
}

extension Int32: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as Int32 }
    func serialize() -> AnyObject { return Int(self) }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Int }
}

extension Float: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as Float }
    func serialize() -> AnyObject { return self }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Float}
}

extension Double: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as Double }
    func serialize() -> AnyObject { return self }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Double }
}

extension Bool: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as Bool }
    func serialize() -> AnyObject { return self }
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? { return value as Bool }
}

extension UIColor: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as UIColor }
    
    func serialize() -> AnyObject {
        var comp: [CGFloat] = Array(count: 4, repeatedValue: 0);
        self.getRed(&comp[0], green: &comp[1], blue: &comp[2], alpha: &comp[3])
        
        var red = UInt32(comp[0] * 255) << 24
        var green = UInt32(comp[1] * 255) << 16
        var blue = UInt32(comp[2] * 255) << 8
        var alpha = UInt32(comp[3] * 255)
        
        var color: UInt32 = red | green | blue | alpha
        return UInt(color)
    }
    
    class func unserialize(value: AnyObject, scope: Scope) -> AnyObject? {
        if let color = value as? UInt {
            var red = CGFloat((color & 0xFF000000) >> 24) / 255.0
            var green = CGFloat((color & 0xFF0000) >> 16) / 255.0
            var blue = CGFloat((color & 0xFF00) >> 8) / 255.0
            var alpha = CGFloat(color & 0xFF) / 255.0
            
            return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        return nil
    }
}

extension NSDate: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self.timeIntervalSinceDate(value as NSDate) == 0 }
    func serialize() -> AnyObject { return self.timeIntervalSince1970 }
    
    class func unserialize(value: AnyObject, scope: Scope) -> AnyObject? {
        if let timeInterval = value as? NSTimeInterval {
            return NSDate(timeIntervalSince1970: timeInterval)
        }
        return nil
    }
}

extension Array: ModelValue {
    func equalTo(value: ModelValue) -> Bool {
        if let newContent = value as? [AnyObject] {
            if self.count != newContent.count {
                return false
            }
            for i in 0..<self.count {
                if self[i] as ModelObject !== newContent[i] {
                    return false
                }
            }
            return true
        }
        return false
    }
    
    func serialize() -> AnyObject {
        var serialized = [String]()
        for i in 0..<self.count {
            if let modelObject = self[i] as? ModelObject {
                serialized.append(modelObject.uuid.UUIDString)
            }
        }
        return serialized
    }
    
    static func unserialize(value: AnyObject, scope: Scope) -> AnyObject? {
        var models = [ModelObject]()
        if let uuids = value as? [String] {
            for uuid in uuids {
                if let modelObject = scope.getObjectById(NSUUID(UUIDString: uuid)) {
                    models.append(modelObject)
                }
            }
        }
        return models
    }
}

extension ModelObject: ModelValue {
    func equalTo(value: ModelValue) -> Bool { return self == value as ModelObject }
    
    func serialize() -> AnyObject { return self.uuid.UUIDString }
    
    class func unserialize(value: AnyObject, scope: Scope) -> AnyObject? {
        if let uuid = value as? String {
            return scope.getObjectById(NSUUID(UUIDString: uuid))
        }
        return nil
    }
}

