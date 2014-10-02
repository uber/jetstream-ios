//
//  ScopeFetchMessage.swift
//  Jetstream
//
//  Created by Rob Skillington on 9/26/14.
//  Copyright (c) 2014 Uber. All rights reserved.
//

import Foundation

class ScopeFetchMessage: IndexedMessage {
    
    class var messageType: String {
        get { return "ScopeFetch" }
    }
    
    override var type: String {
        get { return ScopeFetchMessage.messageType }
    }
    
    let name: String
    let params: [String: AnyObject]
    
    convenience init(session: Session, name: String) {
        self.init(index: session.getIndexForMessage(), name: name, params: [String: AnyObject]())
    }
    
    convenience init(session: Session, name: String, params: [String: AnyObject]) {
        self.init(index: session.getIndexForMessage(), name: name, params: params)
    }
    
    init(index: UInt, name: String, params: [String: AnyObject]) {
        self.name = name
        self.params = params
        super.init(index: index)
    }
    
    override func serialize() -> [String: AnyObject] {
        var dictionary = super.serialize()
        dictionary["name"] = name
        dictionary["params"] = params
        return dictionary
    }
    
}
