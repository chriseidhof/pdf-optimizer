//
//  ContentView.swift
//  PDFOptimizer
//
//  Created by Chris Eidhof on 13.05.20.
//  Copyright © 2020 objc.io. All rights reserved.
//

import SwiftUI

struct ProgressIndicator: NSViewRepresentable {
    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {}
    
    func makeNSView(context: Context) -> NSProgressIndicator {
        let v = NSProgressIndicator()
        v.style = .spinning
        v.startAnimation(nil)
        return v
    }
}

struct ContentView: View {
    @State var active: Bool = false
    @State var outputURL: URL? = nil
    @State var formattedSize: String? = nil
    @State var hover = false
    @State var processing: Bool = false

    var body: some View {
        let delegate = Delegate(processing: $processing, outputURL: $outputURL, formattedSize: $formattedSize)
        return VStack {
            if processing {
                ProgressIndicator()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .overlay(Text("Drag Here..."))
                    .frame(width: 200, height: 200)
            }
            if outputURL != nil {
                VStack {
                    Text("\(outputURL!.lastPathComponent)")
                        .padding()
                        .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
                        .scaleEffect(hover ? 1.1 : 1)
                        .onHover(perform: { self.hover = $0 })
                        .onDrag {
                            NSItemProvider(contentsOf: self.outputURL!)!
                    }
                    if formattedSize != nil {
                        Text(formattedSize!).padding()
                    }
                }.padding()
            }
        }
        .padding()
        .animation(.default)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: ["public.file-url"], delegate: delegate)

    }
}

struct ConversionError: Error {
}

func convert(_ url: URL) throws -> (String, URL) {
    /* TODO add some options
     
     See https://stackoverflow.com/questions/9497120/how-to-downsample-images-within-pdf-file/9571488#9571488
     
     */
    guard url.isFileURL, url.pathExtension == "pdf" else { throw ConversionError() }
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
    let unique = UUID().uuidString
    let pdfDir = tempDir.appendingPathComponent(unique)
    let name = url.deletingPathExtension().lastPathComponent
    let outputPDF = pdfDir.appendingPathComponent("\(name)-out.pdf")
    try FileManager.default.createDirectory(at: pdfDir, withIntermediateDirectories: true, attributes: [:])
    let task = Process()
    task.launchPath = "/usr/local/bin/gs"
    task.arguments = [
        "-sDEVICE=pdfwrite",
        "-dPDFSETTINGS=/printer",
        "-dCompatibilityLevel=1.4",
        "-r75",
        "-dNOPAUSE",
        "-dQUIET",
        "-dBATCH",
        "-sOutputFile=\(outputPDF.lastPathComponent)",
        url.path
    ]
    let pipe = Pipe()
    task.currentDirectoryPath = pdfDir.path
    task.standardError = pipe
    task.standardOutput = pipe
    task.launch()
    task.waitUntilExit()
    let data = try pipe.fileHandleForReading.readToEnd()
    let output = String(decoding: data ?? Data(), as: UTF8.self)
    return (output, outputPDF)
}

struct Delegate: DropDelegate {
    @Binding var processing: Bool
    @Binding var outputURL: URL?
    @Binding var formattedSize: String?
    
    
    func validateDrop(info: DropInfo) -> Bool {
        // todo check that it's a PDF?
        info.hasItemsConforming(to: ["public.file-url"])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        if let item = info.itemProviders(for: ["public.file-url"]).first {
            self.processing = true
            item.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (urlData, error) in
                if let urlData = urlData as? Data {
                    let u = NSURL(absoluteURLWithDataRepresentation: urlData, relativeTo: nil) as URL
                    DispatchQueue.global().async {
                        let (_, file) = try! convert(u)
                        let inputSize = try! FileManager.default.attributesOfItem(atPath: u.path)[.size] as! Int64
                        let fileSize = try! FileManager.default.attributesOfItem(atPath: file.path)[.size] as! Int64
                        let formatter = ByteCountFormatter()
                        formatter.countStyle = ByteCountFormatter.CountStyle.file
                        let formattedInputSize = formatter.string(fromByteCount: inputSize)
                        let formattedOutputSize = formatter.string(fromByteCount: fileSize)
                        let percentage = Int((Double(fileSize)/Double(inputSize)) * 100)
                        DispatchQueue.main.async {
                            self.outputURL = file
                            self.processing = false
                            self.formattedSize = "\(formattedInputSize) → \(formattedOutputSize) (\(percentage)% of original size)"
                        }
                    }
                }
            }
            return true
        } else {
            return false
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return nil
    }
    
    func dropExited(info: DropInfo) {
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
