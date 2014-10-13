//
//  Client.swift
//  Jetstream
//
//  Created by Rob Skillington on 9/24/14.
//  Copyright (c) 2014 Uber Technologies, Inc. All rights reserved.
//

import Foundation
import Signals

let clientVersion = "0.1.0"
let defaultErrorDomain = "com.uber.jetstream"

public enum ClientStatus {
    case Offline
    case Online
}

public class Client {
    
    let logger = Logging.loggerFor("Client")
    
    /// MARK: Events
    
    public let onStatusChanged = Signal<(ClientStatus)>()
    public let onSession = Signal<(Session)>()
    public let onSessionDenied = Signal<(Void)>()

    /// MARK: Properties
    
    public private(set) var status: ClientStatus = .Offline {
        didSet {
            onStatusChanged.fire(status)
        }
    }
    
    public private(set) var session: Session? {
        didSet {
            if session != nil {
                onSession.fire(session!)
            }
        }
    }
    
    let transport: Transport
    var scopes = [UInt: Scope]()
    
    /// MARK: Public interface
    
    public init(options: ConnectionOptions) {
        var defaultAdapter = Transport.defaultTransportAdapter(options)
        transport = Transport(adapter: defaultAdapter)
        bindListeners()
    }
    
    public init(options: MQTTLongPollChunkedConnectionOptions) {
        var adapter = MQTTLongPollChunkedTransportAdapter(options: options)
        transport = Transport(adapter: adapter)
        bindListeners()
    }
    
    public func connect() {
        transport.connect()
    }
    
    public func close() {
        // TODO: close up any resources
    }
    
    /// MARK: Private interface
    
    func bindListeners() {
        onStatusChanged.listen(self) { [weak self] (status) in
            if let this = self {
                this.statusChanged(status)
            }
        }
        transport.onStatusChanged.listen(self) { [weak self] (status) in
            if let this = self {
                this.transportStatusChanged(status)
            }
        }
        transport.onMessage.listen(self) { [weak self] (message: Message) in
            asyncMain {
                if let this = self {
                    this.receivedMessage(message)
                }
            }
        }
    }
    
    func statusChanged(clientStatus: ClientStatus) {
        switch clientStatus {
        case .Online:
            logger.info("Online")
            if session == nil {
                sessionCreate()
            } else {
                sessionResume()
            }
        case .Offline:
            logger.info("Offline")
        }
    }
    
    func transportStatusChanged(transportStatus: TransportStatus) {
        switch transportStatus {
        case .Closed:
            status = .Offline
        case .Connecting:
            status = .Offline
        case .Connected:
            status = .Online
        }
    }
    
    func receivedMessage(message: Message) {
        switch message {
        case let sessionCreateResponse as SessionCreateResponseMessage:
            if session != nil {
                logger.error("Received session create response with existing session")
            } else if sessionCreateResponse.success == false {
                logger.info("Denied starting session")
                onSessionDenied.fire()
            } else {
                let token = sessionCreateResponse.sessionToken
                logger.info("Starting session with token: \(token)")
                session = Session(client: self, token: token)
            }
        case let scopeStateMessage as ScopeStateMessage:
            if let scope = scopes[scopeStateMessage.scopeIndex] {
                if let rootModel = scope.rootModel {
                    scope.startApplyingRemote()
                    scope.applyRootFragment(scopeStateMessage.rootFragment, additionalFragments: scopeStateMessage.syncFragments)
                    scope.endApplyingRemote()
                }
            }
        case let scopeSyncMessage as ScopeSyncMessage:
            if let scope = scopes[scopeSyncMessage.scopeIndex] {
                if let rootModel = scope.rootModel {
                    if scopeSyncMessage.syncFragments.count > 0 {
                        scope.startApplyingRemote()
                        scope.applySyncFragments(scopeSyncMessage.syncFragments)
                        scope.endApplyingRemote()
                    } else {
                        logger.error("Received sync message without fragments")
                    }
                }
            }
        case let replyMessage as ReplyMessage:
            // No-op
            break
        default:
            logger.debug("Unrecognized message received")
        }
    }
    
    private func sessionCreate() {
        transport.sendMessage(SessionCreateMessage())
    }
    
    func sessionResume() {
        // TODO: implement
    }
    
    func scopeFetch(scope: Scope, callback: (NSError?) -> ()) {
        transport.sendMessage(ScopeFetchMessage(session: session!, name: scope.name)) {
            [weak self] (response) in
            if let this = self {
                this.scopeFetchCompleted(scope, response: response, callback: callback)
            }
        }
    }
    
    func scopeFetchCompleted(scope: Scope, response: [String: AnyObject], callback: (NSError?) -> ()) {
        var result: Bool? = response.valueForKey("result")
        var scopeIndex: UInt? = response.valueForKey("scopeIndex")
        
        if result != nil && scopeIndex != nil && result! == true {
            attachScope(scope, scopeIndex: scopeIndex!)
            callback(nil)
        } else {
            var definiteErrorCode = 0
            
            var error: [String: AnyObject]? = response.valueForKey("error")
            var errorMessage: String? = error?.valueForKey("message")
            var errorCode: Int? = error?.valueForKey("code")
            
            if errorCode != nil {
                definiteErrorCode = errorCode!
            }
            
            var userInfo = [NSLocalizedDescriptionKey: "Fetch request failed"]
            
            if errorMessage != nil {
                userInfo[NSLocalizedFailureReasonErrorKey] = errorMessage!
            }
            
            callback(NSError(
                domain: defaultErrorDomain,
                code: definiteErrorCode,
                userInfo: userInfo))
        }
    }
    
    func attachScope(scope: Scope, scopeIndex: UInt = 1) {
        scopes[scopeIndex] = scope
        scope.onChanges.listen(self) {
            [weak self] (syncFragments) in
            if let this = self {
                this.scopeChanges(scope, atIndex: scopeIndex, syncFragments: syncFragments)
            }
        }
    }
    
    func scopeChanges(scope: Scope, atIndex: UInt, syncFragments: [SyncFragment]) {
        if session == nil {
            return
        }
        
        transport.sendMessage(ScopeSyncMessage(
            session: session!,
            scopeIndex: atIndex,
            syncFragments: syncFragments))
    }

}
