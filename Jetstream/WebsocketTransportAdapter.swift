//
//  WebsocketTransportAdapter.swift
//  Jetstream
//
//  Copyright (c) 2014 Uber Technologies, Inc.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import SystemConfiguration

/// A set of connection options.
public struct WebSocketConnectionOptions: ConnectionOptions {
    /// Headers to connect with
    public var url: NSURL
    
    /// A dictionary of key-value pairs to send as headers when connecting.
    public var headers: [String: String]
    
    public init(url: NSURL, headers: [String: String] = [String: String]()) {
        self.url = url
        self.headers = headers
    }
}

enum WebSocketTransportAdapterErrorCode: Int {
    case DeniedConnection = 4096
    case ClosedConnection = 4097
}

/// A transport adapter that connects to the the jetstream service via a persistent Websocket.
public class WebSocketTransportAdapter: NSObject, TransportAdapter, WebSocketDelegate {
    struct Static {
        static let className = "WebsocketTransportAdapter"
        static let inactivityPingIntervalSeconds: NSTimeInterval = 10
        static let inactivityPingIntervalVarianceSeconds: NSTimeInterval = 2
        static let fatalErrorCodes = [
            WebSocketTransportAdapterErrorCode.DeniedConnection.rawValue,
            WebSocketTransportAdapterErrorCode.ClosedConnection.rawValue
        ]
    }
    
    public let onStatusChanged = Signal<(TransportStatus)>()
    public let onMessage = Signal<(NetworkMessage)>()
    public let adapterName = Static.className
    public let options: ConnectionOptions
    let websocketOptions: WebSocketConnectionOptions
    
    public internal(set) var status: TransportStatus = .Closed {
        didSet {
            onStatusChanged.fire(status)
        }
    }

    let logger = Logging.loggerFor(Static.className)
    var socket: WebSocket
    var explicitlyClosed = false
    var session: Session?
    var pingTimer: NSTimer?
    var nonAckedSends = [NetworkMessage]()

    /// Constructor.
    ///
    /// - parameter options: Options to connect to the service with.
    public init(options: WebSocketConnectionOptions ) {
        self.options = options
        websocketOptions = options
        socket = WebSocket(url: options.url)
        super.init()
        socket.delegate = self
        for (key, value) in options.headers {
            socket.headers[key] = value
        }
    }

    // MARK: - TransportAdapter
    public func connect() {
        if status == TransportStatus.Connecting {
            return
        }
        status = .Connecting
        tryConnect()
    }
    
    public func disconnect() {
        if status == .Closed {
            return
        }
        explicitlyClosed = true
        session = nil
        stopPingTimer()
        socket.disconnect()
    }
    
    public func reconnect() {
        if status != .Connected {
            return
        }
        stopPingTimer()
        socket.disconnect()
    }
    
    public func sendMessage(message: NetworkMessage) {
        if session != nil {
            nonAckedSends.append(message)
        }
        transportMessage(message)
    }
    
    public func sessionEstablished(session: Session) {
        self.session = session
        startPingTimer()
    }
    
    // MARK: - WebsocketDelegate
    public func websocketDidConnect(socket: WebSocket) {
        status = .Connected
        if session != nil {
            // Request missed messages
            sendMessage(PingMessage(session: session!, resendMissing: true))
            // Restart the ping timer lost after disconnecting
            startPingTimer()
        }
    }
    
