//
//  ContentView.swift
//  Flare Fixer
//
//  Created by Alan Tocheri on 2024-11-25.
//

import SwiftUI
import PDFKit
import Vision

import SwiftUI

struct ContentView: View {
    @State private var rawText: String = "" // For displaying the combined extracted text
    @State private var orderNumber: String = ""
    @State private var orderDate: String = ""
    @State private var recipientName: String = ""
    @State private var recipientAddress: String = "" // Condensed address

    var body: some View {
        VStack(alignment: .leading) {
            Button("Select PDF") {
                selectPDF()
            }
            .padding()

            // Raw Extracted Text Debugging
            if !rawText.isEmpty {
                GroupBox(label: Text("Raw Extracted Text")) {
                    ScrollView {
                        Text(rawText)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .padding()
                    }
                    .frame(height: 200)
                }
                .padding()
            }

            // Extracted Fields
            if !orderNumber.isEmpty {
                GroupBox(label: Text("Order Details")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Order Number: \(orderNumber)")
                            Spacer()
                            Button("Copy") {
                                copyToClipboard(orderNumber)
                            }
                        }

                        HStack {
                            Text("Order Date: \(orderDate)")
                            Spacer()
                            Button("Copy") {
                                copyToClipboard(orderDate)
                            }
                        }
                    }
                }
                .padding()
            }

            if !recipientName.isEmpty || !recipientAddress.isEmpty {
                GroupBox(label: Text("Recipient")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(recipientName)
                            .fontWeight(.bold)

                        HStack {
                            Text(recipientAddress)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Button("Copy") {
                                copyToClipboard(recipientAddress)
                            }
                        }
                    }
                }
                .padding()
            }

            Spacer()
        }
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 500, alignment: .leading)
        .padding()
    }

    func selectPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                processPDF(at: url)
            }
        }
    }

    func isGarbled(text: String) -> Bool {
        print("Checking if text is garbled...")
        let asciiCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?")
        
        // Filter out non-ASCII characters
        let filteredText = text.filter { char in
            String(char).rangeOfCharacter(from: asciiCharacterSet) != nil
        }
        let readabilityRatio = Double(filteredText.count) / Double(text.count)
        print("Readability ratio: \(readabilityRatio)")
        
        // Determine garbled text based on readability
        return readabilityRatio < 0.9 // Adjust threshold as needed
    }
    
    func cleanText(_ text: String) -> String {
        // Replace multiple newlines with a single newline
        let cleanedText = text
            .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedText
    }

    func copyToClipboard(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    func processPDF(at url: URL) {
        print("Started processing PDF: \(url.lastPathComponent)") // High-level log for file processing
        
        guard let pdfDocument = PDFDocument(url: url) else {
            print("Failed to load PDF: \(url.path)")
            return
        }
        
        var combinedText = ""
        
        for pageIndex in 0..<pdfDocument.pageCount {
            print("Processing page \(pageIndex + 1) of \(pdfDocument.pageCount)...") // Log page count

            if let page = pdfDocument.page(at: pageIndex) {
                if let pageText = page.string, !pageText.isEmpty {
                    // Check if the text is garbled
                    if isGarbled(text: pageText) {
                        print("Page \(pageIndex + 1): Garbled text detected, using OCR...")
                        if let ocrText = performOCR(on: page) {
                            combinedText += "Page \(pageIndex + 1) (OCR):\n\(cleanText(ocrText))\n\n"
                            print("Page \(pageIndex + 1): OCR text successfully extracted.")
                        } else {
                            combinedText += "Page \(pageIndex + 1): No text found (even with OCR).\n\n"
                            print("Page \(pageIndex + 1): OCR failed or no text found.")
                        }
                    } else {
                        print("Page \(pageIndex + 1): Readable text detected.")
                        combinedText += "Page \(pageIndex + 1):\n\(cleanText(pageText))\n\n"
                    }
                } else {
                    // No text found, fallback to OCR
                    print("Page \(pageIndex + 1): No text layer found, attempting OCR...")
                    if let ocrText = performOCR(on: page) {
                        combinedText += "Page \(pageIndex + 1) (OCR):\n\(cleanText(ocrText))\n\n"
                        print("Page \(pageIndex + 1): OCR text successfully extracted.")
                    } else {
                        combinedText += "Page \(pageIndex + 1): No text found (even with OCR).\n\n"
                        print("Page \(pageIndex + 1): OCR failed or no text found.")
                    }
                }
            } else {
                print("Page \(pageIndex + 1): Failed to access page content.")
            }
        }
        
        rawText = combinedText // Update the raw text for debugging
        print("Finished processing PDF. Total pages processed: \(pdfDocument.pageCount).")
        
        // Extract structured fields
        extractFields(from: combinedText)
        print("Field extraction completed.")
    }
    
    
    func performOCR(on page: PDFPage) -> String? {
        guard let image = page.thumbnail(of: page.bounds(for: .mediaBox).size, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to generate CGImage for OCR")
            return nil
        }
        
        let request = VNRecognizeTextRequest()
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        
        do {
            try requestHandler.perform([request])
            guard let observations = request.results else {
                print("No text recognized by OCR")
                return nil
            }
            let recognizedText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return recognizedText
        } catch {
            print("OCR failed: \(error)")
            return nil
        }
    }

    func extractFields(from text: String) {
        if let orderMatch = text.range(of: #"Order #(\S+)"#, options: .regularExpression) {
            orderNumber = String(text[orderMatch]).replacingOccurrences(of: "Order #", with: "")
        }
        
        if let dateMatch = text.range(of: #"placed on (\w+ \d{1,2}, \d{4})"#, options: .regularExpression) {
            orderDate = String(text[dateMatch]).replacingOccurrences(of: "placed on ", with: "")
        }
        
        if let recipientMatch = text.range(of: #"Invoice issued for and on behalf of:\n(.+)\n(.+)\n(.+)"#, options: .regularExpression) {
            let recipientData = text[recipientMatch].components(separatedBy: "\n")
            recipientName = recipientData[0].trimmingCharacters(in: .whitespacesAndNewlines)
            recipientAddress = recipientData.dropFirst().joined(separator: "\n")
        }
    }
    
}
