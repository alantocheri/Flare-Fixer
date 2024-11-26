//
//  ContentView.swift
//  Flare Fixer
//
//  Created by Alan Tocheri on 2024-11-25.
//

import SwiftUI
import SwiftData
import PDFKit
import Vision
import UniformTypeIdentifiers
import Quartz
import CoreText

struct ContentView: View {
    @State private var selectedPDF: URL?

    var body: some View {
        VStack {
            Button("Select PDF") {
                selectPDF { url in
                    self.selectedPDF = url
                    if let pdfURL = url {
                        processPDF(at: pdfURL)
                    }
                }
            }
            .padding()

            if let pdfURL = selectedPDF {
                Text("Selected File: \(pdfURL.lastPathComponent)")
                    .padding()
            } else {
                Text("No File Selected")
                    .italic()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 400, height: 200)
    }

    func selectPDF(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK {
                completion(panel.url)
            } else {
                completion(nil)
            }
        }
    }

    func processPDF(at url: URL) {
        print("Processing PDF at URL: \(url.path)")
        guard let pdfDocument = PDFDocument(url: url) else {
            print("Failed to open PDF")
            return
        }

        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            if let pageText = page.string, !pageText.isEmpty {
                print("Text extracted from page \(pageIndex): \(pageText)")
                if isGarbled(text: pageText) {
                    print("Garbled text detected on page \(pageIndex), performing OCR...")
                    if let correctedText = performOCR(on: page) {
                        recreatePDF(with: correctedText, originalPage: page)
                    }
                } else {
                    print("Text on page \(pageIndex) is not garbled.")
                }
            } else {
                print("No text found on page \(pageIndex), performing OCR...")
                if let correctedText = performOCR(on: page) {
                    recreatePDF(with: correctedText, originalPage: page)
                }
            }
        }
        print("PDF processing complete!")
    }

    func isGarbled(text: String) -> Bool {
        print("Checking if text is garbled...")
        
        // Define ASCII character set
        let asciiCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?")
        
        // Count ASCII-readable characters
        let filteredText = text.filter { char in
            String(char).rangeOfCharacter(from: asciiCharacterSet) != nil
        }
        let readabilityRatio = Double(filteredText.count) / Double(text.count)
        print("Readability ratio: \(readabilityRatio)")
        
        // Additional checks for garbled text
        let nonAlphanumericRatio = 1.0 - readabilityRatio
        let hasExcessiveSymbols = nonAlphanumericRatio > 0.1 // More than 10% symbols
        let hasFewMeaningfulWords = text.split(separator: " ").count < 5 // Fewer than 5 words

        let isGarbled = readabilityRatio < 0.9 || hasExcessiveSymbols || hasFewMeaningfulWords
        print("Text is garbled: \(isGarbled)")
        return isGarbled
    }

    func performOCR(on page: PDFPage) -> String? {
        print("Performing OCR on page...")
        
        // Get the page's thumbnail as an NSImage
        let pageImage = page.thumbnail(of: page.bounds(for: .mediaBox).size, for: .mediaBox)
        
        // Convert NSImage to CGImage
        guard let cgImage = pageImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to convert NSImage to CGImage")
            return nil
        }
        
        // Perform OCR using Vision
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        do {
            try requestHandler.perform([request])
            
            // Unwrap the results
            guard let observations = request.results else {
                print("No text recognized")
                return nil
            }
            
            // Extract text directly from observations
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            print("OCR result: \(recognizedText)")
            return recognizedText
        } catch {
            print("OCR failed: \(error)")
            return nil
        }
    }


    func recreatePDF(with text: String, originalPage: PDFPage) {
        print("Recreating PDF page with corrected text...")
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                print("Save canceled or failed")
                return
            }
            
            var pageBounds = originalPage.bounds(for: .mediaBox)
            guard let context = CGContext(url as CFURL, mediaBox: &pageBounds, nil) else {
                print("Failed to create PDF context")
                return
            }
            print("PDF context created")
            
            context.beginPDFPage(nil)
            print("Started new PDF page")
            
            // Placeholder rectangle (for debugging position)
            context.setFillColor(NSColor.yellow.cgColor)
            context.fill(CGRect(x: 50, y: 50, width: 200, height: 50))
            print("Placeholder rectangle drawn")
            
            // Use Core Text to draw the OCR text
            print("OCR text being drawn: \(text)")
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: NSColor.black.cgColor
            ]
            let attributedString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString!)
            let path = CGPath(rect: CGRect(x: 100, y: 100, width: pageBounds.width - 200, height: pageBounds.height - 200), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, text.count), path, nil)
            CTFrameDraw(frame, context)
            
            print("OCR text drawing completed")
            
            context.endPDFPage()
            context.closePDF()
            print("Recreated PDF saved to \(url.path)")
        }
    }
    
    func savePDF(_ pdfDocument: PDFDocument) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                pdfDocument.write(to: url)
                print("Saved corrected PDF to \(url.path)")
                
                // Confirmation message
                let alert = NSAlert()
                alert.messageText = "PDF Saved Successfully"
                alert.informativeText = "Your corrected PDF has been saved to: \(url.path)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } else {
                print("Save canceled or failed")
            }
        }
    }
}