    public func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        // Starscream sometimes dispatches this on another thread
        dispatch_async(dispatch_get_main_queue()) {
            if let definiteError = error {
                self.didReceiveWebsocketError(definiteError)
            }
            self.didDisconnect()
        }
    }
    
    func didReceiveWebsocketError(error: NSError) {
        if error.domain == "Websocket" && Static.fatalErrorCodes.contains(error.code) {
            // Declare as fatal and close everything up
            explicitlyClosed = true
            socket.delegate = nil
            status = .Fatal
        }
    }
    
    func didDisconnect() {
        stopPingTimer()
        if status == TransportStatus.Connecting {
            status = .Closed
        }
        if !explicitlyClosed {
            resetSocket()
            connect()
        }
    }
    
    func resetSocket() {
        socket.delegate = nil
        
        socket = WebSocket(url: options.url)
        socket.delegate = self
        for (key, value) in websocketOptions.headers {
            socket.headers[key] = value
        }
        if let definiteSession = session {
            socket.headers["X-Jetstream-SessionToken"] = definiteSession.token
        }
    }
    
    public func websocketDidWriteError(socket: WebSocket, error: NSError?) {
        if let _ = error {
            // Starscream sometimes dispatches this on another thread
            dispatch_async(dispatch_get_main_queue()) {
                if let definiteError = error {
                    self.didReceiveWebsocketError(definiteError)
                }
            }
            logger.error("socket error: \(error!.localizedDescription)")
        }
    }
    
    public func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        logger.debug("received: \(text)")
        
        let data = text.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
        
        if data != nil {
            let error = NSErrorPointer()
            let json: AnyObject?
            do {
                json = try NSJSONSerialization.JSONObjectWithData(
                                data!,
                                options: NSJSONReadingOptions(rawValue: 0))
            } catch let error1 as NSError {
                error.memory = error1
                json = nil
            }
            
            if json != nil {
                if let array = json as? [AnyObject] {
                    for object in array {
                        tryReadSerializedMessage(object)
                    }
                } else {
                    tryReadSerializedMessage(json!)
                }
            }
        }
    }
    
    func tryReadSerializedMessage(object: AnyObject) {
        if let dictionary = object as? [String: AnyObject] {
            let message = NetworkMessage.unserializeDictionary(dictionary)
            if message != nil {
                switch message! {
                case let pingMessage as PingMessage:
                    pingMessageReceived(pingMessage)
                default:
                    break
                }
                onMessage.fire(message!)
            }
        }
    }
    
    public func websocketDidReceiveData(socket: WebSocket, data: NSData) {
        logger.debug("received data (len=\(data.length)")
    }
    
    // MARK: - Interal Interface
    func tryConnect() {
        if status != .Connecting {
            return
        }
        
        if canReachHost() {
            socket.connect()
        } else {
            delay(0.1) {
                self.tryConnect()
            }
        }
    }
    
    func transportMessage(message: NetworkMessage) {
        if status != .Connected {
            return
        }
        
        let dictionary = message.serialize()
        let error = NSErrorPointer()
        let json: NSData?
        do {
            json = try NSJSONSerialization.dataWithJSONObject(
                        dictionary,
                        options: NSJSONWritingOptions(rawValue: 0))
        } catch let error1 as NSError {
            error.memory = error1
            json = nil
        }
        
        if let definiteJSON = json {
            if let str = NSString(data: definiteJSON, encoding: NSUTF8StringEncoding) {
                socket.writeString(str as String)
                logger.debug("sent: \(str)")
            }
        }
    }
    
    func startPingTimer() {
        stopPingTimer()
        let varianceLowerBound = Static.inactivityPingIntervalSeconds - (Static.inactivityPingIntervalVarianceSeconds / 2)
        let randomVariance = Double(arc4random_uniform(UInt32(Static.inactivityPingIntervalVarianceSeconds)))
        let delay = varianceLowerBound + randomVariance
        
        pingTimer = NSTimer.scheduledTimerWithTimeInterval(
            delay,
            target: self,
            selector: Selector("pingTimerFired"),
            userInfo: nil,
            repeats: false)
    }
    
    func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    func pingTimerFired() {
        sendMessage(PingMessage(session: session!))
        startPingTimer()
    }
    
    func pingMessageReceived(pingMessage: PingMessage) {
        nonAckedSends = nonAckedSends.filter { $0.index > pingMessage.ack }
        
        if pingMessage.resendMissing {
            for message in nonAckedSends {
                transportMessage(message)
            }
        }
    }
    
    func canReachHost() -> Bool {
        var hostAddress = sockaddr_in(
            sin_len: 0,
            sin_family: 0,
            sin_port: 0,
            sin_addr: in_addr(s_addr: 0),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        hostAddress.sin_len = UInt8(sizeofValue(hostAddress))
        hostAddress.sin_family = sa_family_t(AF_INET)
        hostAddress.sin_port = UInt16(UInt(options.url.port!))
        inet_pton(AF_INET, options.url.host!, &hostAddress.sin_addr)
        
        let defaultRouteReachability = withUnsafePointer(&hostAddress) {
            SCNetworkReachabilityCreateWithAddress(nil, UnsafePointer($0))
        }

        var flags = SCNetworkReachabilityFlags.ConnectionAutomatic
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }

        let isReachable: Bool = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection: Bool = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let transientConnection: Bool = (flags.rawValue & UInt32(kSCNetworkFlagsTransientConnection)) != 0
        let interventionRequired: Bool = (flags.rawValue & UInt32(kSCNetworkFlagsInterventionRequired)) != 0

        return isReachable && !needsConnection && (!transientConnection || !interventionRequired)        
    }
}
