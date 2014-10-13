//
//  ShapesDemoViewController.swift
//  JetstreamDemos
//
//  Created by Rob Skillington on 9/24/14.
//  Copyright (c) 2014 Uber Technologies, Inc. All rights reserved.
//

import Foundation
import UIKit
import Jetstream

class ShapesDemoViewController: UIViewController, NSURLConnectionDataDelegate {
    var scope = Scope(name: "ShapesDemo")
    var shapesDemo = ShapesDemo()

    var client: Client?
    var session: Session?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Shapes Demo"

        let tapRecognizer = UITapGestureRecognizer(target: self, action: Selector("handleTap:"))
        self.view.addGestureRecognizer(tapRecognizer)
        
        shapesDemo.setScopeAndMakeRootModel(scope)
        shapesDemo.observeCollectionAdd(self, keyPath: "shapes") { (element: Shape) in
            let shapeView = ShapeView(shape: element)
            self.view.addSubview(shapeView)
        }
    }
    
    func handleTap(recognizer: UITapGestureRecognizer) {
        let shape = Shape()
        shape.color = shapeColors[Int(arc4random_uniform(UInt32(shapeColors.count)))]
        var point = recognizer.locationInView(self.view)
        shape.x = point.x - shape.width / 2
        shape.y = point.y - shape.height / 2
        shapesDemo.shapes.append(shape)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        showLoader()
        
        client = Client(options: WebsocketConnectionOptions(url: "ws://" + host + ":3000"))
        client?.connect()
        client?.onSession.listenOnce(self) { (session) in
            self.session = session
            let scope = self.scope
            session.fetch(scope) { (error) in
                if error != nil {
                    self.alertError("Error fetching scope", message: "\(error)")
                } else {
                    self.hideLoader()
                }
            }
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        hideLoader()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        client?.onSession.removeListener(self)
        client?.close()
        client = nil
    }
}
